package com.mrkhntr.workscreentime.enforcement

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import com.mrkhntr.workscreentime.WstApp
import com.mrkhntr.workscreentime.notify.Notifier
import com.mrkhntr.workscreentime.notify.WebhookSender
import org.json.JSONObject
import java.util.TimeZone

/// The enforcement brain. Detects the foreground app and a periodic tick, feeds
/// them to the shared core (QuickJS), and runs the returned effects. All
/// decisions (downtime active? app blocked? escalation? webhook?) live in core.js.
class AppMonitorService : AccessibilityService() {
    private val app: WstApp get() = applicationContext as WstApp
    private lateinit var overlay: OverlayController
    private lateinit var notifier: Notifier
    private val webhook = WebhookSender()
    private val handler = Handler(Looper.getMainLooper())
    private val tickRunnable = Runnable { tick() }
    private var lastForegroundPackage: String? = null

    override fun onServiceConnected() {
        overlay = OverlayController(this)
        notifier = Notifier(applicationContext)
        tick()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // ignore our own UI / overlay
        if (pkg == lastForegroundPackage) return // debounce repeats
        lastForegroundPackage = pkg
        dispatch(JSONObject().put("type", "foregroundChanged").put("appId", pkg))
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        handler.removeCallbacks(tickRunnable)
        overlay.hide()
        return super.onUnbind(intent)
    }

    private fun tick() {
        dispatch(JSONObject().put("type", "tick"))
    }

    private fun nowJson(): String {
        val now = System.currentTimeMillis()
        val tzOffsetMin = TimeZone.getDefault().getOffset(now) / 60000
        return JSONObject().put("epochMs", now).put("tzOffsetMin", tzOffsetMin).toString()
    }

    private fun dispatch(event: JSONObject) {
        val core = app.core
        val state = app.stores.loadStateJson(core)
        val config = app.stores.loadConfigJson(core)
        val resultJson = core.reduce(state, event.toString(), nowJson(), config)
        val result = runCatching { JSONObject(resultJson) }.getOrNull() ?: return

        result.optJSONObject("state")?.let { app.stores.saveStateJson(it.toString()) }

        val effects = result.optJSONArray("effects") ?: return
        for (i in 0 until effects.length()) {
            apply(effects.optJSONObject(i) ?: continue)
        }
    }

    private fun apply(effect: JSONObject) {
        when (effect.optString("type")) {
            "showOverlay" -> showOverlay(effect)
            "hideOverlay" -> overlay.hide()
            "notifySnoozed" -> notifier.notifySnoozed(effect.optLong("untilMs"))
            "sendWebhook" -> effect.optJSONObject("request")?.let { webhook.send(it) }
            "scheduleWake" -> {
                val delay = (effect.optLong("atEpochMs") - System.currentTimeMillis()).coerceIn(1_000, 120_000)
                handler.removeCallbacks(tickRunnable)
                handler.postDelayed(tickRunnable, delay)
            }
            else -> Unit // setStatus is macOS menu-only
        }
    }

    private fun showOverlay(effect: JSONObject) {
        val escalation = effect.optJSONObject("escalation") ?: JSONObject()
        val state = BlockUiState(
            title = escalation.optString("title", "Time to stop"),
            message = escalation.optString("message", ""),
            requiresPhrase = escalation.optBoolean("requiresPhrase"),
            requiresReason = escalation.optBoolean("requiresReason"),
            confirmationPhrase = escalation.optString("confirmationPhrase", ""),
        )
        overlay.show(
            state,
            onSnooze = { reason -> dispatch(JSONObject().put("type", "userSnoozed").put("reason", reason ?: JSONObject.NULL)) },
            onDismiss = { reason -> dispatch(JSONObject().put("type", "userDismissed").put("reason", reason ?: JSONObject.NULL)) },
        )
    }
}
