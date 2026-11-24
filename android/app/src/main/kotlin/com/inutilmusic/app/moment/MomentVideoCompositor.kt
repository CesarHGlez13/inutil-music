package com.inutilmusic.app.moment

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.roundToLong

/**
 * Hardware-accelerated offscreen 9:16 video compositor & MP4 encoder.
 *
 * Uses EGL 1.4 + OpenGL ES 2.0 feeding a hardware H.264 MediaCodec input Surface:
 *  1. Decodes an optional looping Canvas / Video Preview MP4 directly onto an
 *     OES GPU texture (center-cropped to 9:16 with cinematic dimming), OR draws
 *     a blurred Ken Burns album-artwork texture when no video exists.
 *  2. Composites the anti-aliased Skia foreground overlay (premultiplied alpha)
 *     at exact constant-framerate timestamps (60 fps on flagship devices).
 *  3. Muxes the encoded H.264 stream together with the Media3-extracted AAC
 *     audio file into a faststart MP4 ready for WhatsApp HD / Reels / TikTok.
 */
class MomentVideoCompositor {

    fun composeAndMux(
        request: MomentExportRequest,
        profile: MomentEncodingProfile,
        renderer: MomentOverlayRenderer,
        audioM4aFile: File,
        backgroundVideoFile: File?,
        fallbackBackgroundBitmap: Bitmap,
        rawMp4File: File,
        finalMp4File: File,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
    ) {
        val width = profile.width
        val height = profile.height
        val fps = profile.fps
        val durationMs = request.clipDurationMs
        val totalFrames = ((durationMs * fps) / 1000L).coerceAtLeast(fps.toLong()).toInt()

        var encoder: MediaCodec? = null
        var encoderSurface: Surface? = null
        var egl: EglContextHolder? = null
        var muxer: MediaMuxer? = null
        var videoSource: LoopingVideoSource? = null
        val overlayBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

        var muxerStarted = false
        var videoTrackIndex = -1
        var audioTrackIndex = -1
        var audioExtractor: MediaExtractor? = null
        var audioFormat: MediaFormat? = null

        try {
            // Prepare AAC audio extractor so MediaMuxer can register BOTH tracks before start().
            val aExt = MediaExtractor().apply { setDataSource(audioM4aFile.absolutePath) }
            audioExtractor = aExt
            for (i in 0 until aExt.trackCount) {
                val fmt = aExt.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("audio/")) {
                    aExt.selectTrack(i)
                    audioFormat = fmt
                    break
                }
            }
            requireNotNull(audioFormat) { "No audio track found in extracted clip" }

            // Configure hardware H.264 encoder with BT.709 color & High Profile.
            val enc = createVideoEncoder(profile)
            encoder = enc
            encoderSurface = enc.createInputSurface()
            enc.start()

            // Attach EGL context to encoder's hardware input Surface.
            val eglHolder = EglContextHolder(encoderSurface)
            egl = eglHolder
            eglHolder.makeCurrent()

            val gl = GlPipeline(width, height)
            gl.uploadBackgroundBitmap(fallbackBackgroundBitmap)
            gl.allocateOverlayTexture(width, height)

            // Open optional looping Canvas / Video Preview source on GPU OES texture.
            if (backgroundVideoFile != null && backgroundVideoFile.exists() && backgroundVideoFile.length() > 1024L) {
                try {
                    videoSource = LoopingVideoSource(
                        videoFile = backgroundVideoFile,
                        oesTextureId = gl.oesTextureId,
                        startOffsetMs = request.videoStartOffsetMs,
                    )
                } catch (t: Throwable) {
                    Log.w(TAG, "Falling back to artwork backdrop; video decode init failed: ${t.message}")
                    videoSource?.release()
                    videoSource = null
                }
            }

            rawMp4File.parentFile?.mkdirs()
            if (rawMp4File.exists()) rawMp4File.delete()
            muxer = MediaMuxer(rawMp4File.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val bufferInfo = MediaCodec.BufferInfo()
            val bgDimAlpha = when (request.mode) {
                MomentMode.LYRICS -> 0.44f
                MomentMode.PLAYER -> 0.14f
            }

            fun drainEncoder(endOfStream: Boolean) {
                if (endOfStream) {
                    enc.signalEndOfInputStream()
                }
                while (true) {
                    val outIdx = enc.dequeueOutputBuffer(bufferInfo, if (endOfStream) 10_000L else 0L)
                    when {
                        outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            if (!endOfStream) break
                        }
                        outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            check(!muxerStarted) { "Encoder output format changed twice" }
                            videoTrackIndex = muxer!!.addTrack(enc.outputFormat)
                            audioTrackIndex = muxer!!.addTrack(audioFormat!!)
                            muxer!!.start()
                            muxerStarted = true
                        }
                        outIdx >= 0 -> {
                            val encoded = enc.getOutputBuffer(outIdx)
                            if (encoded != null && bufferInfo.size > 0 &&
                                (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 &&
                                muxerStarted
                            ) {
                                encoded.position(bufferInfo.offset)
                                encoded.limit(bufferInfo.offset + bufferInfo.size)
                                muxer!!.writeSampleData(videoTrackIndex, encoded, bufferInfo)
                            }
                            enc.releaseOutputBuffer(outIdx, false)
                            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                break
                            }
                        }
                    }
                }
            }

