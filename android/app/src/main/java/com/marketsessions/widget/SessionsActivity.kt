package com.marketsessions.widget

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView

/**
 * The sessions view itself, and the app's main screen.
 *
 * It is the same page the web app serves, copied into the APK's assets at build time, so it runs
 * with no network, no browser and no hosted URL — the widget and its notifications open this
 * rather than handing a github.io link to whichever app has claimed those.
 */
class SessionsActivity : Activity() {

    private lateinit var web: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        web = WebView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            settings.javaScriptEnabled = true      // the dial and the clocks are all script
            settings.domStorageEnabled = true      // so the page can remember its settings
            settings.builtInZoomControls = false
            setBackgroundColor(0xFF101218.toInt()) // avoid a white flash before the page paints

            // The page is the app's only settings screen, so the home screen widget has to hear
            // about a theme change from it. Exposing an object to JavaScript is only safe because
            // this page is an asset shipped inside the APK rather than anything fetched from the
            // network — see ASSET_PAGE below.
            addJavascriptInterface(ThemeBridge(this@SessionsActivity), "MarketSessionsHost")
        }
        setContentView(web)

        if (savedInstanceState == null) web.loadUrl(ASSET_PAGE)
    }

    /** What the page calls when the dial theme changes. */
    private class ThemeBridge(private val context: android.content.Context) {

        @JavascriptInterface
        fun setDialTheme(ground: String, session: String) {
            // Arrives on a WebView worker thread; both the store and the redraw are safe off the
            // main thread, and doing it here keeps the page's own handler snappy.
            if (DialTheme.save(context, ground, session)) {
                MarketWidgetProvider.redrawAll(context)
            }
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.sessions, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId != R.id.action_settings) return super.onOptionsItemSelected(item)
        startActivity(Intent(this, MainActivity::class.java))
        return true
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
        web.restoreState(savedInstanceState)
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    private companion object {
        const val ASSET_PAGE = "file:///android_asset/index.html"
    }
}
