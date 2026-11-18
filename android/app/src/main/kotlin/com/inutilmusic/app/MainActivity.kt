package com.inutilmusic.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread

class MainActivity : AudioServiceActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingFileExportResult: MethodChannel.Result? = null
    private var pendingFileExportSourcePath: String? = null
    private val externalAudioHandler by lazy { ExternalAudioIntentHandler(this) }
    private val externalAudioExecutor = Executors.newSingleThreadExecutor()
    // Artwork reads are independent from catalog/intent resolution. Two
    // workers keep visible rows responsive without creating unbounded metadata
    // concurrency on slower storage.
    private val localArtworkExecutor = Executors.newFixedThreadPool(2)
    private val widgetArtworkExecutor = Executors.newSingleThreadExecutor()
    private var externalAudioChannel: MethodChannel? = null
    private val pendingExternalAudioEvents = ArrayDeque<Map<String, Any?>>()
    private var appActivationChannel: MethodChannel? = null
    private var homeWidgetChannel: MethodChannel? = null
    private var homeWidgetActionHandlerReady = false
    private var pendingHomeWidgetAction: String? = null
    private var pendingAppActivation: Map<String, Any>? = null
    private var pendingExternalAudioPermissionRequest: ExternalAudioRequest? = null
    private var audioPermissionRequestInFlight = false
    private var pendingLocalAudioPermissionResult: MethodChannel.Result? = null
    private var localAudioPermissionRequestInFlight = false
    private var notificationPermissionRequestInFlight = false
    private var statusBarHidden = false
    private var previousSystemUiVisibility: Int? = null
    private var previousSystemBarsBehavior: Int? = null
    private var audioOutputPlugin: AudioOutputPlugin? = null
    private var localAudioQualityPlugin: LocalAudioQualityPlugin? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // This app never stores or autofills account passwords.  Disable the
        // Android Autofill save prompt for the whole activity, including the
        // embedded Google sign-in WebView.  Session cookies are captured only
        // after the account flow succeeds and are kept in secure storage.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.decorView.importantForAutofill =
                View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        enablePreferredHighRefreshRate()
        if (!IncomingCsvFileBridge.accept(this, intent) &&
            !handleHomeWidgetActionIntent(intent) && !handleExternalAudioIntent(intent)) {
            handleAppActivationIntent(intent)
            requestNotificationPermissionIfNeeded()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        IncomingCsvFileBridge.attach(flutterEngine.dartExecutor.binaryMessenger)

        audioOutputPlugin?.dispose()
        audioOutputPlugin = AudioOutputPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        localAudioQualityPlugin?.dispose()
        localAudioQualityPlugin = LocalAudioQualityPlugin(
            this, flutterEngine.dartExecutor.binaryMessenger,
        )
        if (!flutterEngine.plugins.has(InutilCastEnginePlugin::class.java)) {
            flutterEngine.plugins.add(InutilCastEnginePlugin())
        }
        if (!flutterEngine.plugins.has(InutilCanvasEnginePlugin::class.java)) {
            flutterEngine.plugins.add(InutilCanvasEnginePlugin())
        }

        homeWidgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "inutil_music/home_widget",
        ).also { channel -> channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val data = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    // Serialize metadata and covers, including bitmap rendering,
                    // without doing disk or image work on the Android UI thread.
                    widgetArtworkExecutor.execute { InutilMusicWidget.update(this, data) }
                    result.success(null)
                }
                "updateArtwork" -> {
                    val data = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    widgetArtworkExecutor.execute { InutilMusicWidget.updateArtwork(this, data) }
                    result.success(null)
                }
                "updateArtworkBytes" -> {
                    val data = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    widgetArtworkExecutor.execute { InutilMusicWidget.updateArtworkBytes(this, data) }
                    result.success(null)
                }
                "registerActionHandler" -> {
                    homeWidgetActionHandlerReady = true
                    result.success(null)
                }
                "consumePendingAction" -> {
                    val action = pendingHomeWidgetAction
                    pendingHomeWidgetAction = null
                    result.success(action)
                }
                else -> result.notImplemented()
            }
        } }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_EXPORT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFile" -> saveFile(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> setKeepScreenOn(call, result)
                "setStatusBarHidden" -> setStatusBarHidden(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SUPPORTED_LINKS_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSupportedLinksSettings" -> openSupportedLinksSettings(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCAL_AUDIO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "permissionStatus" -> result.success(localAudioPermissionStatus())
                "requestPermission" -> requestLocalAudioPermission(result)
                "queryTracks" -> queryLocalAudioTracks(result)
                "loadArtwork" -> loadLocalAudioArtwork(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "primaryAbi" -> result.success(primaryInstallAbi())
                "canRequestPackageInstalls" ->
                    result.success(canRequestPackageInstalls())
                "openInstallUnknownAppsSettings" ->
                    openInstallUnknownAppsSettings(result)
                "installPackage" -> installDownloadedPackage(call, result)
                else -> result.notImplemented()
            }
        }

        appActivationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_ACTIVATION_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingActivation" -> {
                        val activation = pendingAppActivation
                        pendingAppActivation = null
                        result.success(activation)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        externalAudioChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_AUDIO_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingExternalAudioEvents" -> {
                        val pending = ArrayList(pendingExternalAudioEvents)
                        pendingExternalAudioEvents.clear()
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!IncomingCsvFileBridge.accept(this, intent) &&
            !handleHomeWidgetActionIntent(intent) && !handleExternalAudioIntent(intent)) {
            handleAppActivationIntent(intent)
        }
    }

    private fun handleHomeWidgetActionIntent(intent: Intent?): Boolean {
        if (intent?.action != ACTION_HOME_WIDGET_CONTROL) return false
        val action = intent.getStringExtra(EXTRA_HOME_WIDGET_ACTION)
            ?.takeIf(::isValidHomeWidgetAction)
            ?: return false
        val channel = homeWidgetChannel
        if (channel == null || !homeWidgetActionHandlerReady) {
            pendingHomeWidgetAction = action
        } else {
            pendingHomeWidgetAction = action
            channel.invokeMethod(
                "widgetAction",
                action,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (pendingHomeWidgetAction == action) {
                            pendingHomeWidgetAction = null
                        }
                    }

                    override fun error(code: String, message: String?, details: Any?) = Unit

                    override fun notImplemented() = Unit
                },
            )
        }
        return true
    }

    private fun isValidHomeWidgetAction(action: String): Boolean {
        if (action in HOME_WIDGET_ACTIONS) return true
        if (!action.startsWith(HOME_WIDGET_QUEUE_PREFIX)) return false
        val index = action.removePrefix(HOME_WIDGET_QUEUE_PREFIX).toIntOrNull() ?: return false
        return index >= 0
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            EXTERNAL_AUDIO_PERMISSION_REQUEST -> {
                audioPermissionRequestInFlight = false
                val request = pendingExternalAudioPermissionRequest
                pendingExternalAudioPermissionRequest = null
                val granted = hasAudioLibraryPermission()
                if (request != null) {
                    resolveExternalAudio(
                        request = request,
                        includeFolder = granted,
                        permissionPending = false,
                        permissionDenied = !granted,
                    )
                }
                completePendingLocalAudioPermission()
                requestNotificationPermissionIfNeeded()
            }
            LOCAL_AUDIO_PERMISSION_REQUEST -> {
                localAudioPermissionRequestInFlight = false
                completePendingLocalAudioPermission()
                requestExternalAudioPermissionIfNeeded()
                requestNotificationPermissionIfNeeded()
            }
            NOTIFICATION_PERMISSION_REQUEST -> {
                notificationPermissionRequestInFlight = false
                requestExternalAudioPermissionIfNeeded()
                requestLocalAudioPermissionIfNeeded()
            }
        }
    }

    override fun onDestroy() {
        audioOutputPlugin?.dispose()
        localAudioQualityPlugin?.dispose()
        externalAudioExecutor.shutdownNow()
        localArtworkExecutor.shutdownNow()
        widgetArtworkExecutor.shutdownNow()
        pendingLocalAudioPermissionResult?.error(
            "activity_destroyed",
            "The Android activity was closed before audio permission completed.",
            null,
        )
        pendingLocalAudioPermissionResult = null
        super.onDestroy()
    }

    /**
     * ABI principal del dispositivo. El OTA la usa para elegir el APK dividido
     * publicado en Firestore (`arm64-v8a`, `armeabi-v7a`, `x86_64`, ...).
     */
    private fun primaryInstallAbi(): String = Build.SUPPORTED_ABIS.firstOrNull() ?: ""

    /**
     * Android 8+ exige el permiso de runtime `REQUEST_INSTALL_PACKAGES` para
     * abrir el instalador con un APK descargado fuera de la Play Store.
     */
    private fun canRequestPackageInstalls(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    private fun openInstallUnknownAppsSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(true)
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            Log.w(TAG, "Unknown-sources settings unavailable", error)
            result.success(false)
        }
    }

    /**
     * Abre el instalador de paquetes con el APK que el OTA descargó dentro de
     * `getExternalStorageDirectory()/updates`.
     *
     * El archivo se expone con `FileProvider` como `content://` porque desde
     * Android 7 (API 24, el `minSdk` de esta app) una URI `file://` que sale de
     * la aplicación lanza `FileUriExposedException`. El permiso de lectura se
     * otorga sólo a la actividad del instalador
     * (`FLAG_GRANT_READ_URI_PERMISSION`) y se revoca al cerrarla, así que no
     * queda ningún acceso persistente ni notificación de ningún tipo. La app
     * permanece viva: el audio gestionado por `audio_service` sigue sonando
     * mientras el usuario acepta el instalador.
     */
    private fun installDownloadedPackage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("invalid_path", "Falta la ruta del APK.", null)
            return
        }
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            result.error(
                "missing_file",
                "El paquete descargado ya no existe en el almacenamiento.",
                null,
            )
            return
        }
        val apkUri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (error: IllegalArgumentException) {
            result.error(
                "unshared_path",
                "El paquete descargado está fuera de las carpetas compartidas " +
                    "con el instalador.",
                null,
            )
            return
        }
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(apkUri, "application/vnd.android.package-archive")
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        try {
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            Log.w(TAG, "Package installer unavailable", error)
            result.error(
                "no_installer",
                "No hay ninguna aplicación que pueda instalar este paquete.",
                null,
            )
        }
    }

    private fun saveFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingFileExportResult != null) {
            result.error("export_busy", "Ya hay una exportación en curso.", null)
            return
        }

        val sourcePath = call.requiredString("sourcePath")
        val source = File(sourcePath)
        if (!source.exists() || !source.isFile) {
            result.error("export_missing", "No se encontró el archivo para exportar.", null)
            return
        }

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mimeType") ?: "application/zip"
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName") ?: source.name)
        }
        pendingFileExportResult = result
        pendingFileExportSourcePath = sourcePath
        try {
            startActivityForResult(intent, FILE_EXPORT_REQUEST)
        } catch (error: Throwable) {
            clearPendingFileExport()
            result.error("export_start_failed", error.message, error.stackTraceToString())
        }
    }

    private fun setKeepScreenOn(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        result.success(null)
    }

    private fun setStatusBarHidden(call: MethodCall, result: MethodChannel.Result) {
        statusBarHidden = call.argument<Boolean>("hidden") ?: false
        applyStatusBarVisibility()
        result.success(null)
    }

    @Suppress("DEPRECATION")
    private fun applyStatusBarVisibility() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (statusBarHidden) {
                if (previousSystemBarsBehavior == null) {
                    previousSystemBarsBehavior = controller.systemBarsBehavior
                }
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsets.Type.statusBars())
            } else {
                controller.show(WindowInsets.Type.statusBars())
                previousSystemBarsBehavior?.let { controller.systemBarsBehavior = it }
                previousSystemBarsBehavior = null
            }
            return
        }

        val decorView = window.decorView
        if (statusBarHidden) {
            if (previousSystemUiVisibility == null) {
                previousSystemUiVisibility = decorView.systemUiVisibility
            }
            decorView.systemUiVisibility =
                previousSystemUiVisibility!! or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        } else {
            previousSystemUiVisibility?.let { decorView.systemUiVisibility = it }
            previousSystemUiVisibility = null
        }
    }

    override fun onResume() {
        super.onResume()
        enablePreferredHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && statusBarHidden) {
            applyStatusBarVisibility()
        }
    }

    @Suppress("DEPRECATION")
    private fun enablePreferredHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val activeDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                windowManager?.defaultDisplay
            } ?: return
            val currentMode = activeDisplay.mode ?: return
            val bestMode = activeDisplay.supportedModes
                .filter {
                    it.physicalWidth == currentMode.physicalWidth &&
                        it.physicalHeight == currentMode.physicalHeight
                }
                .maxByOrNull { it.refreshRate }
                ?: return
            if (bestMode.modeId != window.attributes.preferredDisplayModeId &&
                bestMode.refreshRate > currentMode.refreshRate + 0.5f
            ) {
                window.attributes = window.attributes.apply {
                    preferredDisplayModeId = bestMode.modeId
                }
            }
        } catch (_: Throwable) {
            // Keep platform default display mode when OEM restricts mode switching.
        }
    }

    @Deprecated("Deprecated in the Android framework, required by the document picker callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != FILE_EXPORT_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingFileExportResult ?: return
        val sourcePath = pendingFileExportSourcePath
        if (resultCode != Activity.RESULT_OK) {
            clearPendingFileExport()
            result.success(null)
            return
        }
        val destination = data?.data
        if (sourcePath == null || destination == null) {
            clearPendingFileExport()
            result.error("export_destination_missing", "No se obtuvo el destino del respaldo.", null)
            return
        }

        thread(name = "InutilBackupExport") {
            try {
                File(sourcePath).inputStream().buffered().use { input ->
                    val output = contentResolver.openOutputStream(destination, "w")
                        ?: throw IllegalStateException("No se pudo abrir el destino del respaldo.")
                    output.buffered().use { input.copyTo(it, DEFAULT_BUFFER_SIZE) }
                }
                mainHandler.post {
                    clearPendingFileExport()
                    result.success(destination.toString())
                }
            } catch (error: Throwable) {
                mainHandler.post {
                    clearPendingFileExport()
                    result.error("export_failed", error.message, error.stackTraceToString())
                }
            }
        }
    }

    private fun clearPendingFileExport() {
        pendingFileExportResult = null
        pendingFileExportSourcePath = null
    }

    private fun handleExternalAudioIntent(intent: Intent?): Boolean {
        if (!externalAudioHandler.accepts(intent)) {
            return false
        }
        val safeIntent = Intent(intent!!)
        retainExternalAudioPermission(safeIntent)
        val request = ExternalAudioRequest(
            UUID.randomUUID().toString(),
            safeIntent,
            appEntryGeneration.incrementAndGet(),
        )

        if (hasAudioLibraryPermission()) {
            resolveExternalAudio(
                request = request,
                includeFolder = true,
                permissionPending = false,
                permissionDenied = false,
            )
            requestNotificationPermissionIfNeeded()
            return true
        }

        // The URI grant from ACTION_VIEW is enough to begin the selected file.
        // The library permission is requested only to discover its siblings.
        resolveExternalAudio(
            request = request,
            includeFolder = false,
            permissionPending = true,
            permissionDenied = false,
        )
        pendingExternalAudioPermissionRequest = request
        requestExternalAudioPermissionIfNeeded()
        return true
    }

    private fun retainExternalAudioPermission(intent: Intent) {
        if (intent.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION == 0) {
            return
        }
        val uri = intent.data ?: return
        val flags = intent.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (flags == 0) {
            return
        }
        runCatching { contentResolver.takePersistableUriPermission(uri, flags) }
    }

    private fun resolveExternalAudio(
        request: ExternalAudioRequest,
        includeFolder: Boolean,
        permissionPending: Boolean,
        permissionDenied: Boolean,
    ) {
        externalAudioExecutor.execute {
            try {
                val payload = externalAudioHandler.resolve(
                    requestId = request.id,
                    intent = request.intent,
                    includeFolder = includeFolder,
                    permissionPending = permissionPending,
                    permissionDenied = permissionDenied,
                )
                val eventPayload = payload.toMutableMap().apply {
                    put("entryGeneration", request.entryGeneration)
                    put(
                        "openPlayer",
                        request.entryGeneration == appEntryGeneration.get(),
                    )
                }
                Log.i(
                    EXTERNAL_AUDIO_TAG,
                    "Resolved external audio: tracks=" +
                        "${(eventPayload["tracks"] as? List<*>)?.size ?: 0}, " +
                        "selected=${eventPayload["selectedIndex"]}, " +
                        "folderComplete=${eventPayload["folderQueueComplete"]}, " +
                        "permissionPending=$permissionPending",
                )
                mainHandler.post { emitExternalAudio(eventPayload) }
            } catch (error: Throwable) {
                Log.e(TAG, "Could not resolve external audio", error)
            }
        }
    }

    private fun emitExternalAudio(payload: Map<String, Any?>) {
        while (pendingExternalAudioEvents.size >= MAX_PENDING_EXTERNAL_AUDIO_EVENTS) {
            pendingExternalAudioEvents.removeFirst()
        }
        pendingExternalAudioEvents.addLast(payload)
        val channel = externalAudioChannel ?: return
        channel.invokeMethod(
            "externalAudio",
            payload,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true) {
                        pendingExternalAudioEvents.removeFirstOccurrence(payload)
                    }
                }

                override fun error(code: String, message: String?, details: Any?) = Unit

                override fun notImplemented() = Unit
            },
        )
    }

    private fun openSupportedLinksSettings(result: MethodChannel.Result) {
        val packageUri = Uri.parse("package:$packageName")
        val candidates = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            candidates += Intent(
                "android.settings.APP_OPEN_BY_DEFAULT_SETTINGS",
                packageUri,
            )
        }
        candidates += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
        candidates += Intent(Settings.ACTION_SETTINGS)

        for (candidate in candidates) {
            try {
                startActivity(candidate)
                result.success(true)
                return
            } catch (error: Exception) {
                Log.w(TAG, "No se pudo abrir ${candidate.action}", error)
            }
        }
        result.success(false)
    }

    private fun requestExternalAudioPermissionIfNeeded() {
        val pendingRequest = pendingExternalAudioPermissionRequest ?: return
        if (hasAudioLibraryPermission()) {
            pendingExternalAudioPermissionRequest = null
            resolveExternalAudio(
                request = pendingRequest,
                includeFolder = true,
                permissionPending = false,
                permissionDenied = false,
            )
            requestNotificationPermissionIfNeeded()
            return
        }
        if (audioPermissionRequestInFlight ||
            localAudioPermissionRequestInFlight ||
            notificationPermissionRequestInFlight
        ) {
            return
        }
        audioPermissionRequestInFlight = true
        requestPermissions(
            arrayOf(audioLibraryPermission()),
            EXTERNAL_AUDIO_PERMISSION_REQUEST,
        )
    }

    private fun hasAudioLibraryPermission(): Boolean {
        return checkSelfPermission(audioLibraryPermission()) == PackageManager.PERMISSION_GRANTED
    }

    private fun audioLibraryPermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun handleAppActivationIntent(intent: Intent?) {
        val activation = when {
            intent?.action == ACTION_OPEN_HOME -> APP_ACTIVATION_HOME
            intent?.action == AUDIO_SERVICE_NOTIFICATION_CLICK_ACTION -> APP_ACTIVATION_PLAYER
            intent?.action == Intent.ACTION_MAIN &&
                intent.hasCategory(Intent.CATEGORY_LAUNCHER) -> APP_ACTIVATION_HOME
            else -> null
        } ?: return
        emitAppActivation(
            activation = activation,
            entryGeneration = appEntryGeneration.incrementAndGet(),
        )
    }

    private fun emitAppActivation(activation: String, entryGeneration: Long) {
        val payload = mapOf(
            "activation" to activation,
            "entryGeneration" to entryGeneration,
        )
        pendingAppActivation = payload
        val channel = appActivationChannel ?: return
        channel.invokeMethod(
            "activate",
            payload,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true && pendingAppActivation == payload) {
                        pendingAppActivation = null
                    }
                }

                override fun error(code: String, message: String?, details: Any?) = Unit

                override fun notImplemented() = Unit
            },
        )
    }

    private fun localAudioPermissionStatus(): String {
        return if (hasAudioLibraryPermission()) "granted" else "denied"
    }

    private fun requestLocalAudioPermission(result: MethodChannel.Result) {
        if (hasAudioLibraryPermission()) {
            result.success("granted")
            return
        }
        if (pendingLocalAudioPermissionResult != null) {
            result.error(
                "permission_request_busy",
                "An audio permission request is already pending.",
                null,
            )
            return
        }
        pendingLocalAudioPermissionResult = result
        requestLocalAudioPermissionIfNeeded()
    }

    private fun requestLocalAudioPermissionIfNeeded() {
        if (pendingLocalAudioPermissionResult == null) {
            return
        }
        if (hasAudioLibraryPermission()) {
            completePendingLocalAudioPermission()
            return
        }
        if (localAudioPermissionRequestInFlight ||
            audioPermissionRequestInFlight ||
            notificationPermissionRequestInFlight
        ) {
            return
        }
        localAudioPermissionRequestInFlight = true
        requestPermissions(
            arrayOf(audioLibraryPermission()),
            LOCAL_AUDIO_PERMISSION_REQUEST,
        )
    }

    private fun completePendingLocalAudioPermission() {
        val result = pendingLocalAudioPermissionResult ?: return
        pendingLocalAudioPermissionResult = null
        result.success(localAudioPermissionStatus())
    }

    private fun queryLocalAudioTracks(result: MethodChannel.Result) {
        if (!hasAudioLibraryPermission()) {
            result.error(
                "audio_permission_required",
                "Audio library permission is required.",
                null,
            )
            return
        }
        externalAudioExecutor.execute {
            try {
                val tracks = externalAudioHandler.queryLibrary()
                mainHandler.post { result.success(tracks) }
            } catch (error: Throwable) {
                Log.e(EXTERNAL_AUDIO_TAG, "Could not query the local audio catalog", error)
                mainHandler.post {
                    result.error(
                        "local_audio_query_failed",
                        error.message ?: "Could not query the local audio catalog.",
                        null,
                    )
                }
            }
        }
    }

    private fun loadLocalAudioArtwork(call: MethodCall, result: MethodChannel.Result) {
        if (!hasAudioLibraryPermission()) {
            result.error(
                "audio_permission_required",
                "Audio library permission is required.",
                null,
            )
            return
        }
        val audioUri = call.argument<String>("audioUri")?.trim()
        if (audioUri.isNullOrEmpty()) {
            result.error("invalid_audio_uri", "The audio URI is missing.", null)
            return
        }
        val targetWidth = (call.argument<Number>("targetWidth")?.toInt() ?: 256)
            .coerceIn(32, 1280)
        try {
            localArtworkExecutor.execute {
                try {
                    val bytes = externalAudioHandler.loadArtwork(audioUri, targetWidth)
                    mainHandler.post { result.success(bytes) }
                } catch (error: Throwable) {
                    Log.w(EXTERNAL_AUDIO_TAG, "Could not load local audio artwork", error)
                    mainHandler.post { result.success(null) }
                }
            }
        } catch (error: Throwable) {
            result.error(
                "local_artwork_unavailable",
                error.message ?: "Local artwork is unavailable.",
                null,
            )
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        if (notificationPermissionRequestInFlight ||
            audioPermissionRequestInFlight ||
            localAudioPermissionRequestInFlight ||
            pendingLocalAudioPermissionResult != null ||
            pendingExternalAudioPermissionRequest != null
        ) {
            return
        }
        notificationPermissionRequestInFlight = true
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun MethodCall.requiredString(name: String): String {
        return argument<String>(name)
            ?: throw IllegalArgumentException("Falta el argumento $name")
    }

    companion object {
        const val ACTION_HOME_WIDGET_CONTROL = "com.inutilmusic.app.HOME_WIDGET_CONTROL"
        const val EXTRA_HOME_WIDGET_ACTION = "home_widget_action"
        const val HOME_WIDGET_QUEUE_PREFIX = "queue:"
        private val HOME_WIDGET_ACTIONS = setOf("repeat", "favorite")
        private const val FILE_EXPORT_CHANNEL = "inutil_music/file_export"
        private const val SCREEN_CHANNEL = "inutil_music/screen"
        private const val SUPPORTED_LINKS_SETTINGS_CHANNEL =
            "inutil_music/supported_links_settings"
        private const val EXTERNAL_AUDIO_CHANNEL = "inutil_music/external_audio"
        private const val APP_ACTIVATION_CHANNEL = "inutil_music/app_activation"
        private const val APP_UPDATE_CHANNEL = "inutil_music/app_update"
        private const val LOCAL_AUDIO_CHANNEL = "inutil_music/local_audio"
        private const val AUDIO_SERVICE_NOTIFICATION_CLICK_ACTION =
            "com.ryanheise.audioservice.NOTIFICATION_CLICK"
        private const val APP_ACTIVATION_HOME = "home"
        private const val APP_ACTIVATION_PLAYER = "player"
        private val appEntryGeneration = AtomicLong(0)
        private const val NOTIFICATION_PERMISSION_REQUEST = 4010
        private const val FILE_EXPORT_REQUEST = 4011
        private const val EXTERNAL_AUDIO_PERMISSION_REQUEST = 4012
        private const val LOCAL_AUDIO_PERMISSION_REQUEST = 4013
        private const val MAX_PENDING_EXTERNAL_AUDIO_EVENTS = 8
        private const val TAG = "InutilAndroid"
        private const val EXTERNAL_AUDIO_TAG = "InutilExternalAudio"
    }

    private data class ExternalAudioRequest(
        val id: String,
        val intent: Intent,
        val entryGeneration: Long,
    )
}
