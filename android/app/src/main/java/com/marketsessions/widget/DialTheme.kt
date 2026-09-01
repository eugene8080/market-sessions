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
 * The widget has no settings screen of its own. The choice is made in the app — which is the web
 * page in a WebView — and handed here through [SessionsActivity]'s bridge, so there is one picker
 * rather than two that can disagree.
 */
data class DialTheme(
    val ground: Int,
    val ring: Int,
    val ringText: Int,
    val closed: Int,
    val hand: Int,
    val open: Int,
) {
    companion object {
        /** Ground palettes, keyed by the same names the web app's picker uses. */
        private val GROUNDS = mapOf(
            "iron" to intArrayOf(0xFF070910.toInt(), 0xFF3A4866.toInt(), 0xFFE9EEF8.toInt(),
                0xFF8B95B1.toInt(), 0xFFC9D3E4.toInt()),
            "cobalt" to intArrayOf(0xFF050A16.toInt(), 0xFF1D4A80.toInt(), 0xFFE6F0FF.toInt(),
                0xFF5E86BE.toInt(), 0xFFD6E4F7.toInt()),
            "ember" to intArrayOf(0xFF110503.toInt(), 0xFF6A2010.toInt(), 0xFFFFEDE4.toInt(),
                0xFFA48C80.toInt(), 0xFFF2E2D6.toInt()),
        )

        private val SESSIONS = mapOf(
            "red" to 0xFFE8503F.toInt(),
            "green" to 0xFF41C391.toInt(),
            "blue" to 0xFF3D93E8.toInt(),
            "purple" to 0xFF9463E6.toInt(),
        )

        private const val PREFS = "market-sessions"
        private const val GROUND_KEY = "dial.palette"
        private const val SESSION_KEY = "dial.session"

        const val DEFAULT_GROUND = "iron"
        const val DEFAULT_SESSION = "red"

        private fun prefs(context: Context) =
            context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** The theme the widget should draw with right now. Unknown names fall back rather than throw. */
        fun load(context: Context): DialTheme {
            val p = prefs(context)
            val ground = GROUNDS[p.getString(GROUND_KEY, DEFAULT_GROUND)] ?: GROUNDS.getValue(DEFAULT_GROUND)
            val open = SESSIONS[p.getString(SESSION_KEY, DEFAULT_SESSION)] ?: SESSIONS.getValue(DEFAULT_SESSION)
            return DialTheme(ground[0], ground[1], ground[2], ground[3], ground[4], open)
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
    }
}
