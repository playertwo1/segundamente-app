package com.memexlab.memex

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.nio.charset.StandardCharsets
import java.util.UUID

/**
 * Native Android BLE GATT client for `SegundaMente-Placa` (`esp32-s3-amoled-2-16`).
 * Handles scanning by 128-bit service UUID, connecting, MTU negotiation,
 * TX notifications, TX status reads, and RX writes without third-party plugins.
 */
@SuppressLint("MissingPermission")
class Esp32BleManager(
    private val context: Context,
    private val onLineReceived: (String) -> Unit,
    private val onConnectionChanged: (Boolean) -> Unit,
) {
    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        val RX_UUID: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        val TX_UUID: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        const val DEVICE_NAME_PREFIX = "SegundaMente-Placa"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var bluetoothGatt: BluetoothGatt? = null
    private var rxChar: BluetoothGattCharacteristic? = null
    private var txChar: BluetoothGattCharacteristic? = null
    private var scanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var connectTimeoutRunnable: Runnable? = null
    private var pendingConnectResult: ((Boolean, String?) -> Unit)? = null
    private var pendingWriteResult: ((Boolean, String?) -> Unit)? = null
    private var pendingReadResult: ((String?, String?) -> Unit)? = null
    private val lineBuffer = StringBuilder()
    @Volatile
    var isConnected: Boolean = false
        private set

    private fun adapter(): BluetoothAdapter? {
        val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return mgr?.adapter
    }

    fun scanAndConnect(timeoutMs: Long = 10_000L, callback: (Boolean, String?) -> Unit) {
        val bt = adapter()
        if (bt == null || !bt.isEnabled) {
            callback(false, "bluetooth_disabled")
            return
        }
        val leScanner = bt.bluetoothLeScanner
        if (leScanner == null) {
            callback(false, "ble_scanner_unavailable")
            return
        }
        disconnect()
        pendingConnectResult = callback
        scanner = leScanner

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val dev = result.device ?: return
                stopScan()
                connectDevice(dev)
            }

            override fun onScanFailed(errorCode: Int) {
                stopScan()
                finishConnect(false, "scan_failed_$errorCode")
            }
        }
        scanCallback = cb
        val timeout = Runnable {
            stopScan()
            finishConnect(false, "scan_timeout")
        }
        connectTimeoutRunnable = timeout
        mainHandler.postDelayed(timeout, timeoutMs)
        leScanner.startScan(listOf(filter), settings, cb)
    }

    private fun stopScan() {
        val cb = scanCallback ?: return
        scanCallback = null
        try {
            scanner?.stopScan(cb)
        } catch (_: Throwable) {
        }
    }

    private fun connectDevice(device: BluetoothDevice) {
        bluetoothGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(context, false, gattCallback)
        }
    }

    private fun finishConnect(ok: Boolean, error: String? = null) {
        connectTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        connectTimeoutRunnable = null
        val cb = pendingConnectResult ?: return
        pendingConnectResult = null
        mainHandler.post { cb(ok, error) }
    }

    fun disconnect() {
        stopScan()
        connectTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        connectTimeoutRunnable = null
        pendingWriteResult?.invoke(false, "disconnected")
        pendingWriteResult = null
        pendingReadResult?.invoke(null, "disconnected")
        pendingReadResult = null
        rxChar = null
        txChar = null
        isConnected = false
        lineBuffer.clear()
        bluetoothGatt?.let {
            try {
                it.disconnect()
                it.close()
            } catch (_: Throwable) {
            }
        }
        bluetoothGatt = null
        mainHandler.post { onConnectionChanged(false) }
    }

    fun writeJson(jsonPayload: String, callback: (Boolean, String?) -> Unit) {
        val gatt = bluetoothGatt
        val chr = rxChar
        if (!isConnected || gatt == null || chr == null) {
            callback(false, "not_connected")
            return
        }
        val bytes = jsonPayload.toByteArray(StandardCharsets.UTF_8)
        if (bytes.size > 1000) {
            callback(false, "payload_too_large")
            return
        }
        pendingWriteResult = callback
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(
                chr,
                bytes,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            ) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                chr.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                chr.value = bytes
                gatt.writeCharacteristic(chr)
            }
        }
        if (!started) {
            pendingWriteResult = null
            callback(false, "write_start_failed")
        }
    }

    fun readStatus(callback: (String?, String?) -> Unit) {
        val gatt = bluetoothGatt
        val chr = txChar
        if (!isConnected || gatt == null || chr == null) {
            callback(null, "not_connected")
            return
        }
        pendingReadResult = callback
        if (!gatt.readCharacteristic(chr)) {
            pendingReadResult = null
            callback(null, "read_start_failed")
        }
    }

    private fun handleNotifyBytes(bytes: ByteArray) {
        val chunk = String(bytes, StandardCharsets.UTF_8)
        lineBuffer.append(chunk)
        while (true) {
            val idx = lineBuffer.indexOf("\n")
            if (idx < 0) break
            val line = lineBuffer.substring(0, idx).trim()
            lineBuffer.delete(0, idx + 1)
            if (line.isNotEmpty()) {
                mainHandler.post { onLineReceived(line) }
            }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                val wasConnected = isConnected
                isConnected = false
                rxChar = null
                txChar = null
                try {
                    gatt.close()
                } catch (_: Throwable) {
                }
                if (bluetoothGatt === gatt) bluetoothGatt = null
                finishConnect(false, if (status != BluetoothGatt.GATT_SUCCESS) "gatt_status_$status" else "disconnected")
                if (wasConnected) {
                    mainHandler.post { onConnectionChanged(false) }
                }
                return
            }
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                gatt.requestMtu(512)
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            gatt.discoverServices()
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                finishConnect(false, "discover_failed_$status")
                return
            }
            val svc = gatt.getService(SERVICE_UUID)
            val rx = svc?.getCharacteristic(RX_UUID)
            val tx = svc?.getCharacteristic(TX_UUID)
            if (svc == null || rx == null || tx == null) {
                finishConnect(false, "missing_gatt_characteristics")
                return
            }
            rxChar = rx
            txChar = tx
            gatt.setCharacteristicNotification(tx, true)
            val cccd = tx.getDescriptor(CCCD_UUID)
            if (cccd != null) {
                val value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(cccd, value)
                } else {
                    @Suppress("DEPRECATION")
                    run {
                        cccd.value = value
                        gatt.writeDescriptor(cccd)
                    }
                }
            } else {
                isConnected = true
                finishConnect(true)
                mainHandler.post { onConnectionChanged(true) }
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (descriptor.uuid == CCCD_UUID) {
                val ok = status == BluetoothGatt.GATT_SUCCESS
                isConnected = ok
                finishConnect(ok, if (ok) null else "cccd_failed_$status")
                if (ok) mainHandler.post { onConnectionChanged(true) }
            }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            val cb = pendingWriteResult ?: return
            pendingWriteResult = null
            val ok = status == BluetoothGatt.GATT_SUCCESS
            mainHandler.post { cb(ok, if (ok) null else "write_status_$status") }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            val cb = pendingReadResult ?: return
            pendingReadResult = null
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val text = String(value, StandardCharsets.UTF_8)
                mainHandler.post { cb(text, null) }
            } else {
                mainHandler.post { cb(null, "read_status_$status") }
            }
        }

        @Deprecated("Deprecated in Android API 33")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            @Suppress("DEPRECATION")
            onCharacteristicRead(gatt, characteristic, characteristic.value ?: ByteArray(0), status)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            if (characteristic.uuid == TX_UUID) {
                handleNotifyBytes(value)
            }
        }

        @Deprecated("Deprecated in Android API 33")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (characteristic.uuid == TX_UUID) {
                @Suppress("DEPRECATION")
                handleNotifyBytes(characteristic.value ?: ByteArray(0))
            }
        }
    }
}
