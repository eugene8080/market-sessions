package com.marketsessions.widget

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.ViewGroup
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
        }
        setContentView(web)

        if (savedInstanceState == null) web.loadUrl(ASSET_PAGE)
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
