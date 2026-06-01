package com.mrkhntr.workscreentime

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrkhntr.workscreentime.enforcement.AppMonitorService
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : ComponentActivity() {
    private val app: WstApp get() = application as WstApp
    private val refresh = mutableIntStateOf(0)
    private val notifLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { refresh.intValue++ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize()) { Home() }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refresh.intValue++
    }

    // MARK: - config helpers (the core owns the schema; we edit JSON + normalize)

    private fun loadConfig(): JSONObject = runCatching { JSONObject(app.stores.loadConfigJson(app.core)) }.getOrDefault(JSONObject())

    private fun saveConfig(obj: JSONObject) {
        app.stores.saveConfigJson(app.core.normalizeConfig(obj.toString()))
        refresh.intValue++
    }

    private fun blockedPackages(config: JSONObject): Set<String> {
        val arr = config.optJSONObject("appBlocking")?.optJSONArray("blockedApps") ?: return emptySet()
        return (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.optString("identifier") }.filter { it.isNotEmpty() }.toSet()
    }

    private fun setAppBlocked(pkg: String, label: String, blocked: Boolean) {
        val config = loadConfig()
        val blocking = config.optJSONObject("appBlocking") ?: JSONObject()
        val existing = blocking.optJSONArray("blockedApps") ?: JSONArray()
        val kept = JSONArray()
        for (i in 0 until existing.length()) {
            val app = existing.optJSONObject(i) ?: continue
            if (app.optString("identifier") != pkg) kept.put(app)
        }
        if (blocked) {
            kept.put(JSONObject().put("identifier", pkg).put("displayName", label).put("isEnabled", true))
        }
        blocking.put("blockedApps", kept)
        config.put("appBlocking", blocking)
        saveConfig(config)
    }

    private fun setBlockingEnabled(enabled: Boolean) {
        val config = loadConfig()
        val blocking = config.optJSONObject("appBlocking") ?: JSONObject()
        blocking.put("isEnabled", enabled)
        config.put("appBlocking", blocking)
        saveConfig(config)
    }

    private fun launchableApps(): List<Pair<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(intent, 0)
            .map { it.loadLabel(packageManager).toString() to it.activityInfo.packageName }
            .filter { it.second != packageName }
            .distinctBy { it.second }
            .sortedBy { it.first.lowercase() }
    }

    // MARK: - permission state

    private fun canOverlay(): Boolean = Settings.canDrawOverlays(this)

    private fun accessibilityEnabled(): Boolean {
        val expected = ComponentName(this, AppMonitorService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    private fun canNotify(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    @Composable
    private fun Home() {
        val tick by refresh
        val config = rememberConfig(tick)
        val blockingEnabled = config.optJSONObject("appBlocking")?.optBoolean("isEnabled") ?: false
        val blocked = blockedPackages(config)
        val apps = rememberApps(tick)

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                Text("Work Screen Time", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.headlineSmall)
                Text("Block your work apps during downtime.", style = MaterialTheme.typography.bodyMedium)
            }
            item {
                Text("Permissions", fontWeight = FontWeight.SemiBold)
                PermissionRow("Display over other apps", canOverlay()) {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                }
                PermissionRow("Accessibility (detect foreground app)", accessibilityEnabled()) {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                }
                PermissionRow("Notifications", canNotify()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                }
            }
            item {
                HorizontalDivider()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Block apps during downtime", modifier = Modifier.weight(1f))
                    Switch(checked = blockingEnabled, onCheckedChange = { setBlockingEnabled(it) })
                }
                Text("Choose which apps to wall off:", style = MaterialTheme.typography.bodyMedium)
            }
            items(apps) { appEntry ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Checkbox(
                        checked = blocked.contains(appEntry.second),
                        onCheckedChange = { setAppBlocked(appEntry.second, appEntry.first, it) },
                    )
                    Text(appEntry.first, modifier = Modifier.weight(1f))
                }
            }
        }
    }

    @Composable
    private fun rememberConfig(tick: Int): JSONObject {
        return androidx.compose.runtime.remember(tick) { loadConfig() }
    }

    @Composable
    private fun rememberApps(tick: Int): List<Pair<String, String>> {
        return androidx.compose.runtime.remember(tick == 0) { launchableApps() }
    }

    @Composable
    private fun PermissionRow(label: String, granted: Boolean, onGrant: () -> Unit) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
            Text(label, modifier = Modifier.weight(1f))
            if (granted) {
                Text("Granted", color = MaterialTheme.colorScheme.primary)
            } else {
                Button(onClick = onGrant) { Text("Grant") }
            }
        }
    }
}