            // Frame-by-frame deterministic 60fps/30fps hardware render loop.
            for (frameIndex in 0 until totalFrames) {
                if (isCancelled()) {
                    throw InterruptedException("Moment export cancelled")
                }

                val clipTimeNs = (frameIndex.toLong() * 1_000_000_000L) / fps.toLong()
                val clipTimeMs = clipTimeNs / 1_000_000L

                GLES20.glViewport(0, 0, width, height)
                GLES20.glClearColor(0.04f, 0.05f, 0.06f, 1f)
                GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

                // 1. Background layer: GPU-decoded Canvas video OR Ken Burns artwork.
                val vs = videoSource
                if (vs != null && vs.advanceTo(clipTimeNs / 1_000L)) {
                    gl.drawOesVideo(
                        stMatrix = vs.transformMatrix,
                        videoWidth = vs.displayWidth,
                        videoHeight = vs.displayHeight,
                        dimAlpha = bgDimAlpha,
                    )
                } else {
                    val kb = MomentOverlayRenderer.computeKenBurnsTransform(clipTimeMs)
                    gl.drawStaticBackground(
                        zoom = kb[0],
                        panX = kb[1],
                        panY = kb[2],
                        dimAlpha = if (request.mode == MomentMode.LYRICS) 0.28f else 0.08f,
                    )
                }

                // 2. Foreground Skia overlay (lyrics / player card / translucent watermark).
                renderer.drawFrame(overlayBitmap, clipTimeMs)
                gl.uploadAndDrawOverlay(overlayBitmap)

                // 3. Submit exact CFR presentation timestamp to hardware H.264 encoder.
                eglHolder.setPresentationTime(clipTimeNs)
                eglHolder.swapBuffers()

                drainEncoder(endOfStream = false)

                if (frameIndex % 6 == 0 || frameIndex == totalFrames - 1) {
                    onProgress((frameIndex + 1).toFloat() / totalFrames.toFloat())
                }
            }

            drainEncoder(endOfStream = true)

            // 4. Copy trimmed AAC audio track into the exact same MediaMuxer.
            if (muxerStarted && audioTrackIndex >= 0) {
                writeAudioTrack(
                    extractor = aExt,
                    muxer = muxer,
                    audioTrackIndex = audioTrackIndex,
                    maxDurationUs = durationMs * 1_000L,
                    isCancelled = isCancelled,
                )
            }

