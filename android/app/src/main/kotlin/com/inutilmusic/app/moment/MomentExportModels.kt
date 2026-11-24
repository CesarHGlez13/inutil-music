package com.inutilmusic.app.moment

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import kotlin.math.roundToInt

enum class MomentMode {
    LYRICS,
    PLAYER;

    companion object {
        fun parse(raw: String?): MomentMode = when (raw?.trim()?.lowercase()) {
            "player" -> PLAYER
            else -> LYRICS
        }
    }
}

data class MomentLyricWord(
    val text: String,
    val startMs: Long,
    val endMs: Long,
    val startOffset: Int,
    val endOffset: Int,
)

data class MomentLyricLine(
    val timestampMs: Long,
    val text: String,
    val words: List<MomentLyricWord> = emptyList(),
)

data class MomentExportRequest(
    val jobId: String,
    val mode: MomentMode,
    val title: String,
    val artist: String,
    val album: String?,
    val audioUri: String,
    val audioHeaders: Map<String, String>,
    val videoUri: String?,
    val videoStartOffsetMs: Long,
    val artworkSource: String?,
    val accentColorArgb: Int,
    val startMs: Long,
    val endMs: Long,
    val trackDurationMs: Long,
    val lyricsOffsetMs: Long,
    val lyricsCentered: Boolean,
    val lyricsProviderLabel: String?,
    val lyrics: List<MomentLyricLine>,
    val outputPath: String,
) {
    val clipDurationMs: Long
        get() = (endMs - startMs).coerceIn(MIN_DURATION_MS, MAX_DURATION_MS)

    companion object {
        const val MIN_DURATION_MS = 5_000L
        const val MAX_DURATION_MS = 30_000L

        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<*, *>): MomentExportRequest {
            val jobId = (map["jobId"] as? String)?.trim().orEmpty().ifEmpty {
                "moment-${System.currentTimeMillis()}"
            }
            val mode = MomentMode.parse(map["mode"] as? String)
            val title = (map["title"] as? String)?.trim().orEmpty().ifEmpty { "Inútil Music" }
            val artist = (map["artist"] as? String)?.trim().orEmpty().ifEmpty { "Inútil Music" }
            val album = (map["album"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
            val audioUri = (map["audioUri"] as? String)?.trim().orEmpty()
            require(audioUri.isNotEmpty()) { "audioUri is required" }

            val rawHeaders = map["audioHeaders"] as? Map<*, *>
            val audioHeaders = buildMap<String, String> {
                rawHeaders?.forEach { (k, v) ->
                    val key = k?.toString()?.trim().orEmpty()
                    val value = v?.toString()?.trim().orEmpty()
                    if (key.isNotEmpty() && value.isNotEmpty()) {
                        put(key, value)
                    }
                }
            }

            val videoUri = (map["videoUri"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
            val videoStartOffsetMs = ((map["videoStartOffsetMs"] as? Number)?.toLong() ?: 0L)
                .coerceAtLeast(0L)
            val artworkSource = (map["artworkSource"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
            val accentColorArgb = (map["accentColorArgb"] as? Number)?.toInt()
                ?: 0xFF6C8CFF.toInt()
            val startMs = ((map["startMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
            val rawEndMs = (map["endMs"] as? Number)?.toLong() ?: (startMs + 15_000L)
            val endMs = rawEndMs.coerceIn(startMs + MIN_DURATION_MS, startMs + MAX_DURATION_MS)
            val trackDurationMs = ((map["trackDurationMs"] as? Number)?.toLong() ?: endMs)
                .coerceAtLeast(endMs)
            val lyricsOffsetMs = (map["lyricsOffsetMs"] as? Number)?.toLong() ?: 0L
            val lyricsCentered = map["lyricsCentered"] as? Boolean ?: false
            val lyricsProviderLabel = (map["lyricsProviderLabel"] as? String)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }

            val rawLyrics = map["lyrics"] as? List<*> ?: emptyList<Any>()
            val lyrics = rawLyrics.mapNotNull { item ->
                val lineMap = item as? Map<*, *> ?: return@mapNotNull null
                val text = (lineMap["text"] as? String)?.trim().orEmpty()
                if (text.isEmpty()) return@mapNotNull null
                val timestampMs = (lineMap["timestampMs"] as? Number)?.toLong() ?: 0L
                val rawWords = lineMap["words"] as? List<*> ?: emptyList<Any>()
                val words = rawWords.mapNotNull { wItem ->
                    val wMap = wItem as? Map<*, *> ?: return@mapNotNull null
                    val wText = (wMap["text"] as? String).orEmpty()
                    val wStart = (wMap["startMs"] as? Number)?.toLong() ?: return@mapNotNull null
                    val wEnd = (wMap["endMs"] as? Number)?.toLong() ?: return@mapNotNull null
                    val startOffset = (wMap["startOffset"] as? Number)?.toInt() ?: return@mapNotNull null
                    val endOffset = (wMap["endOffset"] as? Number)?.toInt() ?: return@mapNotNull null
                    if (wEnd <= wStart || endOffset <= startOffset || endOffset > text.length) {
                        return@mapNotNull null
                    }
                    MomentLyricWord(
                        text = wText,
                        startMs = wStart,
                        endMs = wEnd,
                        startOffset = startOffset,
                        endOffset = endOffset,
                    )
                }
                MomentLyricLine(
                    timestampMs = timestampMs,
                    text = text,
                    words = words,
                )
            }.sortedBy { it.timestampMs }

            val outputPath = (map["outputPath"] as? String)?.trim().orEmpty()
            require(outputPath.isNotEmpty()) { "outputPath is required" }

            return MomentExportRequest(
                jobId = jobId,
                mode = mode,
                title = title,
                artist = artist,
                album = album,
                audioUri = audioUri,
                audioHeaders = audioHeaders,
                videoUri = videoUri,
                videoStartOffsetMs = videoStartOffsetMs,
                artworkSource = artworkSource,
                accentColorArgb = accentColorArgb,
                startMs = startMs,
                endMs = endMs,
                trackDurationMs = trackDurationMs,
                lyricsOffsetMs = lyricsOffsetMs,
                lyricsCentered = lyricsCentered,
                lyricsProviderLabel = lyricsProviderLabel,
                lyrics = lyrics,
                outputPath = outputPath,
            )
        }
    }
}

data class MomentEncodingProfile(
    val width: Int,
    val height: Int,
    val fps: Int,
    val videoBitrateBps: Int,
    val iFrameIntervalSeconds: Int = 1,
    val preferHighProfile: Boolean = true,
) {
    companion object {
        /**
         * Selects the sharpest social-media-safe profile supported by this device's
         * hardware H.264 encoder:
         *  - 1080x1920 @ 60fps High Profile when supported (flagship iPhone parity)
         *  - 1080x1920 @ 30fps otherwise
         *  - 720x1280 @ 30fps fallback for legacy devices
         */
        fun selectForDevice(durationMs: Long): MomentEncodingProfile {
            val durationSec = (durationMs / 1000.0).coerceIn(5.0, 30.0)
            val fullHdBitrate = when {
                durationSec <= 15.5 -> 9_500_000
                durationSec <= 22.5 -> 8_000_000
                else -> 6_800_000
            }
            val hdBitrate = when {
                durationSec <= 15.5 -> 5_500_000
                else -> 4_600_000
            }

            if (supportsAvcEncoder(1080, 1920, 60.0)) {
                return MomentEncodingProfile(
                    width = 1080,
                    height = 1920,
                    fps = 60,
                    videoBitrateBps = fullHdBitrate,
                )
            }
            if (supportsAvcEncoder(1080, 1920, 30.0)) {
                return MomentEncodingProfile(
                    width = 1080,
                    height = 1920,
                    fps = 30,
                    videoBitrateBps = (fullHdBitrate * 0.85).roundToInt(),
                )
            }
            return MomentEncodingProfile(
                width = 720,
                height = 1280,
                fps = 30,
                videoBitrateBps = hdBitrate,
                preferHighProfile = false,
            )
        }

        private fun supportsAvcEncoder(width: Int, height: Int, fps: Double): Boolean {
            return try {
                val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                codecs.any { info ->
                    if (!info.isEncoder) return@any false
                    if (!info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) }) {
                        return@any false
                    }
                    // Skip software encoders when probing for 60fps flagship capability.
                    val nameLower = info.name.lowercase()
                    if (fps >= 59.0 && (nameLower.startsWith("omx.google.") || nameLower.startsWith("c2.android."))) {
                        return@any false
                    }
                    val caps = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                    val videoCaps = caps.videoCapabilities ?: return@any false
                    videoCaps.areSizeAndRateSupported(width, height, fps)
                }
            } catch (_: Throwable) {
                false
            }
        }
    }
}
