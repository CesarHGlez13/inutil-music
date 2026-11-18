package com.inutilmusic.app

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.util.LongSparseArray
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.metadata.MetadataOutput
import androidx.media3.exoplayer.text.TextOutput
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.atomic.AtomicLong

/**
 * Motor dedicado exclusivamente a video de fondo (Spotify Canvas / Artwork animado /
 * Video Preview) completamente aislado de la pista de música:
 *
 *  - RenderersFactory estrictamente de video (cero AudioRenderer, cero AudioTrack,
 *    cero AudioFlinger, cero AudioFocus).
 *  - Looper de reproducción propio con prioridad inferior al audio
 *    (Process.THREAD_PRIORITY_LESS_FAVORABLE) para no robar CPU al stream musical.
 *  - Buffer compacto (DefaultLoadControl 1.5s–4s) que evita picos al cargar el clip.
 *  - Bucle nativo en hardware (REPEAT_MODE_ALL + reposicionamiento nativo al
 *    startOffset) sin lecturas GPU->CPU (toImage) ni pausas intermedias.
 */
class InutilCanvasEnginePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var appContext: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var playbackThread: HandlerThread? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nextPlayerId = AtomicLong(1L)
    private val players = LongSparseArray<CanvasPlayerInstance>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        textureRegistry = binding.textureRegistry
        val messenger: BinaryMessenger = binding.binaryMessenger

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@InutilCanvasEnginePlugin)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
            setStreamHandler(this@InutilCanvasEnginePlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        disposeAll()
        playbackThread?.quitSafely()
        playbackThread = null
        appContext = null
        textureRegistry = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> handleCreate(call, result)
            "setPlaying" -> handleSetPlaying(call, result)
            "dispose" -> handleDispose(call, result)
            else -> result.notImplemented()
        }
    }

    private fun ensurePlaybackLooper(): Looper {
        val existing = playbackThread
        if (existing != null && existing.isAlive) {
            return existing.looper
        }
        val created = HandlerThread(
            "InutilCanvasPlayback",
            Process.THREAD_PRIORITY_LESS_FAVORABLE,
        ).apply { start() }
        playbackThread = created
        return created.looper
    }

    @OptIn(UnstableApi::class)
    private fun handleCreate(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        val registry = textureRegistry
        if (context == null || registry == null) {
            result.error("unavailable", "Canvas engine not attached", null)
            return
        }
        val uri = call.argument<String>("uri")?.trim().orEmpty()
        if (uri.isEmpty()) {
            result.error("invalid_args", "Missing video uri", null)
            return
        }
        val startOffsetMs = (call.argument<Number>("startOffsetMs")?.toLong() ?: 0L).coerceAtLeast(0L)
        val durationHintMs = (call.argument<Number>("durationHintMs")?.toLong() ?: 0L).coerceAtLeast(0L)
        val shouldPlay = call.argument<Boolean>("playing") ?: true

        val producer = registry.createSurfaceProducer()
        val textureId = producer.id()
        val playerId = nextPlayerId.getAndIncrement()

        val instance = CanvasPlayerInstance(
            id = playerId,
            context = context,
            playbackLooper = ensurePlaybackLooper(),
            mainHandler = mainHandler,
            surfaceProducer = producer,
            uri = uri,
            startOffsetMs = startOffsetMs,
            durationHintMs = durationHintMs,
            initialPlaying = shouldPlay,
            onEvent = { payload -> emitEvent(payload) },
        )
        players.put(playerId, instance)

        result.success(
            mapOf(
                "playerId" to playerId,
                "textureId" to textureId,
            ),
        )
    }

    private fun handleSetPlaying(call: MethodCall, result: MethodChannel.Result) {
        val playerId = (call.argument<Number>("playerId"))?.toLong()
        val playing = call.argument<Boolean>("playing") ?: false
        if (playerId != null) {
            players.get(playerId)?.setDesiredPlaying(playing)
        }
        result.success(null)
    }

    private fun handleDispose(call: MethodCall, result: MethodChannel.Result) {
        val playerId = (call.argument<Number>("playerId"))?.toLong()
        if (playerId != null) {
            players.get(playerId)?.let {
                players.remove(playerId)
                it.dispose()
            }
        }
        result.success(null)
    }

    private fun disposeAll() {
        for (i in 0 until players.size()) {
            players.valueAt(i).dispose()
        }
        players.clear()
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(payload)
        } else {
            mainHandler.post { eventSink?.success(payload) }
        }
    }

    private companion object {
        const val METHOD_CHANNEL = "inutil_music/canvas_video"
        const val EVENT_CHANNEL = "inutil_music/canvas_video/events"
    }
}