            gl.release()
        } finally {
            overlayBitmap.recycle()
            try { videoSource?.release() } catch (_: Throwable) {}
            try { audioExtractor?.release() } catch (_: Throwable) {}
            try {
                if (muxerStarted) muxer?.stop()
            } catch (_: Throwable) {}
            try { muxer?.release() } catch (_: Throwable) {}
            try { egl?.release() } catch (_: Throwable) {}
            try { encoder?.stop() } catch (_: Throwable) {}
            try { encoder?.release() } catch (_: Throwable) {}
            try { encoderSurface?.release() } catch (_: Throwable) {}
        }

        if (isCancelled()) {
            rawMp4File.delete()
            throw InterruptedException("Moment export cancelled")
        }

        // 5. Faststart relocation (moov before mdat) for instant playback on WhatsApp/IG/TikTok.
        finalMp4File.parentFile?.mkdirs()
        if (finalMp4File.exists()) finalMp4File.delete()
        val faststartOk = try {
            Mp4Faststart.optimize(rawMp4File, finalMp4File)
        } catch (t: Throwable) {
            Log.w(TAG, "Faststart relocation skipped: ${t.message}")
            false
        }
        if (!faststartOk) {
            rawMp4File.copyTo(finalMp4File, overwrite = true)
        }
        rawMp4File.delete()
    }

    private fun createVideoEncoder(profile: MomentEncodingProfile): MediaCodec {
        val format = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC,
            profile.width,
            profile.height,
        ).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, profile.videoBitrateBps)
            setInteger(MediaFormat.KEY_FRAME_RATE, profile.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, profile.iFrameIntervalSeconds)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
            }
        }

        // Try High Profile first (crisper iPhone-like detail), then fall back cleanly to default profile.
        if (profile.preferHighProfile) {
            try {
                val highFormat = MediaFormat.createVideoFormat(
                    MediaFormat.MIMETYPE_VIDEO_AVC,
                    profile.width,
                    profile.height,
                ).apply {
                    setInteger(
                        MediaFormat.KEY_COLOR_FORMAT,
                        MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                    )
                    setInteger(MediaFormat.KEY_BIT_RATE, profile.videoBitrateBps)
                    setInteger(MediaFormat.KEY_FRAME_RATE, profile.fps)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, profile.iFrameIntervalSeconds)
                    setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)
                    setInteger(
                        MediaFormat.KEY_LEVEL,
                        if (profile.fps >= 60) {
                            MediaCodecInfo.CodecProfileLevel.AVCLevel42
                        } else {
                            MediaCodecInfo.CodecProfileLevel.AVCLevel41
                        },
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                        setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                        setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                    }
                }
                val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                try {
                    codec.configure(highFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    return codec
                } catch (_: Throwable) {
                    codec.release()
                }
            } catch (_: Throwable) {
            }
        }

        val fallbackCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        fallbackCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        return fallbackCodec
    }

    private fun writeAudioTrack(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        audioTrackIndex: Int,
        maxDurationUs: Long,
        isCancelled: () -> Boolean,
    ) {
        val buf = ByteBuffer.allocate(256 * 1024)
        val info = MediaCodec.BufferInfo()
        var firstPtsUs = -1L
        var lastWrittenPtsUs = -1L

        while (!isCancelled()) {
            val size = extractor.readSampleData(buf, 0)
            if (size < 0) break
            val sampleTime = extractor.sampleTime
            if (sampleTime < 0L) {
                extractor.advance()
                continue
            }
            if (firstPtsUs < 0L) firstPtsUs = sampleTime
            val normalizedPts = (sampleTime - firstPtsUs).coerceAtLeast(0L)
            if (normalizedPts > maxDurationUs + 40_000L) break
            if (normalizedPts <= lastWrittenPtsUs) {
                extractor.advance()
                continue
            }
            info.offset = 0
            info.size = size
            info.presentationTimeUs = normalizedPts
            info.flags = extractor.sampleFlags
            muxer.writeSampleData(audioTrackIndex, buf, info)
            lastWrittenPtsUs = normalizedPts
            extractor.advance()
        }
    }

    companion object {
        private const val TAG = "MomentVideoCompositor"
    }
}

