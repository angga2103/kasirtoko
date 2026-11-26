package com.kasirtoko.app.kasirtoko

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Handles post-reboot recovery cleanly within Android 12-16 restrictions:
 * instead of illegally launching a foreground service from BOOT_COMPLETED background,
 * records interrupted state and prompts the operator with a 1-tap notification.
 */
class ServerBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }

        val prefs = context.getSharedPreferences(PosServerForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
        val wasExpectedRunning = prefs.getBoolean(PosServerForegroundService.KEY_SHOULD_RUN, false)
        prefs.edit().putBoolean(PosServerForegroundService.KEY_IS_RUNNING, false).apply()
        if (!wasExpectedRunning) return

        prefs.edit().putBoolean(PosServerForegroundService.KEY_WAS_INTERRUPTED, true).apply()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel(PosServerForegroundService.CHANNEL_ID) == null
        ) {
            nm.createNotificationChannel(
                NotificationChannel(
                    PosServerForegroundService.CHANNEL_ID,
                    "Layanan Sinkronisasi POS Lokal",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            102,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, PosServerForegroundService.CHANNEL_ID)
            .setContentTitle("KasirToko: Perangkat Baru Dinyalakan Ulang")
            .setContentText("Ketuk untuk memulihkan layanan POS Multi-Perangkat.")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        try {
            nm.notify(PosServerForegroundService.RECOVERY_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {}
    }
}
