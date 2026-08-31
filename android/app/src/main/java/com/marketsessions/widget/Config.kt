package com.marketsessions.widget

import java.time.ZoneId

/**
 * Everything worth tweaking lives here.
 */
object Config {

    /** The dial and the session bands are drawn in this zone, matching the web app's GMT+0 default. */
    val displayZone: ZoneId = ZoneId.of("UTC")

    /** Tapping the widget opens this. */
    const val WEB_APP_URL = "https://eugene8080.github.io/market-sessions/"
}