// =============================================================================
// Seamless Hardware-Decoded Looping Video Source (OES SurfaceTexture)
// =============================================================================
private class LoopingVideoSource(
    videoFile: File,
    oesTextureId: Int,
    startOffsetMs: Long,
) {
    private val extractor = MediaExtractor()
    private val decoder: MediaCodec
    private val surfaceTexture: SurfaceTexture
    private val surface: Surface
    private val callbackThread = HandlerThread("InutilMomentVideoDec").apply { start() }
    private val callbackHandler = Handler(callbackThread.looper)

    private var frameLatch: CountDownLatch? = null
    private val latchLock = Any()

    val transformMatrix = FloatArray(16)
    val displayWidth: Int
    val displayHeight: Int
    private val durationUs: Long
    private val startOffsetUs: Long

    private var hasAnyFrame = false
    private var lastDecodedPtsUs = -1L
    private var inputEos = false
    private var outputEos = false

    init {
        var metaDurationUs = 0L
        var metaRotation = 0
        var metaW = 1080
        var metaH = 1920
        val mmr = MediaMetadataRetriever()
        try {
            mmr.setDataSource(videoFile.absolutePath)
            metaDurationUs = (mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L) * 1000L
            metaRotation = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            metaW = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 1080
            metaH = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 1920
        } finally {
            try { mmr.release() } catch (_: Throwable) {}
        }

        extractor.setDataSource(videoFile.absolutePath)
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME).orEmpty()
            if (mime.startsWith("video/")) {
                trackIndex = i
                format = f
                break
            }
        }
        require(trackIndex >= 0 && format != null) { "No video track in background file" }
        extractor.selectTrack(trackIndex)

        val fmtW = format.getInteger(MediaFormat.KEY_WIDTH)
        val fmtH = format.getInteger(MediaFormat.KEY_HEIGHT)
        val rawW = if (fmtW > 0) fmtW else metaW
        val rawH = if (fmtH > 0) fmtH else metaH
        if (metaRotation == 90 || metaRotation == 270) {
            displayWidth = rawH
            displayHeight = rawW
        } else {
            displayWidth = rawW
            displayHeight = rawH
        }

        val fmtDur = if (format.containsKey(MediaFormat.KEY_DURATION)) {
            format.getLong(MediaFormat.KEY_DURATION)
        } else {
            0L
        }
        durationUs = max(metaDurationUs, fmtDur).coerceAtLeast(1_500_000L)
        val reqOffsetUs = startOffsetMs * 1000L
        startOffsetUs = if (durationUs > reqOffsetUs + 2_000_000L) reqOffsetUs else 0L

        surfaceTexture = SurfaceTexture(oesTextureId).apply {
            setOnFrameAvailableListener({
                synchronized(latchLock) {
                    frameLatch?.countDown()
                }
            }, callbackHandler)
        }
        surface = Surface(surfaceTexture)

        val mime = format.getString(MediaFormat.KEY_MIME)!!
        decoder = MediaCodec.createDecoderByType(mime).apply {
            configure(format, surface, null, 0)
            start()
        }

        if (startOffsetUs > 0L) {
            extractor.seekTo(startOffsetUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        }
        Matrix.setIdentityM(transformMatrix, 0)
    }

    /**
     * Advances the hardware video decoder smoothly to the looped timestamp for
     * `clipTimeUs`. Returns true when a valid OES texture frame is ready to draw.
     */
    fun advanceTo(clipTimeUs: Long): Boolean {
        val targetVideoUs = (startOffsetUs + clipTimeUs) % durationUs

        // Loop wrap: flush decoder & restart cleanly from start of file.
        if (hasAnyFrame && (targetVideoUs + 120_000L < lastDecodedPtsUs || outputEos)) {
            resetToBeginning()
        }

        // If our currently displayed frame is already at or ahead of targetVideoUs,
        // reuse it directly so 60fps overlay animations stay silky without extra decodes!
        if (hasAnyFrame && lastDecodedPtsUs >= targetVideoUs - 8_000L) {
            return true
        }

        val info = MediaCodec.BufferInfo()
        var iterations = 0
        while (iterations < 90 && !outputEos) {
            iterations++
            if (!inputEos) {
                val inIdx = decoder.dequeueInputBuffer(5_000L)
                if (inIdx >= 0) {
                    val buf = decoder.getInputBuffer(inIdx)
                    val sampleSize = if (buf != null) extractor.readSampleData(buf, 0) else -1
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(inIdx, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputEos = true
                    } else {
                        val pts = extractor.sampleTime.coerceAtLeast(0L)
                        decoder.queueInputBuffer(inIdx, 0, sampleSize, pts, 0)
                        extractor.advance()
                    }
                }
            }

            val outIdx = decoder.dequeueOutputBuffer(info, 8_000L)
            if (outIdx >= 0) {
                val isEos = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                if (isEos) {
                    decoder.releaseOutputBuffer(outIdx, false)
                    outputEos = true
                    break
                }
                val pts = info.presentationTimeUs
                val shouldRender = !hasAnyFrame || pts >= targetVideoUs - 18_000L
                if (shouldRender) {
                    val latch = CountDownLatch(1)
                    synchronized(latchLock) { frameLatch = latch }
                    decoder.releaseOutputBuffer(outIdx, true)
                    latch.await(250L, TimeUnit.MILLISECONDS)
                    surfaceTexture.updateTexImage()
                    surfaceTexture.getTransformMatrix(transformMatrix)
                    lastDecodedPtsUs = pts
                    hasAnyFrame = true
                    if (pts >= targetVideoUs - 18_000L) {
                        break
                    }
                } else {
                    decoder.releaseOutputBuffer(outIdx, false)
                    lastDecodedPtsUs = pts
                }
            }
        }
        return hasAnyFrame
    }

    private fun resetToBeginning() {
        try {
            decoder.flush()
            extractor.seekTo(0L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            inputEos = false
            outputEos = false
            lastDecodedPtsUs = -1L
        } catch (_: Throwable) {
        }
    }

    fun release() {
        try { decoder.stop() } catch (_: Throwable) {}
        try { decoder.release() } catch (_: Throwable) {}
        try { extractor.release() } catch (_: Throwable) {}
        try { surface.release() } catch (_: Throwable) {}
        try { surfaceTexture.release() } catch (_: Throwable) {}
        callbackThread.quitSafely()
    }
}