@OptIn(UnstableApi::class)
private class VideoOnlyRenderersFactory(
    context: Context,
) : DefaultRenderersFactory(context) {
    init {
        setEnableDecoderFallback(true)
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioTrackPlaybackParams: Boolean,
    ): AudioSink? = null

    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>,
    ) {
        // Sin renderer de audio: jamás crea AudioTrack ni toca AudioFlinger.
    }

    override fun buildTextRenderers(
        context: Context,
        output: TextOutput,
        outputLooper: Looper,
        extensionRendererMode: Int,
        out: ArrayList<Renderer>,
    ) {
        // Sin subtítulos.
    }

    override fun buildMetadataRenderers(
        context: Context,
        output: MetadataOutput,
        outputLooper: Looper,
        extensionRendererMode: Int,
        out: ArrayList<Renderer>,
    ) {
        // Sin metadatos cronometrados.
    }
}

@OptIn(UnstableApi::class)
private class CanvasPlayerInstance(
    private val id: Long,
    context: Context,
    playbackLooper: Looper,
    private val mainHandler: Handler,
    private val surfaceProducer: TextureRegistry.SurfaceProducer,
    uri: String,
    private val startOffsetMs: Long,
    private val durationHintMs: Long,
    initialPlaying: Boolean,
    private val onEvent: (Map<String, Any?>) -> Unit,
) : TextureRegistry.SurfaceProducer.Callback, Player.Listener {

    private var desiredPlaying: Boolean = initialPlaying
    private var disposed: Boolean = false
    private var readySent: Boolean = false
    private var firstFrameRendered: Boolean = false
    private var introSettled: Boolean = startOffsetMs == 0L
    private var introSeekDispatched: Boolean = false
    private var fastForwardingIntro: Boolean = false
    private var needsSurface: Boolean = true

    private val exoPlayer: ExoPlayer

    private val introMonitorRunnable = object : Runnable {
        override fun run() {
            if (disposed || introSettled) return
            val pos = exoPlayer.currentPosition
            if (pos >= startOffsetMs) {
                introSettled = true
                if (fastForwardingIntro) {
                    fastForwardingIntro = false
                    exoPlayer.setPlaybackParameters(PlaybackParameters(1f))
                }
                maybePublishReady()
                return
            }
            mainHandler.postDelayed(this, 60L)
        }
    }

    init {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(1_500, 4_000, 250, 500)
            .setPrioritizeTimeOverSizeThresholds(false)
            .build()

        exoPlayer = ExoPlayer.Builder(context, VideoOnlyRenderersFactory(context))
            .setPlaybackLooper(playbackLooper)
            .setLoadControl(loadControl)
            .setAudioAttributes(AudioAttributes.DEFAULT, /* handleAudioFocus = */ false)
            .setHandleAudioBecomingNoisy(false)
            .setWakeMode(C.WAKE_MODE_NONE)
            .setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING)
            .build()

        exoPlayer.volume = 0f
        exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .setTrackTypeDisabled(C.TRACK_TYPE_METADATA, true)
            .build()

        exoPlayer.repeatMode = Player.REPEAT_MODE_ALL
        exoPlayer.addListener(this)

        surfaceProducer.setCallback(this)
        val surface = surfaceProducer.surface
        if (surface != null) {
            exoPlayer.setVideoSurface(surface)
            needsSurface = false
        }

        // Arranca silenciado para decodificar el primer frame (y saltar el intro
        // si hay startOffset) antes de mostrar el video en pantalla.
        exoPlayer.setMediaItem(MediaItem.fromUri(uri))
        exoPlayer.playWhenReady = true
        exoPlayer.prepare()
    }

    fun setDesiredPlaying(playing: Boolean) {
        if (disposed) return
        desiredPlaying = playing
        if (!readySent) return
        if (playing) {
            if (!exoPlayer.isPlaying) exoPlayer.play()
        } else {
            if (exoPlayer.isPlaying) exoPlayer.pause()
        }
    }

    override fun onSurfaceAvailable() {
        if (disposed || !needsSurface) return
        val surface = surfaceProducer.surface
        if (surface != null) {
            exoPlayer.setVideoSurface(surface)
            needsSurface = false
        }
    }

    override fun onSurfaceCleanup() {
        if (disposed) return
        exoPlayer.setVideoSurface(null)
        needsSurface = true
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (disposed) return
        if (playbackState == Player.STATE_READY && startOffsetMs > 0L && !introSeekDispatched) {
            introSeekDispatched = true
            val rawDuration = exoPlayer.duration
            val effectiveDuration = if (rawDuration > 1L) rawDuration else durationHintMs
            if (effectiveDuration in 1L..(startOffsetMs + 2_000L)) {
                emitError("Artwork clip is shorter than its intro")
                return
            }
            if (exoPlayer.isCurrentMediaItemSeekable) {
                exoPlayer.seekTo(startOffsetMs)
            }
            if (exoPlayer.currentPosition < startOffsetMs) {
                mainHandler.removeCallbacks(introMonitorRunnable)
                mainHandler.post(introMonitorRunnable)
            } else {
                introSettled = true
            }
            maybePublishReady()
        } else if (playbackState == Player.STATE_READY) {
            maybePublishReady()
        }
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        if (disposed) return
        // Cuando REPEAT_MODE_ALL vuelve al inicio de un clip con intro (p. ej. 8s),
        // salta directamente al punto de bucle dentro del mismo ExoPlayer sin pausar
        // ni recapturar frames en Flutter.
        if (reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION &&
            startOffsetMs > 0L &&
            newPosition.positionMs < startOffsetMs - 400L
        ) {
            if (exoPlayer.isCurrentMediaItemSeekable) {
                exoPlayer.seekTo(startOffsetMs)
            } else {
                introSettled = false
                if (!fastForwardingIntro) {
                    fastForwardingIntro = true
                    exoPlayer.setPlaybackParameters(PlaybackParameters(8f))
                }
                mainHandler.removeCallbacks(introMonitorRunnable)
                mainHandler.post(introMonitorRunnable)
            }
        }
    }

    override fun onRenderedFirstFrame() {
        if (disposed) return
        firstFrameRendered = true
        if (startOffsetMs > 0L && !introSettled) {
            if (exoPlayer.currentPosition >= startOffsetMs) {
                introSettled = true
            } else if (!exoPlayer.isCurrentMediaItemSeekable && !fastForwardingIntro) {
                fastForwardingIntro = true
                exoPlayer.setPlaybackParameters(PlaybackParameters(8f))
                mainHandler.removeCallbacks(introMonitorRunnable)
                mainHandler.post(introMonitorRunnable)
            }
        }
        maybePublishReady()
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (disposed || !readySent) return
        if (isVideoSizeAllowed(videoSize.width, videoSize.height)) {
            onEvent(
                mapOf(
                    "playerId" to id,
                    "event" to "size",
                    "width" to videoSize.width.toDouble(),
                    "height" to videoSize.height.toDouble(),
                    "rotation" to resolveRotationDegrees(videoSize),
                ),
            )
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        if (disposed) return
        emitError("Canvas decoder error: ${error.errorCodeName}")
    }

    private fun maybePublishReady() {
        if (disposed || readySent || !firstFrameRendered || !introSettled) return
        val size = exoPlayer.videoSize
        if (size.width <= 0 || size.height <= 0) return
        if (!isVideoSizeAllowed(size.width, size.height)) {
            emitError("Artwork video exceeds display budget")
            return
        }
        readySent = true
        if (desiredPlaying) {
            if (!exoPlayer.isPlaying) exoPlayer.play()
        } else {
            exoPlayer.pause()
        }
        onEvent(
            mapOf(
                "playerId" to id,
                "event" to "ready",
                "width" to size.width.toDouble(),
                "height" to size.height.toDouble(),
                "rotation" to resolveRotationDegrees(size),
            ),
        )
    }

    private fun isVideoSizeAllowed(width: Int, height: Int): Boolean =
        width > 0 &&
            height > 0 &&
            maxOf(width, height) <= 1920 &&
            width.toLong() * height.toLong() <= 2_200_000L

    private fun resolveRotationDegrees(videoSize: VideoSize): Int {
        if (Build.VERSION.SDK_INT <= 21) {
            return if (videoSize.unappliedRotationDegrees == 180) 180 else 0
        }
        if (surfaceProducer.handlesCropAndRotation()) {
            return 0
        }
        val raw = exoPlayer.videoFormat?.rotationDegrees ?: 0
        return if (raw == 0 || raw == 90 || raw == 180 || raw == 270) raw else 0
    }

    private fun emitError(message: String) {
        mainHandler.removeCallbacks(introMonitorRunnable)
        onEvent(
            mapOf(
                "playerId" to id,
                "event" to "error",
                "message" to message,
            ),
        )
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        mainHandler.removeCallbacks(introMonitorRunnable)
        surfaceProducer.setCallback(null)
        exoPlayer.removeListener(this)
        exoPlayer.release()
        surfaceProducer.release()
    }
}
