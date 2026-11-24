package com.inutilmusic.app.moment

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Renders razor-sharp, anti-aliased 9:16 overlays for both "Letras" and
 * "Reproductor" moment clips, including the subtle translucent Inútil Music
 * logo watermark. All coordinates are authored in a 1080x1920 design grid and
 * scaled cleanly when targeting 720x1280 fallback devices.
 */
class MomentOverlayRenderer(
    private val context: Context,
    private val request: MomentExportRequest,
    val width: Int,
    val height: Int,
    artworkBitmap: Bitmap?,
) {
    private val scale = width / 1080f
    private val designW = 1080f
    private val designH = 1920f

    private val fontRegular: Typeface = loadBundledFont("Roboto-Regular.ttf", Typeface.NORMAL)
    private val fontMedium: Typeface = loadBundledFont("Roboto-Medium.ttf", Typeface.NORMAL)
    private val fontBold: Typeface = loadBundledFont("Roboto-Bold.ttf", Typeface.BOLD)
    private val fontBlack: Typeface = loadBundledFont("Roboto-Black.ttf", Typeface.BOLD)

    private val logoBitmap: Bitmap? = loadFlutterAssetBitmap("assets/icons/inutil_icon.png")
    private val roundedArtworkSmall: Bitmap? = artworkBitmap?.let { createRoundedCover(it, 108, 20f) }
    private val roundedArtworkPlayer: Bitmap? = artworkBitmap?.let { createRoundedCover(it, 136, 24f) }
    private val roundedArtworkCenter: Bitmap? = artworkBitmap?.let { createRoundedCover(it, 520, 44f) }

    // Pre-measured lyric blocks for smooth 60fps scrolling without per-frame layout churn.
    private data class MeasuredLyric(
        val index: Int,
        val line: MomentLyricLine,
        val layout: StaticLayout,
        val topY: Float,
        val height: Float,
        val centerY: Float,
    )

    private val lyricsAreaLeft = 68f
    private val lyricsAreaWidth = (designW - 136f).toInt()
    private val lyricsLineSpacing = 44f
    private val lyricsActiveTextSize = 62f

    private val lyricPaint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        typeface = fontBold
        textSize = lyricsActiveTextSize
        color = Color.WHITE
    }

    private val measuredLyrics: List<MeasuredLyric> = buildMeasuredLyrics()

    // Smooth camera scroll state for 60fps spring-like gliding between lyric lines.
    private var currentScrollY: Float = Float.NaN
    private var lastFrameMs: Long = -1L

    // Smooth cross-fade state for single active lyric line in Player mode.
    private var lastPlayerLyricIndex: Int = -1
    private var previousPlayerLyricText: String = ""
    private var playerLyricChangeClipMs: Long = -10_000L

    // Reusable Paints.
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
    private val subtitlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
    private val timePaint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
    private val watermarkTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        typeface = fontMedium
        textSize = 27f
        letterSpacing = 0.03f
        color = Color.argb(138, 255, 255, 255)
        setShadowLayer(12f, 0f, 3f, Color.argb(145, 0, 0, 0))
    }
    private val fadeMaskPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
    }

    // Pre-computed halo color matching `_lyricsHaloFor` in lyrics_page.dart.
    private val haloColor: Int = computeHaloColor(request.accentColorArgb)

    // Pre-computed vertical fade mask gradients for lyrics viewport.
    private val lyricsViewportTop = 276f
    private val lyricsViewportBottom = 1720f
    private val lyricsFocusY = 760f
    private val lyricsFadeMaskShader = LinearGradient(
        0f,
        lyricsViewportTop,
        0f,
        lyricsViewportBottom,
        intArrayOf(
            Color.TRANSPARENT,
            Color.WHITE,
            Color.WHITE,
            Color.TRANSPARENT,
        ),
        floatArrayOf(0f, 0.11f, 0.86f, 1f),
        Shader.TileMode.CLAMP,
    )

    private val playerBottomScrimShader = LinearGradient(
        0f,
        920f,
        0f,
        designH,
        intArrayOf(
            Color.TRANSPARENT,
            Color.argb(95, 6, 8, 12),
            Color.argb(195, 6, 8, 12),
            Color.argb(235, 6, 8, 12),
        ),
        floatArrayOf(0f, 0.34f, 0.72f, 1f),
        Shader.TileMode.CLAMP,
    )

    private val playerTopScrimShader = LinearGradient(
        0f,
        0f,
        0f,
        320f,
        intArrayOf(
            Color.argb(155, 6, 8, 12),
            Color.argb(60, 6, 8, 12),
            Color.TRANSPARENT,
        ),
        floatArrayOf(0f, 0.55f, 1f),
        Shader.TileMode.CLAMP,
    )

    private val lyricsTopScrimShader = LinearGradient(
        0f,
        0f,
        0f,
        360f,
        intArrayOf(
            Color.argb(170, 6, 8, 12),
            Color.argb(95, 6, 8, 12),
            Color.TRANSPARENT,
        ),
        floatArrayOf(0f, 0.65f, 1f),
        Shader.TileMode.CLAMP,
    )

    private val lyricsBottomScrimShader = LinearGradient(
        0f,
        1560f,
        0f,
        designH,
        intArrayOf(
            Color.TRANSPARENT,
            Color.argb(155, 6, 8, 12),
        ),
        floatArrayOf(0f, 1f),
        Shader.TileMode.CLAMP,
    )

    fun drawFrame(targetBitmap: Bitmap, clipTimeMs: Long) {
        val canvas = Canvas(targetBitmap)
        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        canvas.save()
        canvas.scale(scale, scale)

        val songTimeMs = request.startMs + clipTimeMs
        when (request.mode) {
            MomentMode.LYRICS -> drawLyricsMode(canvas, clipTimeMs, songTimeMs)
            MomentMode.PLAYER -> drawPlayerMode(canvas, clipTimeMs, songTimeMs)
        }
        drawTranslucentWatermark(canvas)

        canvas.restore()
    }

    /**
     * Generates a rich, blurred 9:16 artwork backdrop bitmap for songs that do
     * not have a Spotify Canvas or music-video preview clip.
     */
    fun createFallbackBackgroundBitmap(artwork: Bitmap?): Bitmap {
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.rgb(10, 12, 16))
        if (artwork != null && !artwork.isRecycled) {
            // Downscale + box blur for silky iOS-style mesh/blurred artwork look.
            val smallW = 72
            val smallH = 128
            val small = Bitmap.createBitmap(smallW, smallH, Bitmap.Config.ARGB_8888)
            val sCanvas = Canvas(small)
            val srcRect = centerCropRect(artwork.width, artwork.height, smallW, smallH)
            sCanvas.drawBitmap(artwork, srcRect, Rect(0, 0, smallW, smallH), bitmapPaint)
            fastBoxBlur(small, radius = 9)
            fastBoxBlur(small, radius = 6)

            val blurPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            canvas.drawBitmap(small, null, Rect(0, 0, width, height), blurPaint)
            small.recycle()

            // Subtle ambient color wash.
            val accent = request.accentColorArgb
            val r = Color.red(accent)
            val g = Color.green(accent)
            val b = Color.blue(accent)
            val aura = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    width * 0.5f,
                    height * 0.38f,
                    height * 0.62f,
                    intArrayOf(
                        Color.argb(90, r, g, b),
                        Color.argb(35, r, g, b),
                        Color.argb(145, 6, 8, 12),
                    ),
                    floatArrayOf(0f, 0.5f, 1f),
                    Shader.TileMode.CLAMP,
                )
            }
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), aura)
        } else {
            // Accent gradient when even artwork is absent.
            val accent = request.accentColorArgb
            val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    0f,
                    0f,
                    width.toFloat(),
                    height.toFloat(),
                    intArrayOf(
                        Color.rgb(
                            (Color.red(accent) * 0.42f).toInt(),
                            (Color.green(accent) * 0.42f).toInt(),
                            (Color.blue(accent) * 0.42f).toInt(),
                        ),
                        Color.rgb(12, 14, 22),
                    ),
                    null,
                    Shader.TileMode.CLAMP,
                )
            }
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bg)
        }
        return out
    }

    fun release() {
        logoBitmap?.recycle()
        roundedArtworkSmall?.recycle()
        roundedArtworkPlayer?.recycle()
        roundedArtworkCenter?.recycle()
    }

    // -------------------------------------------------------------------------
    // Mode 1: Letras (mirrors lyrics_page.dart cleanly without chrome clutter)
    // -------------------------------------------------------------------------
    private fun drawLyricsMode(canvas: Canvas, clipTimeMs: Long, songTimeMs: Long) {
        // Top & bottom atmospheric scrims for effortless contrast.
        fillPaint.shader = lyricsTopScrimShader
        canvas.drawRect(0f, 0f, designW, 360f, fillPaint)
        fillPaint.shader = lyricsBottomScrimShader
        canvas.drawRect(0f, 1560f, designW, designH, fillPaint)
        fillPaint.shader = null

        // Top song header: rounded artwork + "Letras" / Title + Artist.
        val headerY = 104f
        val leftX = 64f
        roundedArtworkSmall?.let { cover ->
            fillPaint.color = Color.argb(90, 0, 0, 0)
            fillPaint.setShadowLayer(22f, 0f, 8f, Color.argb(120, 0, 0, 0))
            canvas.drawRoundRect(
                RectF(leftX, headerY, leftX + 108f, headerY + 108f),
                20f,
                20f,
                fillPaint,
            )
            fillPaint.clearShadowLayer()
            canvas.drawBitmap(cover, leftX, headerY, bitmapPaint)
        }

        val textLeft = if (roundedArtworkSmall != null) leftX + 134f else leftX
        val maxTextW = designW - textLeft - 64f

        titlePaint.apply {
            typeface = fontBold
            textSize = 40f
            color = Color.WHITE
            setShadowLayer(10f, 0f, 2f, Color.argb(110, 0, 0, 0))
        }
        val titleEllipsized = TextUtils.ellipsize(
            request.title,
            titlePaint,
            maxTextW,
            TextUtils.TruncateAt.END,
        ).toString()
        canvas.drawText(titleEllipsized, textLeft, headerY + 46f, titlePaint)

        subtitlePaint.apply {
            typeface = fontMedium
            textSize = 30f
            color = Color.argb(204, 255, 255, 255)
            setShadowLayer(8f, 0f, 2f, Color.argb(110, 0, 0, 0))
        }
        val artistEllipsized = TextUtils.ellipsize(
            request.artist,
            subtitlePaint,
            maxTextW,
            TextUtils.TruncateAt.END,
        ).toString()
        canvas.drawText(artistEllipsized, textLeft, headerY + 90f, subtitlePaint)

        // Thin animated song progress strip right under header (matches Screenshot 1).
        val barY = headerY + 134f
        val progress = if (request.trackDurationMs > 0L) {
            (songTimeMs.toFloat() / request.trackDurationMs.toFloat()).coerceIn(0f, 1f)
        } else {
            (clipTimeMs.toFloat() / request.clipDurationMs.toFloat()).coerceIn(0f, 1f)
        }
        fillPaint.color = Color.argb(64, 255, 255, 255)
        canvas.drawRoundRect(RectF(0f, barY, designW, barY + 6f), 3f, 3f, fillPaint)
        fillPaint.color = Color.argb(235, 255, 255, 255)
        canvas.drawRoundRect(
            RectF(0f, barY, designW * progress, barY + 6f),
            3f,
            3f,
            fillPaint,
        )

        if (measuredLyrics.isEmpty()) {
            drawEditorialFallbackCenter(canvas, clipTimeMs, songTimeMs)
            return
        }

        // Compute active lyric index with user's lyricsOffsetMs.
        val lyricClockMs = songTimeMs + request.lyricsOffsetMs
        val activeIdx = findActiveLyricIndex(lyricClockMs)

        // Target scroll positions active line at lyricsFocusY.
        val targetScrollY = if (activeIdx in measuredLyrics.indices) {
            measuredLyrics[activeIdx].centerY - lyricsFocusY
        } else {
            measuredLyrics.first().centerY - lyricsFocusY
        }

        val dtSec = if (lastFrameMs < 0L) {
            1f / 60f
        } else {
            ((clipTimeMs - lastFrameMs).coerceIn(1L, 100L) / 1000f)
        }
        lastFrameMs = clipTimeMs
        currentScrollY = if (currentScrollY.isNaN()) {
            targetScrollY
        } else {
            // Critically-damped smooth glide (Apple Music / Better Lyrics feel).
            val smoothing = 1f - 2.7182818f.pow(-9.5f * dtSec)
            currentScrollY + (targetScrollY - currentScrollY) * smoothing
        }

        // Draw scrolling lyrics inside a masked layer for smooth top/bottom feathering.
        val layerId = canvas.saveLayer(
            0f,
            lyricsViewportTop,
            designW,
            lyricsViewportBottom,
            null,
        )
        for (item in measuredLyrics) {
            val drawTop = item.topY - currentScrollY
            val drawBottom = drawTop + item.height
            if (drawBottom < lyricsViewportTop - 80f || drawTop > lyricsViewportBottom + 80f) {
                continue
            }

            val isActive = item.index == activeIdx
            val isPast = activeIdx >= 0 && item.index < activeIdx
            val distanceFromFocus = abs((drawTop + item.height * 0.5f) - lyricsFocusY)
            val focusFactor = (1f - (distanceFromFocus / 540f)).coerceIn(0f, 1f)

            canvas.save()
            val pivotX = if (request.lyricsCentered) designW * 0.5f else lyricsAreaLeft
            val pivotY = drawTop + item.height * 0.5f
            val lineScale = if (isActive) 1.03f else (0.94f + 0.03f * focusFactor)
            canvas.scale(lineScale, lineScale, pivotX, pivotY)
            canvas.translate(lyricsAreaLeft, drawTop)

            if (isActive && item.line.words.isNotEmpty()) {
                drawWordTimedActiveLine(canvas, item, lyricClockMs)
            } else {
                drawStandardLyricLine(
                    canvas = canvas,
                    item = item,
                    isActive = isActive,
                    isPast = isPast,
                    focusFactor = focusFactor,
                )
            }
            canvas.restore()
        }

        // Apply vertical feather mask (smooth top & bottom dissolve).
        fadeMaskPaint.shader = lyricsFadeMaskShader
        canvas.drawRect(0f, lyricsViewportTop, designW, lyricsViewportBottom, fadeMaskPaint)
        canvas.restoreToCount(layerId)
    }

    private fun drawStandardLyricLine(
        canvas: Canvas,
        item: MeasuredLyric,
        isActive: Boolean,
        isPast: Boolean,
        focusFactor: Float,
    ) {
        val paint = item.layout.paint
        if (isActive) {
            paint.color = Color.WHITE
            paint.setShadowLayer(
                28f,
                0f,
                0f,
                Color.argb(145, Color.red(haloColor), Color.green(haloColor), Color.blue(haloColor)),
            )
        } else {
            val alpha = if (isPast) {
                (62 + 34 * focusFactor).toInt()
            } else {
                (82 + 48 * focusFactor).toInt()
            }.coerceIn(48, 140)
            paint.color = Color.argb(alpha, 255, 255, 255)
            paint.setShadowLayer(8f, 0f, 2f, Color.argb(65, 0, 0, 0))
        }
        item.layout.draw(canvas)
        paint.clearShadowLayer()
    }

    /**
     * Renders word-by-word karaoke reveal matching Better Lyrics timing:
     * base line in soft translucent white, overlaid with bright glowing
     * filled characters swept horizontally across each active word.
     */
    private fun drawWordTimedActiveLine(
        canvas: Canvas,
        item: MeasuredLyric,
        lyricClockMs: Long,
    ) {
        val layout = item.layout
        val paint = layout.paint

        // 1. Base dimmed text for upcoming syllables.
        paint.color = Color.argb(118, 255, 255, 255)
        paint.setShadowLayer(8f, 0f, 2f, Color.argb(75, 0, 0, 0))
        layout.draw(canvas)

        // 2. Highlighted sung / sweeping words clipped cleanly per line row.
        paint.color = Color.WHITE
        paint.setShadowLayer(
            26f,
            0f,
            0f,
            Color.argb(165, Color.red(haloColor), Color.green(haloColor), Color.blue(haloColor)),
        )

        val lineCount = layout.lineCount
        for (row in 0 until lineCount) {
            val rowStart = layout.getLineStart(row)
            val rowEnd = layout.getLineEnd(row)
            val rowTop = layout.getLineTop(row).toFloat() - 16f
            val rowBottom = layout.getLineBottom(row).toFloat() + 16f
            val rowLeft = layout.getLineLeft(row)

            var clipRight = rowLeft
            var hasLitContent = false

            for (word in item.line.words) {
                if (word.endOffset <= rowStart || word.startOffset >= rowEnd) continue
                val clippedStart = max(word.startOffset, rowStart)
                val clippedEnd = min(word.endOffset, rowEnd)
                if (clippedEnd <= clippedStart) continue

                val x0 = layout.getPrimaryHorizontal(clippedStart)
                val x1 = if (clippedEnd == rowEnd) {
                    layout.getLineRight(row)
                } else {
                    layout.getPrimaryHorizontal(clippedEnd)
                }
                val leftX = min(x0, x1)
                val rightX = max(x0, x1)

                if (lyricClockMs >= word.endMs) {
                    clipRight = max(clipRight, rightX)
                    hasLitContent = true
                } else if (lyricClockMs > word.startMs) {
                    val frac = ((lyricClockMs - word.startMs).toFloat() /
                        (word.endMs - word.startMs).coerceAtLeast(1L).toFloat())
                        .coerceIn(0f, 1f)
                    val eased = frac * frac * (3f - 2f * frac)
                    clipRight = max(clipRight, leftX + (rightX - leftX) * eased)
                    hasLitContent = true
                }
            }

            if (hasLitContent && clipRight > rowLeft + 1f) {
                canvas.save()
                canvas.clipRect(rowLeft - 12f, rowTop, clipRight + 4f, rowBottom)
                layout.draw(canvas)
                canvas.restore()
            }
        }
        paint.clearShadowLayer()
    }

    // -------------------------------------------------------------------------
    // Mode 2: Reproductor (mirrors spotify_fullscreen_canvas_player.dart cleanly)
    // -------------------------------------------------------------------------
    private fun drawPlayerMode(canvas: Canvas, clipTimeMs: Long, songTimeMs: Long) {
        // Cinematic top & bottom scrims (matches Screenshot 2 without UI chrome).
        fillPaint.shader = playerTopScrimShader
        canvas.drawRect(0f, 0f, designW, 320f, fillPaint)
        fillPaint.shader = playerBottomScrimShader
        canvas.drawRect(0f, 920f, designW, designH, fillPaint)
        fillPaint.shader = null

        // Subtle centered top context label (artist / album — zero nav buttons).
        subtitlePaint.apply {
            typeface = fontMedium
            textSize = 26f
            textAlign = Paint.Align.CENTER
            color = Color.argb(185, 255, 255, 255)
            setShadowLayer(8f, 0f, 2f, Color.argb(120, 0, 0, 0))
        }
        canvas.drawText(
            request.album?.takeIf { it.isNotBlank() } ?: "REPRODUCIENDO",
            designW * 0.5f,
            124f,
            subtitlePaint,
        )
        titlePaint.apply {
            typeface = fontBold
            textSize = 32f
            textAlign = Paint.Align.CENTER
            color = Color.WHITE
            setShadowLayer(10f, 0f, 2f, Color.argb(120, 0, 0, 0))
        }
        val topArtist = TextUtils.ellipsize(
            request.artist,
            titlePaint,
            designW - 220f,
            TextUtils.TruncateAt.END,
        ).toString()
        canvas.drawText(topArtist, designW * 0.5f, 168f, titlePaint)
        titlePaint.textAlign = Paint.Align.LEFT
        subtitlePaint.textAlign = Paint.Align.LEFT

        // Lower-third layout matching Screenshot 2.
        val sidePad = 68f
        val contentW = designW - sidePad * 2f

        // 1. Live active synced lyric floating right above the track card!
        val lyricClockMs = songTimeMs + request.lyricsOffsetMs
        val activeIdx = findActiveLyricIndex(lyricClockMs)
        if (activeIdx != lastPlayerLyricIndex) {
            if (lastPlayerLyricIndex in measuredLyrics.indices) {
                previousPlayerLyricText = measuredLyrics[lastPlayerLyricIndex].line.text
            }
            lastPlayerLyricIndex = activeIdx
            playerLyricChangeClipMs = clipTimeMs
        }
        val currentLyricText = if (activeIdx in measuredLyrics.indices) {
            measuredLyrics[activeIdx].line.text
        } else {
            ""
        }
        if (currentLyricText.isNotEmpty()) {
            val animT = ((clipTimeMs - playerLyricChangeClipMs).coerceAtLeast(0L) / 280f)
                .coerceIn(0f, 1f)
            val eased = 1f - (1f - animT).pow(3f)
            val yOffset = (1f - eased) * 20f

            val lyricFloatPaint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
                typeface = fontBold
                textSize = 46f
                color = Color.argb((255 * eased).toInt().coerceIn(0, 255), 255, 255, 255)
                setShadowLayer(16f, 0f, 3f, Color.argb(175, 0, 0, 0))
            }
            val floatLayout = buildStaticLayout(
                text = currentLyricText,
                paint = lyricFloatPaint,
                width = contentW.toInt(),
                centered = false,
                maxLines = 2,
            )
            val floatY = 1350f - floatLayout.height + yOffset
            canvas.save()
            canvas.translate(sidePad, floatY)
            floatLayout.draw(canvas)
            canvas.restore()
        }

        // 2. Track row: rounded mini cover + bold title + artist (matches Screenshot 2).
        val cardTop = 1404f
        val coverSize = 136f
        roundedArtworkPlayer?.let { cover ->
            fillPaint.color = Color.argb(105, 0, 0, 0)
            fillPaint.setShadowLayer(26f, 0f, 10f, Color.argb(145, 0, 0, 0))
            canvas.drawRoundRect(
                RectF(sidePad, cardTop, sidePad + coverSize, cardTop + coverSize),
                24f,
                24f,
                fillPaint,
            )
            fillPaint.clearShadowLayer()
            canvas.drawBitmap(cover, sidePad, cardTop, bitmapPaint)
        }

        val infoLeft = if (roundedArtworkPlayer != null) sidePad + coverSize + 30f else sidePad
        val infoMaxW = designW - infoLeft - sidePad

        titlePaint.apply {
            typeface = fontBlack
            textSize = 48f
            color = Color.WHITE
            setShadowLayer(12f, 0f, 3f, Color.argb(140, 0, 0, 0))
        }
        val songTitle = TextUtils.ellipsize(
            request.title,
            titlePaint,
            infoMaxW,
            TextUtils.TruncateAt.END,
        ).toString()
        canvas.drawText(songTitle, infoLeft, cardTop + 64f, titlePaint)

        subtitlePaint.apply {
            typeface = fontMedium
            textSize = 35f
            color = Color.argb(208, 255, 255, 255)
            setShadowLayer(10f, 0f, 2f, Color.argb(120, 0, 0, 0))
        }
        val songArtist = TextUtils.ellipsize(
            request.artist,
            subtitlePaint,
            infoMaxW,
            TextUtils.TruncateAt.END,
        ).toString()
        canvas.drawText(songArtist, infoLeft, cardTop + 114f, subtitlePaint)

        // 3. Crisp animated progress bar + live elapsed / total timestamps.
        val barTop = cardTop + coverSize + 52f
        val barHeight = 9f
        val trackProgress = if (request.trackDurationMs > 0L) {
            (songTimeMs.toFloat() / request.trackDurationMs.toFloat()).coerceIn(0f, 1f)
        } else {
            (clipTimeMs.toFloat() / request.clipDurationMs.toFloat()).coerceIn(0f, 1f)
        }

        fillPaint.color = Color.argb(72, 255, 255, 255)
        canvas.drawRoundRect(
            RectF(sidePad, barTop, sidePad + contentW, barTop + barHeight),
            barHeight * 0.5f,
            barHeight * 0.5f,
            fillPaint,
        )

        val fillRight = sidePad + contentW * trackProgress
        fillPaint.color = Color.WHITE
        canvas.drawRoundRect(
            RectF(sidePad, barTop, max(sidePad + barHeight, fillRight), barTop + barHeight),
            barHeight * 0.5f,
            barHeight * 0.5f,
            fillPaint,
        )

        // Subtle glowing thumb dot.
        fillPaint.setShadowLayer(14f, 0f, 0f, Color.argb(180, 255, 255, 255))
        canvas.drawCircle(fillRight, barTop + barHeight * 0.5f, 13f, fillPaint)
        fillPaint.clearShadowLayer()

        timePaint.apply {
            typeface = fontMedium
            textSize = 27f
            color = Color.argb(190, 255, 255, 255)
            setShadowLayer(8f, 0f, 2f, Color.argb(110, 0, 0, 0))
            textAlign = Paint.Align.LEFT
        }
        canvas.drawText(formatDuration(songTimeMs), sidePad, barTop + 48f, timePaint)

        timePaint.textAlign = Paint.Align.RIGHT
        canvas.drawText(
            formatDuration(request.trackDurationMs),
            sidePad + contentW,
            barTop + 48f,
            timePaint,
        )
        timePaint.textAlign = Paint.Align.LEFT
    }

    /**
     * Elegant centered fallback when Lyrics mode is chosen on an instrumental
     * track or a song without synchronized lyrics.
     */
    private fun drawEditorialFallbackCenter(canvas: Canvas, clipTimeMs: Long, songTimeMs: Long) {
        val coverLeft = (designW - 520f) * 0.5f
        val coverTop = 580f
        roundedArtworkCenter?.let { cover ->
            fillPaint.color = Color.argb(110, 0, 0, 0)
            fillPaint.setShadowLayer(44f, 0f, 20f, Color.argb(165, 0, 0, 0))
            canvas.drawRoundRect(
                RectF(coverLeft, coverTop, coverLeft + 520f, coverTop + 520f),
                44f,
                44f,
                fillPaint,
            )
            fillPaint.clearShadowLayer()
            canvas.drawBitmap(cover, coverLeft, coverTop, bitmapPaint)
        }

        // Subtle animated minimalist equalizer bars below the cover.
        val barCount = 9
        val barW = 10f
        val barGap = 16f
        val totalW = barCount * barW + (barCount - 1) * barGap
        val startX = (designW - totalW) * 0.5f
        val baseY = 1230f
        val phaseSec = clipTimeMs / 1000f
        fillPaint.color = Color.argb(210, 255, 255, 255)
        for (i in 0 until barCount) {
            val wave = 0.5f + 0.5f * sin(phaseSec * (4.2f + i * 0.55f) + i * 1.1f)
            val h = 18f + 56f * wave
            val x = startX + i * (barW + barGap)
            canvas.drawRoundRect(
                RectF(x, baseY - h * 0.5f, x + barW, baseY + h * 0.5f),
                barW * 0.5f,
                barW * 0.5f,
                fillPaint,
            )
        }

        timePaint.apply {
            typeface = fontMedium
            textSize = 28f
            textAlign = Paint.Align.CENTER
            color = Color.argb(180, 255, 255, 255)
        }
        canvas.drawText(
            "${formatDuration(songTimeMs)} / ${formatDuration(request.trackDurationMs)}",
            designW * 0.5f,
            1320f,
            timePaint,
        )
        timePaint.textAlign = Paint.Align.LEFT
    }

    /**
     * Subtle, refined translucent Inútil Music watermark anchored cleanly at the
     * bottom-center safe zone so it looks premium and stays clear of TikTok /
     * Reels / WhatsApp edge overlays.
     */
    private fun drawTranslucentWatermark(canvas: Canvas) {
        val label = "Inútil Music"
        val iconSize = 38f
        val gap = 14f
        val textW = watermarkTextPaint.measureText(label)
        val totalW = (if (logoBitmap != null) iconSize + gap else 0f) + textW
        val startX = (designW - totalW) * 0.5f
        val centerY = 1824f

        // Ultra-subtle frosted glass pill behind the watermark (barely visible, keeps legibility on bright frames).
        val pillPadX = 24f
        val pillPadY = 13f
        val pillRect = RectF(
            startX - pillPadX,
            centerY - iconSize * 0.5f - pillPadY,
            startX + totalW + pillPadX,
            centerY + iconSize * 0.5f + pillPadY,
        )
        fillPaint.color = Color.argb(38, 12, 14, 20)
        canvas.drawRoundRect(pillRect, 999f, 999f, fillPaint)
        fillPaint.style = Paint.Style.STROKE
        fillPaint.strokeWidth = 1.4f
        fillPaint.color = Color.argb(40, 255, 255, 255)
        canvas.drawRoundRect(pillRect, 999f, 999f, fillPaint)
        fillPaint.style = Paint.Style.FILL

        var cursorX = startX
        logoBitmap?.let { logo ->
            val dst = RectF(
                cursorX,
                centerY - iconSize * 0.5f,
                cursorX + iconSize,
                centerY + iconSize * 0.5f,
            )
            canvas.save()
            val clipPath = Path().apply {
                addRoundRect(dst, 10f, 10f, Path.Direction.CW)
            }
            canvas.clipPath(clipPath)
            val logoPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                alpha = 158 // ~62% subtle translucent brand icon
            }
            canvas.drawBitmap(logo, null, dst, logoPaint)
            canvas.restore()
            cursorX += iconSize + gap
        }

        val fm = watermarkTextPaint.fontMetrics
        val baselineY = centerY - (fm.ascent + fm.descent) * 0.5f
        canvas.drawText(label, cursorX, baselineY, watermarkTextPaint)
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    private fun buildMeasuredLyrics(): List<MeasuredLyric> {
        if (request.lyrics.isEmpty()) return emptyList()
        val list = mutableListOf<MeasuredLyric>()
        var cursorY = 0f
        request.lyrics.forEachIndexed { index, line ->
            val layout = buildStaticLayout(
                text = line.text,
                paint = TextPaint(lyricPaint),
                width = lyricsAreaWidth,
                centered = request.lyricsCentered,
                maxLines = 4,
            )
            val h = layout.height.toFloat()
            list.add(
                MeasuredLyric(
                    index = index,
                    line = line,
                    layout = layout,
                    topY = cursorY,
                    height = h,
                    centerY = cursorY + h * 0.5f,
                ),
            )
            cursorY += h + lyricsLineSpacing
        }
        return list
    }

    private fun findActiveLyricIndex(songTimeMs: Long): Int {
        if (measuredLyrics.isEmpty()) return -1
        var active = -1
        for (i in measuredLyrics.indices) {
            if (measuredLyrics[i].line.timestampMs <= songTimeMs) {
                active = i
            } else {
                break
            }
        }
        return active
    }

    private fun buildStaticLayout(
        text: String,
        paint: TextPaint,
        width: Int,
        centered: Boolean,
        maxLines: Int,
    ): StaticLayout {
        val alignment = if (centered) {
            Layout.Alignment.ALIGN_CENTER
        } else {
            Layout.Alignment.ALIGN_NORMAL
        }
        return StaticLayout.Builder.obtain(text, 0, text.length, paint, width.coerceAtLeast(64))
            .setAlignment(alignment)
            .setLineSpacing(4f, 1.08f)
            .setIncludePad(false)
            .setMaxLines(maxLines)
            .setEllipsize(TextUtils.TruncateAt.END)
            .build()
    }

    private fun loadBundledFont(fileName: String, fallbackStyle: Int): Typeface {
        return try {
            Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/$fileName")
        } catch (_: Throwable) {
            Typeface.create(Typeface.SANS_SERIF, fallbackStyle)
        }
    }

    private fun loadFlutterAssetBitmap(assetPath: String): Bitmap? {
        return try {
            context.assets.open("flutter_assets/$assetPath").use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun createRoundedCover(source: Bitmap, sizePx: Int, radius: Float): Bitmap {
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val path = Path().apply {
            addRoundRect(RectF(0f, 0f, sizePx.toFloat(), sizePx.toFloat()), radius, radius, Path.Direction.CW)
        }
        c.clipPath(path)
        val srcRect = centerCropRect(source.width, source.height, sizePx, sizePx)
        c.drawBitmap(source, srcRect, Rect(0, 0, sizePx, sizePx), bitmapPaint)
        return out
    }

    private fun centerCropRect(srcW: Int, srcH: Int, dstW: Int, dstH: Int): Rect {
        val srcAspect = srcW.toFloat() / srcH.coerceAtLeast(1).toFloat()
        val dstAspect = dstW.toFloat() / dstH.coerceAtLeast(1).toFloat()
        return if (srcAspect > dstAspect) {
            val cropW = (srcH * dstAspect).toInt().coerceIn(1, srcW)
            val left = (srcW - cropW) / 2
            Rect(left, 0, left + cropW, srcH)
        } else {
            val cropH = (srcW / dstAspect).toInt().coerceIn(1, srcH)
            val top = (srcH - cropH) / 2
            Rect(0, top, srcW, top + cropH)
        }
    }

    private fun computeHaloColor(accent: Int): Int {
        val r = Color.red(accent) / 255f
        val g = Color.green(accent) / 255f
        val b = Color.blue(accent) / 255f
        val luminance = 0.2126f * r + 0.7152f * g + 0.0722f * b
        if (luminance >= 0.40f) return accent
        // Blend 28% white into dark accents so the glow remains legible.
        val nr = (Color.red(accent) * 0.72f + 255f * 0.28f).toInt().coerceIn(0, 255)
        val ng = (Color.green(accent) * 0.72f + 255f * 0.28f).toInt().coerceIn(0, 255)
        val nb = (Color.blue(accent) * 0.72f + 255f * 0.28f).toInt().coerceIn(0, 255)
        return Color.rgb(nr, ng, nb)
    }

    private fun formatDuration(ms: Long): String {
        val totalSeconds = (ms / 1000L).coerceAtLeast(0L)
        val minutes = totalSeconds / 60L
        val seconds = totalSeconds % 60L
        return "$minutes:${seconds.toString().padStart(2, '0')}"
    }

    /**
     * Fast separable box blur on a tiny bitmap (72x128) — takes <1ms on CPU and
     * avoids deprecated RenderScript while producing creamy iOS-style backdrop blur.
     */
    private fun fastBoxBlur(bitmap: Bitmap, radius: Int) {
        val w = bitmap.width
        val h = bitmap.height
        val pix = IntArray(w * h)
        bitmap.getPixels(pix, 0, w, 0, 0, w, h)
        val tmp = IntArray(w * h)
        val div = radius * 2 + 1

        // Horizontal pass.
        for (y in 0 until h) {
            var rSum = 0
            var gSum = 0
            var bSum = 0
            val row = y * w
            for (i in -radius..radius) {
                val p = pix[row + i.coerceIn(0, w - 1)]
                rSum += (p shr 16) and 0xFF
                gSum += (p shr 8) and 0xFF
                bSum += p and 0xFF
            }
            for (x in 0 until w) {
                tmp[row + x] = Color.rgb(rSum / div, gSum / div, bSum / div)
                val addIdx = (x + radius + 1).coerceAtMost(w - 1)
                val subIdx = (x - radius).coerceAtLeast(0)
                val pAdd = pix[row + addIdx]
                val pSub = pix[row + subIdx]
                rSum += ((pAdd shr 16) and 0xFF) - ((pSub shr 16) and 0xFF)
                gSum += ((pAdd shr 8) and 0xFF) - ((pSub shr 8) and 0xFF)
                bSum += (pAdd and 0xFF) - (pSub and 0xFF)
            }
        }

        // Vertical pass.
        for (x in 0 until w) {
            var rSum = 0
            var gSum = 0
            var bSum = 0
            for (i in -radius..radius) {
                val p = tmp[i.coerceIn(0, h - 1) * w + x]
                rSum += (p shr 16) and 0xFF
                gSum += (p shr 8) and 0xFF
                bSum += p and 0xFF
            }
            for (y in 0 until h) {
                pix[y * w + x] = Color.rgb(rSum / div, gSum / div, bSum / div)
                val addY = (y + radius + 1).coerceAtMost(h - 1)
                val subY = (y - radius).coerceAtLeast(0)
                val pAdd = tmp[addY * w + x]
                val pSub = tmp[subY * w + x]
                rSum += ((pAdd shr 16) and 0xFF) - ((pSub shr 16) and 0xFF)
                gSum += ((pAdd shr 8) and 0xFF) - ((pSub shr 8) and 0xFF)
                bSum += (pAdd and 0xFF) - (pSub and 0xFF)
            }
        }
        bitmap.setPixels(pix, 0, w, 0, 0, w, h)
    }

    companion object {
        fun computeKenBurnsTransform(clipTimeMs: Long): FloatArray {
            val t = clipTimeMs / 1000f
            val zoom = 1.06f + 0.055f * (0.5f + 0.5f * sin(t * (2f * PI.toFloat() / 16f)))
            val panX = 0.024f * sin(t * (2f * PI.toFloat() / 20f))
            val panY = 0.018f * cos(t * (2f * PI.toFloat() / 24f))
            return floatArrayOf(zoom, panX, panY)
        }
    }
}