// =============================================================================
// EGL 1.4 Context Holder (Offscreen MediaCodec Input Surface)
// =============================================================================
private class EglContextHolder(surface: Surface) {
    private val display: EGLDisplay
    private val context: EGLContext
    private val eglSurface: EGLSurface

    init {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        require(display != EGL14.EGL_NO_DISPLAY) { "Unable to get EGL14 display" }
        val version = IntArray(2)
        require(EGL14.eglInitialize(display, version, 0, version, 1)) { "Unable to init EGL14" }

        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        require(EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, numConfigs, 0) && numConfigs[0] > 0) {
            "Unable to find recordable EGL config"
        }

        val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        context = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)
        require(context != EGL14.EGL_NO_CONTEXT) { "Unable to create EGL context" }

        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreateWindowSurface(display, configs[0], surface, surfaceAttribs, 0)
        require(eglSurface != EGL14.EGL_NO_SURFACE) { "Unable to create EGL window surface" }
    }

    fun makeCurrent() {
        require(EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context)) {
            "eglMakeCurrent failed"
        }
    }

    fun setPresentationTime(nanos: Long) {
        EGLExt.eglPresentationTimeANDROID(display, eglSurface, nanos)
    }

    fun swapBuffers() {
        EGL14.eglSwapBuffers(display, eglSurface)
    }

    fun release() {
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroySurface(display, eglSurface)
        EGL14.eglDestroyContext(display, context)
        EGL14.eglTerminate(display)
    }

    companion object {
        private const val EGL_RECORDABLE_ANDROID = 0x3142
    }
}

