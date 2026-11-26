package com.kasirtoko.app.kasirtoko

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.net.Inet4Address

/**
 * Persistent Android Foreground Service lifecycle shell (specialUse) prepared for
 * the upcoming local POS LAN/Hotspot server in Phase 2.
 *
 * NOTE: This Phase 1 service manages OS foreground lifecycle, notification,
 * optional partial wake lock, and network interface change tracking ONLY.
 * No HTTP/WebSocket LAN server socket is started in Phase 1.
 * Android OS/OEM battery policies can still terminate background processes in
 * extreme conditions; this service persists state for deterministic recovery.
 */
class PosServerForegroundService : Service() {
    companion object {
        const val PREFS_NAME = "kasirtoko_server_lifecycle_prefs"
        const val KEY_SHOULD_RUN = "server_should_run"
        const val KEY_IS_RUNNING = "server_is_running"
        const val KEY_WAS_INTERRUPTED = "server_was_interrupted"
        const val KEY_LAST_IP_SUMMARY = "server_last_ip_summary"
        const val KEY_LAST_STARTED_AT = "server_last_started_at"
        const val KEY_PORT = "server_port"
        const val KEY_CONNECTED_TERMINALS = "server_connected_terminals"
        const val KEY_SERVER_LIVE = "server_is_live"

        const val CHANNEL_ID = "kasirtoko_pos_server_channel"
        const val NOTIFICATION_ID = 7201
        const val RECOVERY_NOTIFICATION_ID = 7202

        const val ACTION_START = "com.kasirtoko.app.action.START_SERVER_SHELL"
        const val ACTION_STOP = "com.kasirtoko.app.action.STOP_SERVER_SHELL"
        const val ACTION_UPDATE_STATUS = "com.kasirtoko.app.action.UPDATE_SERVER_STATUS"
        const val EXTRA_STORE_NAME = "store_name"
        const val EXTRA_PORT = "server_port"
        const val EXTRA_CONNECTED_TERMINALS = "connected_terminals"
        const val EXTRA_SERVER_LIVE = "server_live"

        fun collectLocalIpv4Summary(context: Context): String {
            return try {
                val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                val activeIps = mutableListOf<String>()
                if (cm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    @Suppress("DEPRECATION")
                    for (net in cm.allNetworks) {
                        val lp: LinkProperties? = cm.getLinkProperties(net)
                        lp?.linkAddresses?.forEach { la ->
                            val addr = la.address
                            if (addr is Inet4Address && !addr.isLoopbackAddress) {
                                val host = addr.hostAddress ?: ""
                                if (host.isNotEmpty() && !activeIps.contains(host)) {
                                    activeIps.add(host)
                                }
                            }
                        }
                    }
                }
                if (activeIps.isEmpty()) {
                    val en = java.net.NetworkInterface.getNetworkInterfaces()
                    while (en != null && en.hasMoreElements()) {
                        val intf = en.nextElement()
                        if (!intf.isUp || intf.isLoopback) continue
                        val addrs = intf.inetAddresses
                        while (addrs.hasMoreElements()) {
                            val addr = addrs.nextElement()
                            if (addr is Inet4Address && !addr.isLoopbackAddress) {
                                val host = addr.hostAddress ?: ""
                                if (host.isNotEmpty() && !activeIps.contains(host)) {
                                    activeIps.add(host)
                                }
                            }
                        }
                    }
                }
                if (activeIps.isEmpty()) "Menunggu jaringan Wi-Fi/Hotspot" else activeIps.joinToString(", ")
            } catch (_: Exception) {
                "Tidak tersedia"
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var storeName: String = "KasirToko POS"
    private var serverPort: Int = 8443
    private var connectedCount: Int = 0
    private var serverLive: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        registerNetworkObserver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            markStoppedCleanly()
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_UPDATE_STATUS) {
            storeName = intent.getStringExtra(EXTRA_STORE_NAME)?.takeIf { it.isNotBlank() } ?: storeName
            serverPort = intent.getIntExtra(EXTRA_PORT, serverPort)
            connectedCount = intent.getIntExtra(EXTRA_CONNECTED_TERMINALS, connectedCount)
            serverLive = intent.getBooleanExtra(EXTRA_SERVER_LIVE, serverLive)
            val ipSummary = collectLocalIpv4Summary(this)
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString(KEY_LAST_IP_SUMMARY, ipSummary)
                .putInt(KEY_PORT, serverPort)
                .putInt(KEY_CONNECTED_TERMINALS, connectedCount)
                .putBoolean(KEY_SERVER_LIVE, serverLive)
                .apply()
            updateNotification(ipSummary)
            return START_STICKY
        }

        storeName = intent?.getStringExtra(EXTRA_STORE_NAME)?.takeIf { it.isNotBlank() } ?: "KasirToko POS"
        serverPort = intent?.getIntExtra(EXTRA_PORT, 8443) ?: 8443
        val ipSummary = collectLocalIpv4Summary(this)

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_SHOULD_RUN, true)
            .putBoolean(KEY_IS_RUNNING, true)
            .putBoolean(KEY_WAS_INTERRUPTED, false)
            .putString(KEY_LAST_IP_SUMMARY, ipSummary)
            .putInt(KEY_PORT, serverPort)
            .putLong(KEY_LAST_STARTED_AT, System.currentTimeMillis())
            .apply()

        val notification = buildNotification(ipSummary)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep foreground service alive if user swipes Activity from Recents while server mode is enabled.
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_SHOULD_RUN, false)) {
            val ipSummary = collectLocalIpv4Summary(this)
            prefs.edit().putString(KEY_LAST_IP_SUMMARY, ipSummary).apply()
            updateNotification(ipSummary)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val shouldRun = prefs.getBoolean(KEY_SHOULD_RUN, false)
        prefs.edit()
            .putBoolean(KEY_IS_RUNNING, false)
            .putBoolean(KEY_WAS_INTERRUPTED, shouldRun)
            .apply()

        unregisterNetworkObserver()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun markStoppedCleanly() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_SHOULD_RUN, false)
            .putBoolean(KEY_IS_RUNNING, false)
            .putBoolean(KEY_WAS_INTERRUPTED, false)
            .apply()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Layanan Sinkronisasi POS Lokal",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Menjaga kesiapan layanan sinkronisasi POS multi-perangkat di jaringan lokal."
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(ipSummary: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPending = PendingIntent.getActivity(
            this,
            100,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, PosServerForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            101,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val titleText = if (serverLive) {
            "$storeName • Server POS Aktif (:$serverPort • $connectedCount terminal)"
        } else {
            "$storeName • Mode Server Siap"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(titleText)
            .setContentText("IP Lokal: $ipSummary")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Hentikan", stopPending)
            .build()
    }

    private fun updateNotification(ipSummary: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        nm.notify(NOTIFICATION_ID, buildNotification(ipSummary))
    }

    private fun registerNetworkObserver() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = refreshNetworkState()
            override fun onLost(network: Network) = refreshNetworkState()
            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) = refreshNetworkState()
        }
        try {
            cm.registerNetworkCallback(req, cb)
            networkCallback = cb
        } catch (_: Exception) {}
    }

    private fun unregisterNetworkObserver() {
        val cb = networkCallback ?: return
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        try {
            cm.unregisterNetworkCallback(cb)
        } catch (_: Exception) {}
        networkCallback = null
    }

    private fun refreshNetworkState() {
        val ipSummary = collectLocalIpv4Summary(this)
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LAST_IP_SUMMARY, ipSummary)
            .apply()
        updateNotification(ipSummary)
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "KasirToko::PosServerWakeLock").apply {
                    setReferenceCounted(false)
                    acquire(12 * 60 * 60 * 1000L) // Bounded 12h operational window, refreshed on restart
                }
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        wakeLock = null
    }
}
