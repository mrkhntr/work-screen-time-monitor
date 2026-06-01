package com.mrkhntr.workscreentime.notify

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.text.format.DateFormat
import com.mrkhntr.workscreentime.R
import java.util.Date

class Notifier(private val context: Context) {
    private val channelId = "wst.events"

    init {
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(channelId, "Work Screen Time", NotificationManager.IMPORTANCE_DEFAULT)
        manager.createNotificationChannel(channel)
    }

    fun notifySnoozed(untilMs: Long) {
        val time = DateFormat.getTimeFormat(context).format(Date(untilMs))
        post("Snoozed", "Snoozed until $time")
    }

    private fun post(title: String, text: String) {
        if (!canPost()) return
        val notification = Notification.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify((System.nanoTime() and 0x7FFFFF).toInt(), notification)
    }

    private fun canPost(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }
}