// =============================================================================
// OpenGL ES 2.0 Compositing Pipeline (OES Video + 2D Artwork + Premul Overlay)
// =============================================================================
private class GlPipeline(
    private val outWidth: Int,
    private val outHeight: Int,
) {
    private val quadVertices: FloatBuffer = ByteBuffer
        .allocateDirect(QUAD_DATA.size * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(QUAD_DATA)
            position(0)
        }

    private val oesProgram: Int
    private val tex2dProgram: Int

    val oesTextureId: Int
    private val bgTextureId: Int
    private val overlayTextureId: Int

    private val mvpMatrix = FloatArray(16)
    private val texMatrix = FloatArray(16)

    init {
        oesProgram = buildProgram(VERTEX_SHADER, FRAGMENT_SHADER_OES)
        tex2dProgram = buildProgram(VERTEX_SHADER, FRAGMENT_SHADER_2D)

        val textures = IntArray(3)
        GLES20.glGenTextures(3, textures, 0)
        oesTextureId = textures[0]
        bgTextureId = textures[1]
        overlayTextureId = textures[2]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        for (texId in intArrayOf(bgTextureId, overlayTextureId)) {
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texId)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        }
    }

    fun uploadBackgroundBitmap(bitmap: Bitmap) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, bgTextureId)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
    }

    fun allocateOverlayTexture(width: Int, height: Int) {
        val empty = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, empty, 0)
        empty.recycle()
    }

    fun drawOesVideo(stMatrix: FloatArray, videoWidth: Int, videoHeight: Int, dimAlpha: Float) {
        GLES20.glDisable(GLES20.GL_BLEND)
        GLES20.glUseProgram(oesProgram)

        // Center-crop scale to fill 9:16 cleanly without stretching.
        val outAspect = outWidth.toFloat() / outHeight.toFloat()
        val vidAspect = videoWidth.toFloat() / videoHeight.coerceAtLeast(1).toFloat()
        var scaleX = 1f
        var scaleY = 1f
        if (vidAspect > outAspect) {
            scaleX = vidAspect / outAspect
        } else {
            scaleY = outAspect / vidAspect
        }
        Matrix.setIdentityM(mvpMatrix, 0)
        Matrix.scaleM(mvpMatrix, 0, scaleX, scaleY, 1f)

        drawQuad(
            program = oesProgram,
            target = GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            textureId = oesTextureId,
            mvp = mvpMatrix,
            st = stMatrix,
            dimAlpha = dimAlpha,
        )
    }

    fun drawStaticBackground(zoom: Float, panX: Float, panY: Float, dimAlpha: Float) {
        GLES20.glDisable(GLES20.GL_BLEND)
        GLES20.glUseProgram(tex2dProgram)

        Matrix.setIdentityM(mvpMatrix, 0)
        Matrix.translateM(mvpMatrix, 0, panX, panY, 0f)
        Matrix.scaleM(mvpMatrix, 0, zoom, zoom, 1f)

        // Flip V coordinate for Android Bitmap top-to-bottom orientation.
        Matrix.setIdentityM(texMatrix, 0)
        Matrix.translateM(texMatrix, 0, 0f, 1f, 0f)
        Matrix.scaleM(texMatrix, 0, 1f, -1f, 1f)

        drawQuad(
            program = tex2dProgram,
            target = GLES20.GL_TEXTURE_2D,
            textureId = bgTextureId,
            mvp = mvpMatrix,
            st = texMatrix,
            dimAlpha = dimAlpha,
        )
    }

    fun uploadAndDrawOverlay(bitmap: Bitmap) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId)
        GLUtils.texSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, bitmap)

        // Android ARGB_8888 Bitmaps are premultiplied -> GL_ONE + GL_ONE_MINUS_SRC_ALPHA
        // prevents dark fringes around glowing text and translucent watermark!
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glUseProgram(tex2dProgram)

        Matrix.setIdentityM(mvpMatrix, 0)
        Matrix.setIdentityM(texMatrix, 0)
        Matrix.translateM(texMatrix, 0, 0f, 1f, 0f)
        Matrix.scaleM(texMatrix, 0, 1f, -1f, 1f)

        drawQuad(
            program = tex2dProgram,
            target = GLES20.GL_TEXTURE_2D,
            textureId = overlayTextureId,
            mvp = mvpMatrix,
            st = texMatrix,
            dimAlpha = 0f,
        )
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun drawQuad(
        program: Int,
        target: Int,
        textureId: Int,
        mvp: FloatArray,
        st: FloatArray,
        dimAlpha: Float,
    ) {
        val posLoc = GLES20.glGetAttribLocation(program, "aPosition")
        val texLoc = GLES20.glGetAttribLocation(program, "aTexCoord")
        val mvpLoc = GLES20.glGetUniformLocation(program, "uMvpMatrix")
        val stLoc = GLES20.glGetUniformLocation(program, "uTexMatrix")
        val dimLoc = GLES20.glGetUniformLocation(program, "uDimAlpha")

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(target, textureId)

        GLES20.glUniformMatrix4fv(mvpLoc, 1, false, mvp, 0)
        GLES20.glUniformMatrix4fv(stLoc, 1, false, st, 0)
        GLES20.glUniform1f(dimLoc, dimAlpha)

        quadVertices.position(0)
        GLES20.glVertexAttribPointer(posLoc, 2, GLES20.GL_FLOAT, false, 16, quadVertices)
        GLES20.glEnableVertexAttribArray(posLoc)

        quadVertices.position(2)
        GLES20.glVertexAttribPointer(texLoc, 2, GLES20.GL_FLOAT, false, 16, quadVertices)
        GLES20.glEnableVertexAttribArray(texLoc)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(posLoc)
        GLES20.glDisableVertexAttribArray(texLoc)
    }

    fun release() {
        GLES20.glDeleteTextures(3, intArrayOf(oesTextureId, bgTextureId, overlayTextureId), 0)
        GLES20.glDeleteProgram(oesProgram)
        GLES20.glDeleteProgram(tex2dProgram)
    }

    private fun buildProgram(vs: String, fs: String): Int {
        val v = compileShader(GLES20.GL_VERTEX_SHADER, vs)
        val f = compileShader(GLES20.GL_FRAGMENT_SHADER, fs)
        val p = GLES20.glCreateProgram()
        GLES20.glAttachShader(p, v)
        GLES20.glAttachShader(p, f)
        GLES20.glLinkProgram(p)
        GLES20.glDeleteShader(v)
        GLES20.glDeleteShader(f)
        return p
    }

    private fun compileShader(type: Int, src: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, src)
        GLES20.glCompileShader(shader)
        return shader
    }

    companion object {
        // Interleaved: X, Y, U, V
        private val QUAD_DATA = floatArrayOf(
            -1f, -1f, 0f, 0f,
             1f, -1f, 1f, 0f,
            -1f,  1f, 0f, 1f,
             1f,  1f, 1f, 1f,
        )

        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec4 aTexCoord;
            uniform mat4 uMvpMatrix;
            uniform mat4 uTexMatrix;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = uMvpMatrix * aPosition;
                vTexCoord = (uTexMatrix * aTexCoord).xy;
            }
        """

        private const val FRAGMENT_SHADER_OES = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES sTexture;
            uniform float uDimAlpha;
            void main() {
                vec4 c = texture2D(sTexture, vTexCoord);
                gl_FragColor = vec4(c.rgb * (1.0 - uDimAlpha), 1.0);
            }
        """

        private const val FRAGMENT_SHADER_2D = """
            precision mediump float;
            varying vec2 vTexCoord;
            uniform sampler2D sTexture;
            uniform float uDimAlpha;
            void main() {
                vec4 c = texture2D(sTexture, vTexCoord);
                gl_FragColor = vec4(c.rgb * (1.0 - uDimAlpha), c.a);
            }
        """
    }
}
