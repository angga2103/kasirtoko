package com.kasirtoko.app.kasirtoko

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.net.Uri
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.kasirtoko.app/hardware"
        private const val SECURITY_CHANNEL = "com.kasirtoko.app/security"
        private const val SERVER_LIFECYCLE_CHANNEL = "com.kasirtoko.app/server_lifecycle"
        private const val ACTION_USB_PERMISSION = "com.kasirtoko.app.USB_PERMISSION"
        private const val REQ_BT_PERMISSIONS = 9101
        private const val REQ_NOTIFICATION_PERMISSION = 9102
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val PEPPER_KEK_ALIAS = "kasirtoko_pepper_kek_v1"
        private const val PEPPER_PREFS = "kasirtoko_keystore_prefs"
        private const val KEY_WRAPPED_PEPPER = "wrapped_pepper_b64"
        private const val KEY_WRAPPED_IV = "wrapped_pepper_iv_b64"
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val cryptoExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var toneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getOrCreatePepper" -> {
                    cryptoExecutor.execute {
                        try {
                            val pepperB64 = getOrCreateKeystorePepperB64()
                            mainHandler.post { result.success(pepperB64) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("KEYSTORE_ERROR", e.message, null) }
                        }
                    }
                }

                "derivePbkdf2HmacSha256" -> {
                    val secretAscii = call.argument<String>("secretAscii") ?: ""
                    val saltBytes = call.argument<ByteArray>("salt") ?: ByteArray(0)
                    val iterations = call.argument<Int>("iterations") ?: 600000
                    val keyLength = call.argument<Int>("keyLength") ?: 32
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.error("UNSUPPORTED_API", "PBKDF2WithHmacSHA256 native requires Android API 26+", null)
                        return@setMethodCallHandler
                    }
                    cryptoExecutor.execute {
                        try {
                            val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                            val spec = PBEKeySpec(secretAscii.toCharArray(), saltBytes, iterations, keyLength * 8)
                            val bytes = factory.generateSecret(spec).encoded
                            spec.clearPassword()
                            mainHandler.post { result.success(bytes) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("PBKDF2_NATIVE_FAILED", e.message, null) }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVER_LIFECYCLE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundServerShell" -> {
                    val storeName = call.argument<String>("storeName") ?: "KasirToko POS"
                    ensureNotificationPermissionIfNeeded()
                    val intent = Intent(this, PosServerForegroundService::class.java).apply {
                        action = PosServerForegroundService.ACTION_START
                        putExtra(PosServerForegroundService.EXTRA_STORE_NAME, storeName)
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(readServerLifecycleStatus())
                }

                "stopForegroundServerShell" -> {
                    val intent = Intent(this, PosServerForegroundService::class.java).apply {
                        action = PosServerForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(readServerLifecycleStatus())
                }

                "getForegroundServerStatus" -> {
                    result.success(readServerLifecycleStatus())
                }

                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    openBatteryOptimizationSettings(result)
                }

                "getActiveLocalIps" -> {
                    result.success(PosServerForegroundService.collectLocalIpv4Summary(this))
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playBeep" -> {
                    val durationMs = (call.argument<Int>("durationMs") ?: 120)
                    playBeepTone(durationMs)
                    result.success(true)
                }

                "getPairedBluetoothDevices" -> {
                    getPairedBluetoothDevices(result)
                }

                "testBluetoothConnection" -> {
                    val address = call.argument<String>("address") ?: ""
                    testBluetoothConnection(address, result)
                }

                "printBluetoothBytes" -> {
                    val address = call.argument<String>("address") ?: ""
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    printBluetoothBytes(address, bytes, result)
                }

                "getUsbDevices" -> {
                    getUsbDevices(result)
                }

                "testUsbConnection" -> {
                    val deviceName = call.argument<String>("deviceName") ?: ""
                    testUsbConnection(deviceName, result)
                }

                "printUsbBytes" -> {
                    val deviceName = call.argument<String>("deviceName") ?: ""
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    printUsbBytes(deviceName, bytes, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        toneGenerator?.release()
        toneGenerator = null
        ioExecutor.shutdownNow()
        cryptoExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun ensureNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQ_NOTIFICATION_PERMISSION
                )
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("BATTERY_OPT_ERROR", e.message, null)
        }
    }

    private fun readServerLifecycleStatus(): Map<String, Any> {
        val prefs = getSharedPreferences(PosServerForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
        return mapOf(
            "shouldRun" to prefs.getBoolean(PosServerForegroundService.KEY_SHOULD_RUN, false),
            "isRunning" to prefs.getBoolean(PosServerForegroundService.KEY_IS_RUNNING, false),
            "wasInterrupted" to prefs.getBoolean(PosServerForegroundService.KEY_WAS_INTERRUPTED, false),
            "ipSummary" to (prefs.getString(PosServerForegroundService.KEY_LAST_IP_SUMMARY, "") ?: ""),
            "lastStartedAtMs" to prefs.getLong(PosServerForegroundService.KEY_LAST_STARTED_AT, 0L),
            "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
            "sdkInt" to Build.VERSION.SDK_INT
        )
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun getOrCreateKeystorePepperKey(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = ks.getKey(PEPPER_KEK_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val builder = KeyGenParameterSpec.Builder(
            PEPPER_KEK_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
        keyGen.init(builder.build())
        return keyGen.generateKey()
    }

    private fun getOrCreateKeystorePepperB64(): String {
        val prefs = getSharedPreferences(PEPPER_PREFS, Context.MODE_PRIVATE)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            val legacyKey = "legacy_api21_pepper_b64"
            val existing = prefs.getString(legacyKey, null)
            if (!existing.isNullOrEmpty()) return existing
            val raw = ByteArray(32)
            SecureRandom().nextBytes(raw)
            val b64 = Base64.encodeToString(raw, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
            prefs.edit().putString(legacyKey, b64).apply()
            return b64
        }

        val wrappedB64 = prefs.getString(KEY_WRAPPED_PEPPER, null)
        val ivB64 = prefs.getString(KEY_WRAPPED_IV, null)
        val kek = getOrCreateKeystorePepperKey()

        if (!wrappedB64.isNullOrEmpty() && !ivB64.isNullOrEmpty()) {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = Base64.decode(ivB64, Base64.NO_WRAP)
            val wrapped = Base64.decode(wrappedB64, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, kek, GCMParameterSpec(128, iv))
            val rawPepper = cipher.doFinal(wrapped)
            return Base64.encodeToString(rawPepper, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        }

        val rawPepper = ByteArray(32)
        SecureRandom().nextBytes(rawPepper)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, kek)
        val iv = cipher.iv
        val wrapped = cipher.doFinal(rawPepper)

        prefs.edit()
            .putString(KEY_WRAPPED_PEPPER, Base64.encodeToString(wrapped, Base64.NO_WRAP))
            .putString(KEY_WRAPPED_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
            .apply()

        return Base64.encodeToString(rawPepper, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    private fun playBeepTone(durationMs: Int) {
        try {
            if (toneGenerator == null) {
                toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 95)
            }
            toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, durationMs)
        } catch (_: Exception) {
            // Ignore audio hardware failures on emulators/silent hardware
        }
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestBluetoothPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN
                ),
                REQ_BT_PERMISSIONS
            )
        }
    }

    private fun getBluetoothAdapter(): BluetoothAdapter? {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    @SuppressLint("MissingPermission")
    private fun getPairedBluetoothDevices(result: MethodChannel.Result) {
        if (!hasBluetoothConnectPermission()) {
            requestBluetoothPermissions()
            result.error("PERMISSION_DENIED", "Izin Bluetooth belum diberikan. Berikan izin lalu coba lagi.", null)
            return
        }

        val adapter = getBluetoothAdapter()
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "Perangkat tidak mendukung Bluetooth.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Bluetooth belum aktif. Nyalakan Bluetooth Android terlebih dahulu.", null)
            return
        }

        try {
            val list = adapter.bondedDevices?.map { dev ->
                mapOf(
                    "name" to (dev.name ?: "Perangkat Bluetooth"),
                    "address" to dev.address
                )
            } ?: emptyList()
            result.success(list)
        } catch (e: Exception) {
            result.error("BT_LIST_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun testBluetoothConnection(address: String, result: MethodChannel.Result) {
        if (address.isBlank()) {
            result.error("INVALID_ADDRESS", "Alamat MAC Bluetooth kosong.", null)
            return
        }
        if (!hasBluetoothConnectPermission()) {
            requestBluetoothPermissions()
            result.error("PERMISSION_DENIED", "Izin Bluetooth belum diberikan.", null)
            return
        }

        val adapter = getBluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Bluetooth tidak aktif.", null)
            return
        }

        ioExecutor.execute {
            var socket: BluetoothSocket? = null
            try {
                val device = adapter.getRemoteDevice(address)
                socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                adapter.cancelDiscovery()
                socket.connect()
                mainHandler.post { result.success(mapOf("connected" to true, "message" to "Terhubung ke ${device.name ?: address}")) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("BT_CONNECT_FAILED", "Gagal terhubung ke printer ($address): ${e.message}", null)
                }
            } finally {
                try {
                    socket?.close()
                } catch (_: Exception) {}
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun printBluetoothBytes(address: String, bytes: ByteArray, result: MethodChannel.Result) {
        if (address.isBlank()) {
            result.error("INVALID_ADDRESS", "Alamat MAC Bluetooth kosong.", null)
            return
        }
        if (!hasBluetoothConnectPermission()) {
            requestBluetoothPermissions()
            result.error("PERMISSION_DENIED", "Izin Bluetooth belum diberikan.", null)
            return
        }
        val adapter = getBluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Bluetooth tidak aktif.", null)
            return
        }

        ioExecutor.execute {
            var socket: BluetoothSocket? = null
            try {
                val device = adapter.getRemoteDevice(address)
                socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                adapter.cancelDiscovery()
                socket.connect()
                val out = socket.outputStream
                // Send in 512-byte chunks for stability across cheap thermal printers
                var offset = 0
                val chunkSize = 512
                while (offset < bytes.size) {
                    val end = minOf(offset + chunkSize, bytes.size)
                    out.write(bytes, offset, end - offset)
                    out.flush()
                    offset = end
                    Thread.sleep(15)
                }
                Thread.sleep(80)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("BT_PRINT_FAILED", "Gagal mencetak ke Bluetooth ($address): ${e.message}", null)
                }
            } finally {
                try {
                    socket?.close()
                } catch (_: Exception) {}
            }
        }
    }

    private fun getUsbDevices(result: MethodChannel.Result) {
        try {
            val usbManager = getSystemService(Context.USB_SERVICE) as? UsbManager
            if (usbManager == null) {
                result.success(emptyList<Map<String, Any>>())
                return
            }
            val list = usbManager.deviceList.values.map { dev ->
                mapOf(
                    "deviceName" to dev.deviceName,
                    "productName" to (dev.productName ?: "USB Device"),
                    "manufacturerName" to (dev.manufacturerName ?: ""),
                    "vendorId" to dev.vendorId,
                    "productId" to dev.productId,
                    "hasPermission" to usbManager.hasPermission(dev)
                )
            }
            result.success(list)
        } catch (e: Exception) {
            result.error("USB_LIST_ERROR", e.message, null)
        }
    }

    private fun findUsbEndpoint(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        // First prefer explicit printer class interface (class 7)
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT
                ) {
                    if (intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) {
                        return Pair(intf, ep)
                    }
                }
            }
        }
        // Fallback: any bulk OUT endpoint
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT
                ) {
                    return Pair(intf, ep)
                }
            }
        }
        return null
    }

    private fun testUsbConnection(deviceName: String, result: MethodChannel.Result) {
        val usbManager = getSystemService(Context.USB_SERVICE) as? UsbManager
        if (usbManager == null) {
            result.error("NO_USB", "USB Host tidak tersedia.", null)
            return
        }
        val device = usbManager.deviceList[deviceName]
        if (device == null) {
            result.error("USB_NOT_FOUND", "Printer USB tidak terdeteksi ($deviceName).", null)
            return
        }
        if (!usbManager.hasPermission(device)) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val intent = Intent(ACTION_USB_PERMISSION).apply { setPackage(packageName) }
            val permissionIntent = PendingIntent.getBroadcast(this, 0, intent, flags)
            usbManager.requestPermission(device, permissionIntent)
            result.error("USB_PERMISSION_REQUESTED", "Silakan izinkan akses USB OTG di popup Android lalu coba lagi.", null)
            return
        }
        val pair = findUsbEndpoint(device)
        if (pair == null) {
            result.error("USB_NO_ENDPOINT", "Perangkat USB tidak memiliki endpoint output printer.", null)
            return
        }
        result.success(mapOf("connected" to true, "message" to "USB ${device.productName ?: deviceName} siap mencetak"))
    }

    private fun printUsbBytes(deviceName: String, bytes: ByteArray, result: MethodChannel.Result) {
        val usbManager = getSystemService(Context.USB_SERVICE) as? UsbManager
        if (usbManager == null) {
            result.error("NO_USB", "USB Host tidak tersedia.", null)
            return
        }
        val device = usbManager.deviceList[deviceName]
        if (device == null) {
            result.error("USB_NOT_FOUND", "Perangkat USB ($deviceName) tidak terpasang.", null)
            return
        }
        if (!usbManager.hasPermission(device)) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val intent = Intent(ACTION_USB_PERMISSION).apply { setPackage(packageName) }
            val permissionIntent = PendingIntent.getBroadcast(this, 0, intent, flags)
            usbManager.requestPermission(device, permissionIntent)
            result.error("USB_PERMISSION_REQUESTED", "Mohon setujui akses USB OTG pada dialog Android dan cetak ulang.", null)
            return
        }
        val target = findUsbEndpoint(device)
        if (target == null) {
            result.error("USB_NO_ENDPOINT", "Endpoint bulk output printer tidak ditemukan.", null)
            return
        }

        ioExecutor.execute {
            var connection: UsbDeviceConnection? = null
            try {
                connection = usbManager.openDevice(device)
                if (connection == null) {
                    mainHandler.post { result.error("USB_OPEN_FAILED", "Gagal membuka koneksi perangkat USB.", null) }
                    return@execute
                }
                val (intf, endpoint) = target
                if (!connection.claimInterface(intf, true)) {
                    mainHandler.post { result.error("USB_CLAIM_FAILED", "Gagal mengklaim antarmuka printer USB.", null) }
                    return@execute
                }

                val maxPacket = maxOf(64, endpoint.maxPacketSize * 8)
                var offset = 0
                while (offset < bytes.size) {
                    val len = minOf(maxPacket, bytes.size - offset)
                    val chunk = bytes.copyOfRange(offset, offset + len)
                    val transferred = connection.bulkTransfer(endpoint, chunk, len, 3000)
                    if (transferred < 0) {
                        mainHandler.post { result.error("USB_WRITE_FAILED", "Transfer data USB terputus.", null) }
                        connection.releaseInterface(intf)
                        return@execute
                    }
                    offset += transferred
                }
                connection.releaseInterface(intf)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("USB_PRINT_ERROR", "Gagal mencetak USB: ${e.message}", null) }
            } finally {
                connection?.close()
            }
        }
    }
}
