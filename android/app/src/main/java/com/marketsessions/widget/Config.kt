package com.marketsessions.widget

import java.time.ZoneId

/**
 * Everything worth tweaking lives here.
 */
object Config {

    /**
     * The zone the dial and the session bands are drawn in: the phone's own, so the widget agrees
     * with the clock in the status bar. It is read on every redraw rather than cached, so a
     * change of zone — travelling, or the twice yearly clock change — takes effect on the next
     * tick. Return `ZoneId.of("UTC")` here to pin the dial to GMT+0 instead, matching the web
     * app's default setting.
     */
    fun displayZone(): ZoneId = ZoneId.systemDefault()

    /**
     * The hosted copy, offered only behind an explicit "open in a browser" action. The widget and
     * its notifications open [SessionsActivity] instead: this URL resolves through whichever app
     * has claimed github.io links, which is not necessarily a browser.
     */
    const val WEB_APP_URL = "https://eugene8080.github.io/market-sessions/"
}
