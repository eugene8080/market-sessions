package com.marketsessions.widget

import android.app.Activity
import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.TextView
import android.widget.Toast

/**
 * The app itself is only a launcher for the widget: add it, grant the alarm permission that keeps
 * the hands ticking, or jump to the web app.
 */
class MainActivity : Activity() {

    private lateinit var exactAlarmsButton: Button
    private lateinit var exactAlarmsNote: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        exactAlarmsButton = findViewById(R.id.btn_exact_alarms)
        exactAlarmsNote = findViewById(R.id.txt_exact_alarms)

        findViewById<Button>(R.id.btn_add_large).setOnClickListener { addWidget(WidgetKind.LARGE) }
        findViewById<Button>(R.id.btn_add_medium).setOnClickListener { addWidget(WidgetKind.MEDIUM) }
        findViewById<Button>(R.id.btn_add_small).setOnClickListener { addWidget(WidgetKind.SMALL) }
        findViewById<Button>(R.id.btn_open_web).setOnClickListener {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Config.WEB_APP_URL)))
        }
        exactAlarmsButton.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:$packageName"),
                    )
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val alarms = getSystemService(AlarmManager::class.java)
        val granted = alarms == null || WidgetScheduler.canScheduleExact(alarms)
        val visibility = if (granted) View.GONE else View.VISIBLE
        exactAlarmsButton.visibility = visibility
        exactAlarmsNote.visibility = visibility
        MarketWidgetProvider.redrawAll(this)
        WidgetScheduler.scheduleNext(this)
    }

    private fun addWidget(kind: WidgetKind) {
        val manager = getSystemService(AppWidgetManager::class.java)
        val provider = ComponentName(this, kind.provider)
        if (manager != null && manager.isRequestPinAppWidgetSupported) {
            manager.requestPinAppWidget(provider, null, null)
        } else {
            Toast.makeText(this, R.string.pin_unsupported, Toast.LENGTH_LONG).show()
        }
    }
}
