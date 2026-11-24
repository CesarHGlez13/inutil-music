package com.inutilmusic.app.moment

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.Clock
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSourceBitmapLoader
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultAssetLoaderFactory
import androidx.media3.transformer.DefaultDecoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.roundToInt

/**
 * Extracts and trims `[startMs, endMs]` from any audio source supported by
 * ExoPlayer (YouTube WebM/Opus, M4A, MP3, FLAC, HLS, local files, custom HTTP
 * headers) into a clean 48 kHz AAC-LC `.m4a` with gentle fade-in/fade-out.
 */
@OptIn(UnstableApi::class)
class MomentAudioExtractor(private val context: Context) {

    fun extractClip(
        audioUri: String,
        httpHeaders: Map<String, String>,
        startMs: Long,
        endMs: Long,
        outputFile: File,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
    ) {
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) outputFile.delete()

        val durationMs = (endMs - startMs).coerceAtLeast(1000L)
        val thread = HandlerThread(
            "InutilMomentAudioExtract",
            Process.THREAD_PRIORITY_BACKGROUND,
        ).apply { start() }
        val handler = Handler(thread.looper)
        val latch = CountDownLatch(1)
        val errorRef = AtomicReference<Throwable?>(null)
        val finished = AtomicBoolean(false)
        val transformerRef = AtomicReference<Transformer?>(null)

        try {
            val resolvedUri = resolveUri(audioUri)
            val mediaItem = MediaItem.Builder()
                .setUri(resolvedUri)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(startMs.coerceAtLeast(0L))
                        .setEndPositionMs(endMs)
                        .build(),
                )
                .build()

            val fadeProcessor = MomentFadeAudioProcessor(
                clipDurationMs = durationMs,
                fadeInMs = 140L,
                fadeOutMs = 260L,
            )
            val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                .setRemoveVideo(true)
                .setEffects(Effects(listOf(fadeProcessor), emptyList()))
                .build()

            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15_000)
                .setReadTimeoutMs(20_000)
                .apply {
                    val userAgent = httpHeaders.entries.firstOrNull {
                        it.key.equals("User-Agent", ignoreCase = true)
                    }?.value ?: "InutilMusic/2.5"
                    setUserAgent(userAgent)
                    val filteredHeaders = httpHeaders.filterKeys {
                        !it.equals("User-Agent", ignoreCase = true)
                    }
                    if (filteredHeaders.isNotEmpty()) {
                        setDefaultRequestProperties(filteredHeaders)
                    }
                }
            val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
            val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            val assetLoaderFactory = DefaultAssetLoaderFactory(
                context,
                DefaultDecoderFactory.Builder(context).build(),
                Clock.DEFAULT,
                mediaSourceFactory,
                DataSourceBitmapLoader(context),
            )

            handler.post {
                if (isCancelled()) {
                    finished.set(true)
                    latch.countDown()
                    return@post
                }
                try {
                    val transformer = Transformer.Builder(context)
                        .setLooper(thread.looper)
                        .setAssetLoaderFactory(assetLoaderFactory)
                        .setAudioMimeType(MimeTypes.AUDIO_AAC)
                        .addListener(object : Transformer.Listener {
                            override fun onCompleted(
                                composition: Composition,
                                exportResult: ExportResult,
                            ) {
                                if (finished.compareAndSet(false, true)) {
                                    onProgress(1f)
                                    latch.countDown()
                                }
                            }

                            override fun onError(
                                composition: Composition,
                                exportResult: ExportResult,
                                exportException: ExportException,
                            ) {
                                if (finished.compareAndSet(false, true)) {
                                    errorRef.set(exportException)
                                    latch.countDown()
                                }
                            }
                        })
                        .build()

                    transformerRef.set(transformer)
                    transformer.start(editedMediaItem, outputFile.absolutePath)

                    val progressHolder = ProgressHolder()
                    val pollRunnable = object : Runnable {
                        override fun run() {
                            if (finished.get()) return
                            if (isCancelled()) {
                                try {
                                    transformer.cancel()
                                } catch (_: Throwable) {
                                }
                                if (finished.compareAndSet(false, true)) {
                                    latch.countDown()
                                }
                                return
                            }
                            try {
                                val state = transformer.getProgress(progressHolder)
                                if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                                    onProgress((progressHolder.progress / 100f).coerceIn(0f, 1f))
                                }
                            } catch (_: Throwable) {
                            }
                            handler.postDelayed(this, 80L)
                        }
                    }
                    handler.postDelayed(pollRunnable, 80L)
                } catch (t: Throwable) {
                    if (finished.compareAndSet(false, true)) {
                        errorRef.set(t)
                        latch.countDown()
                    }
                }
            }

            latch.await()
            if (isCancelled()) {
                outputFile.delete()
                throw InterruptedException("Moment export cancelled")
            }
            errorRef.get()?.let { throw it }
            if (!outputFile.exists() || outputFile.length() == 0L) {
                throw IllegalStateException("Audio extraction produced an empty file")
            }
        } finally {
            handler.post {
                try {
                    if (!finished.get()) {
                        transformerRef.get()?.cancel()
                    }
                } catch (_: Throwable) {
                }
            }
            thread.quitSafely()
        }
    }

    private fun resolveUri(raw: String): Uri {
        val trimmed = raw.trim()
        return if (trimmed.startsWith("/")) {
            Uri.fromFile(File(trimmed))
        } else {
            Uri.parse(trimmed)
        }
    }
}

