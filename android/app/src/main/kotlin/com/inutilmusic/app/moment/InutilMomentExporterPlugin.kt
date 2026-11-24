package com.inutilmusic.app.moment

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Native Android plugin for "Compartir momento".
 *
 * Exposes:
 *  - MethodChannel `inutil_music/moment_exporter`
 *      - `exportMoment(Map)` -> Map { outputPath, width, height, fps, sizeBytes, durationMs }
 *      - `cancelExport(jobId?)` -> Boolean
 *      - `probeCapabilities()` -> Map { width, height, fps }
 *  - EventChannel `inutil_music/moment_exporter/progress`
 *      - emits { jobId, stage, progress }
 */
class InutilMomentExporterPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var appContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "InutilMomentExportWorker").apply { isDaemon = true }
    }

    private val activeJobId = AtomicReference<String?>(null)
    private val activeCancelled = AtomicBoolean(false)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@InutilMomentExporterPlugin)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
            setStreamHandler(this@InutilMomentExporterPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        activeCancelled.set(true)
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        appContext = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exportMoment" -> handleExport(call, result)
            "cancelExport" -> {
                val targetJob = (call.arguments as? Map<*, *>)?.get("jobId") as? String
                val current = activeJobId.get()
                if (targetJob == null || targetJob == current) {
                    activeCancelled.set(true)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "probeCapabilities" -> {
                val profile = MomentEncodingProfile.selectForDevice(15_000L)
                result.success(
                    mapOf(
                        "width" to profile.width,
                        "height" to profile.height,
                        "fps" to profile.fps,
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("NO_CONTEXT", "Moment exporter is detached.", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("BAD_ARGS", "Expected export parameters map.", null)
            return
        }
        val request = try {
            MomentExportRequest.fromMap(args)
        } catch (t: Throwable) {
            result.error("BAD_ARGS", t.message ?: "Invalid export request", null)
            return
        }

        // Cancel any previous in-flight export cleanly.
        activeCancelled.set(true)
        worker.execute {
            activeJobId.set(request.jobId)
            activeCancelled.set(false)

            val tempDir = File(context.cacheDir, "inutil-moment-work/${request.jobId}").apply {
                mkdirs()
            }
            val audioM4a = File(tempDir, "audio.m4a")
            val bgVideo = File(tempDir, "bg.mp4")
            val rawMp4 = File(tempDir, "raw.mp4")
            val finalMp4 = File(request.outputPath)

            var artworkBitmap: Bitmap? = null
            var fallbackBgBitmap: Bitmap? = null
            var renderer: MomentOverlayRenderer? = null

            try {
                emitProgress(request.jobId, "preparing", 0.02f)

                val profile = MomentEncodingProfile.selectForDevice(request.clipDurationMs)

                // 1. Load artwork bitmap (local file or HTTP) for cover + fallback blur backdrop.
                artworkBitmap = loadArtworkBitmap(request.artworkSource)
                checkNotCancelled()

                // 2. Download optional background Canvas / Video Preview file (fast, typically 1–4 MB).
                val resolvedVideoFile = downloadVideoIfNeeded(
                    videoUri = request.videoUri,
                    dest = bgVideo,
                    isCancelled = { activeCancelled.get() },
                )
                checkNotCancelled()
                emitProgress(request.jobId, "audio", 0.12f)

                // 3. Extract & trim exact audio window [startMs, endMs] to AAC via Media3 Transformer.
                val audioExtractor = MomentAudioExtractor(context)
                audioExtractor.extractClip(
                    audioUri = request.audioUri,
                    httpHeaders = request.audioHeaders,
                    startMs = request.startMs,
                    endMs = request.endMs,
                    outputFile = audioM4a,
                    isCancelled = { activeCancelled.get() },
                    onProgress = { p ->
                        emitProgress(request.jobId, "audio", 0.12f + p * 0.23f)
                    },
                )
                checkNotCancelled()

                // 4. Prepare Skia overlay renderer & fallback background.
                emitProgress(request.jobId, "video", 0.36f)
                renderer = MomentOverlayRenderer(
                    context = context,
                    request = request,
                    width = profile.width,
                    height = profile.height,
                    artworkBitmap = artworkBitmap,
                )
                fallbackBgBitmap = renderer.createFallbackBackgroundBitmap(artworkBitmap)

                // 5. Render GPU frames + hardware H.264 encode + AAC mux + MP4 faststart.
                val compositor = MomentVideoCompositor()
                compositor.composeAndMux(
                    request = request,
                    profile = profile,
                    renderer = renderer,
                    audioM4aFile = audioM4a,
                    backgroundVideoFile = resolvedVideoFile,
                    fallbackBackgroundBitmap = fallbackBgBitmap,
                    rawMp4File = rawMp4,
                    finalMp4File = finalMp4,
                    isCancelled = { activeCancelled.get() },
                    onProgress = { p ->
                        emitProgress(request.jobId, "video", 0.36f + p * 0.60f)
                    },
                )
                checkNotCancelled()
                emitProgress(request.jobId, "done", 1.0f)

                val payload = mapOf(
                    "outputPath" to finalMp4.absolutePath,
                    "width" to profile.width,
                    "height" to profile.height,
                    "fps" to profile.fps,
                    "sizeBytes" to finalMp4.length(),
                    "durationMs" to request.clipDurationMs,
                )
                mainHandler.post { result.success(payload) }
            } catch (_: InterruptedException) {
                finalMp4.delete()
                mainHandler.post {
                    result.error("CANCELLED", "Export cancelled by user", null)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Moment export failed", t)
                finalMp4.delete()
                mainHandler.post {
                    result.error(
                        "EXPORT_FAILED",
                        t.message ?: t.javaClass.simpleName,
                        null,
                    )
                }
            } finally {
                try { renderer?.release() } catch (_: Throwable) {}
                try { fallbackBgBitmap?.recycle() } catch (_: Throwable) {}
                try { artworkBitmap?.recycle() } catch (_: Throwable) {}
                try { tempDir.deleteRecursively() } catch (_: Throwable) {}
                if (activeJobId.get() == request.jobId) {
                    activeJobId.set(null)
                }
            }
        }
    }

    private fun checkNotCancelled() {
        if (activeCancelled.get()) {
            throw InterruptedException("Moment export cancelled")
        }
    }

    private fun emitProgress(jobId: String, stage: String, progress: Float) {
        val clamped = progress.coerceIn(0f, 1f).toDouble()
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "jobId" to jobId,
                    "stage" to stage,
                    "progress" to clamped,
                ),
            )
        }
    }

    private fun loadArtworkBitmap(source: String?): Bitmap? {
        val trimmed = source?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        return try {
            when {
                trimmed.startsWith("http://", true) || trimmed.startsWith("https://", true) -> {
                    val conn = (URL(trimmed).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 10_000
                        readTimeout = 12_000
                        instanceFollowRedirects = true
                        setRequestProperty("User-Agent", "InutilMusic/2.5")
                    }
                    try {
                        if (conn.responseCode in 200..299) {
                            conn.inputStream.use { BitmapFactory.decodeStream(it) }
                        } else {
                            null
                        }
                    } finally {
                        conn.disconnect()
                    }
                }
                trimmed.startsWith("file://", true) -> {
                    val path = android.net.Uri.parse(trimmed).path ?: return null
                    BitmapFactory.decodeFile(path)
                }
                else -> {
                    val file = File(trimmed)
                    if (file.exists()) BitmapFactory.decodeFile(file.absolutePath) else null
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Artwork decode failed ($trimmed): ${t.message}")
            null
        }
    }

    private fun downloadVideoIfNeeded(
        videoUri: String?,
        dest: File,
        isCancelled: () -> Boolean,
    ): File? {
        val trimmed = videoUri?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        return try {
            when {
                trimmed.startsWith("file://", true) -> {
                    val f = File(android.net.Uri.parse(trimmed).path ?: return null)
                    if (f.exists()) f else null
                }
                trimmed.startsWith("/") -> {
                    val f = File(trimmed)
                    if (f.exists()) f else null
                }
                trimmed.startsWith("http://", true) || trimmed.startsWith("https://", true) -> {
                    val conn = (URL(trimmed).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 12_000
                        readTimeout = 20_000
                        instanceFollowRedirects = true
                        setRequestProperty("User-Agent", "InutilMusic/2.5")
                    }
                    try {
                        if (conn.responseCode !in 200..299) return null
                        dest.parentFile?.mkdirs()
                        conn.inputStream.use { input ->
                            FileOutputStream(dest).use { output ->
                                val buf = ByteArray(64 * 1024)
                                var totalBytes = 0L
                                while (!isCancelled()) {
                                    val n = input.read(buf)
                                    if (n <= 0) break
                                    output.write(buf, 0, n)
                                    totalBytes += n
                                    // Safety cap at 40 MB for background Canvas / video preview clips.
                                    if (totalBytes > 40L * 1024L * 1024L) {
                                        dest.delete()
                                        return null
                                    }
                                }
                            }
                        }
                        if (!isCancelled() && dest.exists() && dest.length() > 1024L) dest else null
                    } finally {
                        conn.disconnect()
                    }
                }
                else -> null
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Background video download skipped ($trimmed): ${t.message}")
            null
        }
    }

    companion object {
        const val METHOD_CHANNEL = "inutil_music/moment_exporter"
        const val EVENT_CHANNEL = "inutil_music/moment_exporter/progress"
        private const val TAG = "InutilMomentExporter"
    }
}
