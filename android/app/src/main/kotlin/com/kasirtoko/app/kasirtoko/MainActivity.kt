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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.kasirtoko.app/hardware"
        private const val ACTION_USB_PERMISSION = "com.kasirtoko.app.USB_PERMISSION"
        private const val REQ_BT_PERMISSIONS = 9101
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var toneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
        super.onDestroy()
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