/**
 * Applies a short, smooth cosine-shaped fade-in and fade-out directly on 16-bit
 * PCM frames so exported clips never click or cut off harshly.
 */
@OptIn(UnstableApi::class)
private class MomentFadeAudioProcessor(
    private val clipDurationMs: Long,
    private val fadeInMs: Long,
    private val fadeOutMs: Long,
) : BaseAudioProcessor() {

    private var processedFrames: Long = 0L
    private var totalFrames: Long = 0L
    private var fadeInFrames: Long = 0L
    private var fadeOutFrames: Long = 0L

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat,
    ): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            return AudioProcessor.AudioFormat.NOT_SET
        }
        val sampleRate = inputAudioFormat.sampleRate.toLong().coerceAtLeast(1L)
        totalFrames = (clipDurationMs * sampleRate) / 1000L
        fadeInFrames = (fadeInMs * sampleRate) / 1000L
        fadeOutFrames = (fadeOutMs * sampleRate) / 1000L
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return

        val channels = inputAudioFormat.channelCount.coerceAtLeast(1)
        val frameBytes = channels * 2
        val frameCount = remaining / frameBytes
        val out = replaceOutputBuffer(remaining)

        for (f in 0 until frameCount) {
            val frameIndex = processedFrames + f
            val gain = computeGain(frameIndex)
            for (c in 0 until channels) {
                val sample = inputBuffer.short
                val scaled = if (gain >= 0.9999f) {
                    sample
                } else {
                    (sample * gain).roundToInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                }
                out.putShort(scaled)
            }
        }
        // Copy any trailing bytes if non-aligned (rare).
        while (inputBuffer.hasRemaining()) {
            out.put(inputBuffer.get())
        }
        processedFrames += frameCount
        out.flip()
    }

    override fun onFlush() {
        processedFrames = 0L
    }

    override fun onReset() {
        processedFrames = 0L
    }

    private fun computeGain(frameIndex: Long): Float {
        var gain = 1f
        if (fadeInFrames > 0L && frameIndex < fadeInFrames) {
            gain = (frameIndex.toFloat() / fadeInFrames.toFloat()).coerceIn(0f, 1f)
        }
        if (fadeOutFrames > 0L && totalFrames > fadeOutFrames) {
            val fadeOutStart = totalFrames - fadeOutFrames
            if (frameIndex > fadeOutStart) {
                val outGain = ((totalFrames - frameIndex).toFloat() / fadeOutFrames.toFloat())
                    .coerceIn(0f, 1f)
                gain = minOf(gain, outGain)
            }
        }
        return gain
    }
}
