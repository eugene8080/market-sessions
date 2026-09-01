package com.marketsessions.widget

import android.content.Context

/**
 * The colours the dial is drawn in, and where the choice is kept.
 *
 * Three grounds and four session colours, matching the web app's picker and the Garmin build's
 * settings, so the three faces of Market Sessions can be set to look alike. The session colour is
 * chosen separately from the ground because it is the one colour on the dial that carries meaning
 * rather than mood.
 *
 * Colours come in pairs wherever something fades: the ring from midnight to noon, a band from its
 * own open to its own close. Android has gradient shaders and could do those natively, but the
 * fades are drawn as runs of short arcs to match the watch exactly — Connect IQ has no gradient
 * primitive at all, and three faces that agree are worth more than one that is a shade smoother.
 *
 * The widget has no settings screen of its own. The choice is made in the app — which is the web
 * page in a WebView — and handed here through [SessionsActivity]'s bridge, so there is one picker
 * rather than two that can disagree.
 */
data class DialTheme(
    val ground: Int,
    val ringNight: Int,
    val ringDay: Int,
    val ringText: Int,
    val closedFrom: Int,
    val closedTo: Int,
    val hand: Int,
    /** The hour hand's tip, and nothing else. */
    val accent: Int,
    val openFrom: Int,
    val openTo: Int,
    /** A flat tone for where a fade would be lost: the hub's rim. */
    val open: Int,
) {
    companion object {
        /** Ground palettes, keyed by the same names the web app's picker uses. */
        private val GROUNDS = mapOf(
            "iron" to Ground(0xFF070910, 0xFF2C3854, 0xFF495C82, 0xFFE9EEF8,
                0xFF404A64, 0xFF8B95B1, 0xFFC9D3E4, 0xFFFFB03A),
            "cobalt" to Ground(0xFF050A16, 0xFF123058, 0xFF255E9E, 0xFFE6F0FF,
                0xFF1F3C66, 0xFF5E86BE, 0xFFD6E4F7, 0xFFFFB03A),
            "ember" to Ground(0xFF110503, 0xFF3E1109, 0xFF8C2A12, 0xFFFFEDE4,
                0xFF46302A, 0xFFA48C80, 0xFFF2E2D6, 0xFFFFD98A),
        )

        private val SESSIONS = mapOf(
            "red" to Session(0xFF9E2318, 0xFFFF6B58, 0xFFE8503F),
            "green" to Session(0xFF1B7A56, 0xFF63EDB0, 0xFF41C391),
            "blue" to Session(0xFF184F9B, 0xFF69BCFF, 0xFF3D93E8),
            "purple" to Session(0xFF54269B, 0xFFC095FF, 0xFF9463E6),
        )

        private const val PREFS = "market-sessions"
        private const val GROUND_KEY = "dial.palette"
        private const val SESSION_KEY = "dial.session"

        const val DEFAULT_GROUND = "iron"
        const val DEFAULT_SESSION = "red"

        private fun prefs(context: Context) =
            context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** The theme the widget should draw with. Unknown names fall back rather than throw. */
        fun load(context: Context): DialTheme {
            val p = prefs(context)
            val g = GROUNDS[p.getString(GROUND_KEY, DEFAULT_GROUND)] ?: GROUNDS.getValue(DEFAULT_GROUND)
            val s = SESSIONS[p.getString(SESSION_KEY, DEFAULT_SESSION)] ?: SESSIONS.getValue(DEFAULT_SESSION)
            return DialTheme(
                ground = g.ground.toInt(),
                ringNight = g.ringNight.toInt(),
                ringDay = g.ringDay.toInt(),
                ringText = g.ringText.toInt(),
                closedFrom = g.closedFrom.toInt(),
                closedTo = g.closedTo.toInt(),
                hand = g.hand.toInt(),
                accent = g.accent.toInt(),
                openFrom = s.from.toInt(),
                openTo = s.to.toInt(),
                open = s.flat.toInt(),
            )
        }

        /**
         * Store a choice made in the app. Returns true when it actually changed, so the caller can
         * skip redrawing every widget for a tap that selected what was already selected.
         */
        fun save(context: Context, ground: String, session: String): Boolean {
            if (!GROUNDS.containsKey(ground) || !SESSIONS.containsKey(session)) return false

            val p = prefs(context)
            val unchanged = p.getString(GROUND_KEY, DEFAULT_GROUND) == ground &&
                p.getString(SESSION_KEY, DEFAULT_SESSION) == session
            if (unchanged) return false

            p.edit().putString(GROUND_KEY, ground).putString(SESSION_KEY, session).apply()
            return true
        }

        /**
         * Blend two opaque ARGB colours, channel-wise in sRGB.
         *
         * Interpolating gamma-encoded values is not what a colour scientist would do, but over the
         * short, low-contrast spans on this dial the difference is invisible — and it keeps the
         * arithmetic identical to `Palette.mix` on the watch, which has no room for anything else.
         */
        fun mix(from: Int, to: Int, amount: Float): Int {
            val t = amount.coerceIn(0f, 1f)
            fun channel(shift: Int): Int {
                val a = from shr shift and 0xFF
                val b = to shr shift and 0xFF
                return (a + (b - a) * t).toInt()
            }
            return (0xFF shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
        }
    }

    private data class Ground(
        val ground: Long,
        val ringNight: Long,
        val ringDay: Long,
        val ringText: Long,
        val closedFrom: Long,
        val closedTo: Long,
        val hand: Long,
        val accent: Long,
    )

    private data class Session(val from: Long, val to: Long, val flat: Long)
}
