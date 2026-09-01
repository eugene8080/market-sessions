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
class DialRenderer(
    private val size: Int,
    private val detail: DialStyle = DialStyle.FULL,
    private val theme: DialTheme = DialTheme(
        ground = 0xFF070910.toInt(),
        ringNight = 0xFF2C3854.toInt(),
        ringDay = 0xFF495C82.toInt(),
        ringText = 0xFFE9EEF8.toInt(),
        closedFrom = 0xFF404A64.toInt(),
        closedTo = 0xFF8B95B1.toInt(),
        hand = 0xFFC9D3E4.toInt(),
        accent = 0xFFFFB03A.toInt(),
        openFrom = 0xFF9E2318.toInt(),
        openTo = 0xFFFF6B58.toInt(),
        open = 0xFFE8503F.toInt(),
    ),
) {

    private companion object {
        /** The grid is a wash of white over whatever ground the theme supplies, so it is not themed. */
        const val GRID = 0x17FFFFFF

        /** Market names on the bands: white on every theme, matching the web app. */
        const val BAND_TEXT = 0xFFFFFFFF.toInt()

        const val CENTER = 200f
        const val BAND_OUTER = 157f
        const val BAND_WIDTH = 7.2f
        const val BAND_STEP = 9f

        const val HAND_PIVOT = 20f
        const val HOUR_TIP = 96f
        const val HUB_RADIUS = 18f
        const val MINUTE_TIP = BAND_OUTER - 3 * BAND_STEP - BAND_WIDTH

        /** Segment counts for the two fades, matching the watch. */
        const val RING_STEPS = 30
        const val BAND_STEPS = 8
    }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    private val hourText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textSize = detail.hourTextSize
        color = theme.ringText
    }

    /**
     * Band labels are deliberately taller than the 7.2 band they sit on, matching the web app: at
     * 6f they were legible on a desktop and not on a phone. Spilling into the gap either side costs
     * nothing, because a neighbouring band only collides where the two sessions overlap in the day
     * AND both labels sit at the same angle, which they never do — each is centred on its own
     * session. `label` still drops any name too long for its own arc.
     */
    private val bandText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textSize = 8.5f
        letterSpacing = 0.09f
        color = BAND_TEXT
    }

    fun render(states: List<MarketState>, now: Instant): Bitmap {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(size / 400f, size / 400f)
        if (detail.zoom != 1f) canvas.scale(detail.zoom, detail.zoom, CENTER, CENTER)

        face(canvas)
        states.forEachIndexed { index, state -> band(canvas, index, state) }
        hands(canvas, now)

        return bitmap
    }

    private fun face(canvas: Canvas) {
        if (detail.ring) {
            fill.color = theme.ground
            canvas.drawCircle(CENTER, CENTER, 188f, fill)

            // Cool at midnight, warmer under the middle of the trading day. A hair of overlap on
            // each segment, or the joins show as hairlines.
            stroke.strokeWidth = 22f
            stroke.strokeCap = Paint.Cap.BUTT
            val sweep = 360f / RING_STEPS
            for (step in 0 until RING_STEPS) {
                val from = step * sweep
                val t = (1f - Math.cos(Math.toRadians(from.toDouble())).toFloat()) / 2f
                stroke.color = DialTheme.mix(theme.ringNight, theme.ringDay, t)
                canvas.drawArc(ovalAt(177f), from - 90f - 0.6f, sweep + 1.2f, false, stroke)
            }
        }

        if (detail.grid) {
            stroke.color = GRID
            stroke.strokeWidth = 0.7f
            for (hour in 0 until 24) {
                val degrees = hour / 24f * 360f
                val inner = polar(22f, degrees)
                val outer = polar(163f, degrees)
                canvas.drawLine(inner.x, inner.y, outer.x, outer.y, stroke)
            }
        }

        if (detail.hourLabelStep > 0) {
            val metrics = hourText.fontMetrics
            val baseline = -(metrics.ascent + metrics.descent) / 2f
            for (hour in detail.hourLabelStep..24 step detail.hourLabelStep) {
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

        // Each session travels from its own open to its own close, so a band carries a direction
        // rather than sitting there as a flat stripe.
        val tail = if (state.isOpen) theme.openFrom else theme.closedFrom
        val head = if (state.isOpen) theme.openTo else theme.closedTo

        stroke.strokeWidth = BAND_WIDTH
        stroke.strokeCap = Paint.Cap.BUTT
        val step = (to - from) / BAND_STEPS
        for (segment in 0 until BAND_STEPS) {
            stroke.color = DialTheme.mix(tail, head, segment / (BAND_STEPS - 1f))
            val edge = if (segment == BAND_STEPS - 1) 0f else 0.5f
            canvas.drawArc(ovalAt(radius), from - 90f + segment * step, step + edge, false, stroke)
        }

        if (detail.bandLabels) label(canvas, state.market.name.uppercase(), radius, from, to)
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

    /**
     * Hands, matching the Garmin dial: tapered rather than drawn as lines, a short broad hour hand
     * with a warm tip and a long thin minute hand.
     *
     * Each is drawn three times — a dark shoulder a shade wider than the hand, so it separates from
     * whatever band it is lying over; the body; and, on the hour hand only, the last fifth in the
     * accent. A second flash of colour on the minute hand would be decoration on a hand that is
     * along for the ride.
     */
    private fun hands(canvas: Canvas, now: Instant) {
        val minutes = minuteOfDay(now)

        hand(canvas, minutes % 60f / 60f * 360f, MINUTE_TIP, 4.5f, 1.5f, theme.hand, null)
        hand(canvas, minutes / 1440f * 360f, HOUR_TIP, 7.2f, 2.4f, theme.hand, theme.accent)

        // The hub caps the roots of both hands.
        fill.color = theme.ground
        canvas.drawCircle(CENTER, CENTER, HUB_RADIUS, fill)
        stroke.color = theme.open
        stroke.strokeWidth = 2.4f
        stroke.strokeCap = Paint.Cap.BUTT
        canvas.drawCircle(CENTER, CENTER, HUB_RADIUS, stroke)
    }

    private fun hand(
        canvas: Canvas,
        degrees: Float,
        tip: Float,
        halfBase: Float,
        halfTip: Float,
        body: Int,
        tipColour: Int?,
    ) {
        taper(canvas, degrees, HAND_PIVOT, tip, halfBase + 1.1f, halfTip + 1.1f, theme.ground)
        taper(canvas, degrees, HAND_PIVOT, tip, halfBase, halfTip, body)

        if (tipColour != null) {
            val shoulder = tip - (tip - HAND_PIVOT) * 0.2f
            taper(canvas, degrees, shoulder, tip, halfBase * 0.45f, halfTip, tipColour)
        }
    }

    private fun taper(
        canvas: Canvas,
        degrees: Float,
        from: Float,
        to: Float,
        halfFrom: Float,
        halfTo: Float,
        colour: Int,
    ) {
        val radians = Math.toRadians((degrees - 90f).toDouble())
        val alongX = Math.cos(radians).toFloat()
        val alongY = Math.sin(radians).toFloat()
        val acrossX = -alongY
        val acrossY = alongX

        val baseX = CENTER + alongX * from
        val baseY = CENTER + alongY * from
        val tipX = CENTER + alongX * to
        val tipY = CENTER + alongY * to

        val path = Path().apply {
            moveTo(baseX + acrossX * halfFrom, baseY + acrossY * halfFrom)
            lineTo(tipX + acrossX * halfTo, tipY + acrossY * halfTo)
            lineTo(tipX - acrossX * halfTo, tipY - acrossY * halfTo)
            lineTo(baseX - acrossX * halfFrom, baseY - acrossY * halfFrom)
            close()
        }

        fill.color = colour
        canvas.drawPath(path, fill)
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
