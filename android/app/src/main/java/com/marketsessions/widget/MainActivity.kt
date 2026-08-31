package com.marketsessions.widget

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.NumberPicker
import android.widget.TextView
import android.widget.Toast

/**
 * The app is a control panel for the widget and its alerts: add a widget, grant the permissions
 * those two need, choose what to be notified about, or jump to the web app.
 */
class MainActivity : Activity() {

    private lateinit var exactAlarmsButton: Button
    private lateinit var exactAlarmsNote: TextView
    private lateinit var alertsEnabled: CheckBox
    private lateinit var alertsBox: LinearLayout
    private lateinit var marketsBox: LinearLayout
    private lateinit var beforePicker: NumberPicker
    private lateinit var afterPicker: NumberPicker
    private lateinit var onOpen: CheckBox
    private lateinit var onClose: CheckBox
    private lateinit var permissionNote: TextView
    private lateinit var exactAlertNote: TextView

    /** Guards the listeners while the controls are being filled in from stored settings. */
    private var binding = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        exactAlarmsButton = findViewById(R.id.btn_exact_alarms)
        exactAlarmsNote = findViewById(R.id.txt_exact_alarms)
        alertsEnabled = findViewById(R.id.chk_alerts)
        alertsBox = findViewById(R.id.box_alerts)
        marketsBox = findViewById(R.id.box_markets)
        beforePicker = findViewById(R.id.pick_before)
        afterPicker = findViewById(R.id.pick_after)
        onOpen = findViewById(R.id.chk_on_open)
        onClose = findViewById(R.id.chk_on_close)
        permissionNote = findViewById(R.id.txt_alerts_permission)
        exactAlertNote = findViewById(R.id.txt_alerts_exact)

        findViewById<Button>(R.id.btn_add_large).setOnClickListener { addWidget(WidgetKind.LARGE) }
        findViewById<Button>(R.id.btn_add_medium).setOnClickListener { addWidget(WidgetKind.MEDIUM) }
        findViewById<Button>(R.id.btn_add_small).setOnClickListener { addWidget(WidgetKind.SMALL) }
        findViewById<Button>(R.id.btn_open_sessions).setOnClickListener {
            startActivity(Intent(this, SessionsActivity::class.java))
        }
        findViewById<Button>(R.id.btn_open_web).setOnClickListener {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Config.WEB_APP_URL)))
        }
        exactAlarmsButton.setOnClickListener { requestExactAlarms() }

        buildAlertControls()
    }

    override fun onResume() {
        super.onResume()

        val alarms = getSystemService(AlarmManager::class.java)
        val exactGranted = alarms == null || WidgetScheduler.canScheduleExact(alarms)
        val exactVisibility = if (exactGranted) View.GONE else View.VISIBLE
        exactAlarmsButton.visibility = exactVisibility
        exactAlarmsNote.visibility = exactVisibility

        bindAlertControls()
        exactAlertNote.visibility =
            if (exactGranted || !alertsEnabled.isChecked) View.GONE else View.VISIBLE
        permissionNote.visibility =
            if (notificationsAllowed() || !alertsEnabled.isChecked) View.GONE else View.VISIBLE

        MarketWidgetProvider.redrawAll(this)
        WidgetScheduler.scheduleNext(this)
        AlertScheduler.reschedule(this)
    }

    // ---- alerts ----

    private fun buildAlertControls() {
        listOf(beforePicker, afterPicker).forEach {
            it.minValue = 0
            it.maxValue = 120
            it.wrapSelectorWheel = false
        }
        MARKETS.forEach { market ->
            marketsBox.addView(
                CheckBox(this).apply {
                    text = market.name
                    tag = market.name
                    setOnCheckedChangeListener { _, _ -> if (!binding) persist() }
                }
            )
        }
        alertsEnabled.setOnClickListener {
            if (alertsEnabled.isChecked) askForNotificationPermission()
            if (!binding) persist()
        }
        onOpen.setOnClickListener { if (!binding) persist() }
        onClose.setOnClickListener { if (!binding) persist() }
        listOf(beforePicker, afterPicker).forEach { picker ->
            picker.setOnValueChangedListener { _, _, _ -> if (!binding) persist() }
        }
    }

    private fun bindAlertControls() {
        val settings = AlertStore.load(this)
        binding = true
        alertsEnabled.isChecked = settings.enabled
        beforePicker.value = settings.beforeMinutes
        afterPicker.value = settings.afterMinutes
        onOpen.isChecked = settings.onOpen
        onClose.isChecked = settings.onClose
        marketCheckBoxes().forEach { it.isChecked = it.tag as String in settings.markets }
        binding = false
        alertsBox.visibility = if (settings.enabled) View.VISIBLE else View.GONE
    }

    private fun persist() {
        val settings = AlertSettings(
            enabled = alertsEnabled.isChecked,
            beforeMinutes = beforePicker.value,
            afterMinutes = afterPicker.value,
            onOpen = onOpen.isChecked,
            onClose = onClose.isChecked,
            markets = marketCheckBoxes().filter { it.isChecked }.map { it.tag as String }.toSet(),
        )
        AlertStore.save(this, settings)
        AlertScheduler.reschedule(this)

        alertsBox.visibility = if (settings.enabled) View.VISIBLE else View.GONE
        permissionNote.visibility =
            if (notificationsAllowed() || !settings.enabled) View.GONE else View.VISIBLE
    }

    private fun marketCheckBoxes(): List<CheckBox> =
        (0 until marketsBox.childCount).map { marketsBox.getChildAt(it) as CheckBox }

    private fun notificationsAllowed(): Boolean =
        getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: true

    private fun askForNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionNote.visibility =
            if (notificationsAllowed() || !alertsEnabled.isChecked) View.GONE else View.VISIBLE
    }

    // ---- widget and permissions ----

    private fun requestExactAlarms() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:$packageName"),
                )
            )
        }
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
