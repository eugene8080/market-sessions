package com.marketsessions.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.graphics.Typeface
import java.time.Instant

/**
 * How much of the dial survives at a given widget size. Decoration is dropped as the cell shrinks
 * rather than scaled down into illegibility; MINI drops the hour ring altogether and zooms the
 * bands into the space it leaves, so a one cell widget still reads as a ring of open markets.
 */
enum class DialStyle(
    val hourLabelStep: Int,
    val hourTextSize: Float,
    val grid: Boolean,
    val ring: Boolean,
    val bandLabels: Boolean,
    val zoom: Float,
    val minBitmap: Int,
) {
    FULL(hourLabelStep = 1, hourTextSize = 11f, grid = true, ring = true, bandLabels = true, zoom = 1f, minBitmap = 288),
    COMPACT(hourLabelStep = 6, hourTextSize = 15f, grid = false, ring = true, bandLabels = false, zoom = 1f, minBitmap = 224),
    MINI(hourLabelStep = 0, hourTextSize = 0f, grid = false, ring = false, bandLabels = false, zoom = 1.2f, minBitmap = 160),
}

/**
 * Draws the 24 hour dial as a bitmap for the widget's ImageView. It is a port of the SVG in
 * index.html: the same 400 unit design grid, the same geometry constants, the app's dark palette.
 * The minute ring labels and the second hand are dropped, both illegible at widget size.
 */
class DialRenderer(private val size: Int, private val style: DialStyle = DialStyle.FULL) {

    private object Palette {
        const val DIAL_BG = 0xFF151821.toInt()
        const val RING = 0xFF3C4761.toInt()
        const val RING_TEXT = 0xFFEEF1F8.toInt()
        const val OPEN = 0xFF41C391.toInt()
        const val CLOSED = 0xFF8F97B6.toInt()
        const val HAND = 0xFFC3CBDF.toInt()
        const val GRID = 0x17FFFFFF
        const val BAND_TEXT = 0xFF0E1116.toInt()
    }

    private companion object {
        const val CENTER = 200f
        const val BAND_OUTER = 157f
        const val BAND_WIDTH = 7.2f
        const val BAND_STEP = 9f
    }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    private val hourText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textSize = style.hourTextSize
        color = Palette.RING_TEXT
    }

    private val bandText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textSize = 6f
        letterSpacing = 0.09f
        color = Palette.BAND_TEXT
    }

    fun render(states: List<MarketState>, now: Instant): Bitmap {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(size / 400f, size / 400f)
        if (style.zoom != 1f) canvas.scale(style.zoom, style.zoom, CENTER, CENTER)

        face(canvas)
        states.forEachIndexed { index, state -> band(canvas, index, state) }
        hands(canvas, now)

        return bitmap
    }

    private fun face(canvas: Canvas) {
        if (style.ring) {
            fill.color = Palette.DIAL_BG
            canvas.drawCircle(CENTER, CENTER, 188f, fill)

            stroke.color = Palette.RING
            stroke.strokeWidth = 22f
            canvas.drawCircle(CENTER, CENTER, 177f, stroke)
        }

        if (style.grid) {
            stroke.color = Palette.GRID
            stroke.strokeWidth = 0.7f
            for (hour in 0 until 24) {
                val degrees = hour / 24f * 360f
                val inner = polar(22f, degrees)
                val outer = polar(163f, degrees)
                canvas.drawLine(inner.x, inner.y, outer.x, outer.y, stroke)
            }
        }

        if (style.hourLabelStep > 0) {
            val metrics = hourText.fontMetrics
            val baseline = -(metrics.ascent + metrics.descent) / 2f
            for (hour in style.hourLabelStep..24 step style.hourLabelStep) {
                val point = polar(177f, hour / 24f * 360f)
                canvas.drawText(hour.toString().padStart(2, '0'), point.x, point.y + baseline, hourText)
            }
        }
    }

    private fun band(canvas: Canvas, index: Int, state: MarketState) {
        val window = state.window ?: return
        val radius = BAND_OUTER - index * BAND_STEP - BAND_WIDTH / 2f

        val from = degreesOf(window.start)
        var to = degreesOf(window.end)
        if (to <= from) to += 360f

        stroke.color = if (state.isOpen) Palette.OPEN else Palette.CLOSED
        stroke.strokeWidth = BAND_WIDTH
        stroke.strokeCap = Paint.Cap.BUTT
        canvas.drawArc(ovalAt(radius), from - 90f, to - from, false, stroke)

        if (style.bandLabels) label(canvas, state.market.name.uppercase(), radius, from, to)
    }

    /** Curved band label, the Canvas equivalent of the SVG textPath in the web app. */
    private fun label(canvas: Canvas, text: String, radius: Float, from: Float, to: Float) {
        val sweep = to - from
        val arcLength = sweep / 360f * (2f * Math.PI.toFloat() * radius)
        val textWidth = bandText.measureText(text)
        if (arcLength < textWidth + 6f) return

        // Text on the bottom half would read upside down, so run the path the other way.
        val middle = ((from + to) / 2f) % 360f
        val flipped = middle > 90f && middle < 270f

        val path = Path()
        if (flipped) {
            path.addArc(ovalAt(radius), to - 90f, -sweep)
        } else {
            path.addArc(ovalAt(radius), from - 90f, sweep)
        }

        val metrics = bandText.fontMetrics
        canvas.drawTextOnPath(
            text,
            path,
            (arcLength - textWidth) / 2f,
            -(metrics.ascent + metrics.descent) / 2f,
            bandText,
        )
    }

    private fun hands(canvas: Canvas, now: Instant) {
        val minutes = minuteOfDay(now)

        stroke.color = Palette.HAND
        stroke.strokeCap = Paint.Cap.ROUND

        stroke.strokeWidth = 5.5f
        hand(canvas, minutes / 1440f * 360f, 118f)

        stroke.strokeWidth = 4f
        hand(canvas, minutes % 60f / 60f * 360f, 146f)

        fill.color = Palette.HAND
        canvas.drawCircle(CENTER, CENTER, 8f, fill)
    }

    private fun hand(canvas: Canvas, degrees: Float, length: Float) {
        val tip = polar(length, degrees)
        canvas.drawLine(CENTER, CENTER, tip.x, tip.y, stroke)
    }

    private fun ovalAt(radius: Float) =
        RectF(CENTER - radius, CENTER - radius, CENTER + radius, CENTER + radius)

    private fun degreesOf(instant: Instant) = minuteOfDay(instant) / 1440f * 360f

    private fun minuteOfDay(instant: Instant): Float {
        val time = instant.atZone(Config.displayZone())
        return time.hour * 60f + time.minute + time.second / 60f
    }

    /** Zero degrees is noon-up, angles run clockwise, matching the SVG helper of the same name. */
    private fun polar(radius: Float, degrees: Float): PointF {
        val radians = Math.toRadians((degrees - 90f).toDouble())
        return PointF(
            CENTER + radius * Math.cos(radians).toFloat(),
            CENTER + radius * Math.sin(radians).toFloat(),
        )
    }
}
