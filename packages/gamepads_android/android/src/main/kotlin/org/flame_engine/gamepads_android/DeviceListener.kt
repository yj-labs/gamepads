package org.flame_engine.gamepads_android

import android.hardware.input.InputManager
import android.util.Log
import android.view.InputDevice

class DeviceListener(
    val isGamepadsInputDevice: (device: InputDevice) -> Boolean,
    val onDeviceAdded: ((InputDevice) -> Unit)? = null,
    val onDeviceRemoved: ((deviceId: Int, name: String) -> Unit)? = null,
): InputManager.InputDeviceListener {
    private val devicesLookup: MutableMap<Int, InputDevice> = mutableMapOf()
    private val TAG = "ConnectionListener"

    init {
        getGameControllerIds()
    }

    fun getDevices(): Map<Int, InputDevice> {
        return devicesLookup.toMap()
    }

    private fun getGameControllerIds() {
        val gameControllerDeviceIds = mutableListOf<Int>()
        val deviceIds = InputDevice.getDeviceIds()
        deviceIds.forEach { deviceId ->
            InputDevice.getDevice(deviceId).apply {
                if (this != null) {
                    if (isGamepadsInputDevice(this)) {
                        Log.i(TAG, "${this.name} passed input device test")
                        devicesLookup[deviceId] = this
                    } else {
                        Log.e(TAG, "${this.name} failed input device test")
                    }
                }
            }
        }
    }

    fun containsKey(deviceId: Int): Boolean {
        return devicesLookup.containsKey(deviceId)
    }

    override fun onInputDeviceAdded(deviceId: Int) {
        val device: InputDevice? = InputDevice.getDevice(deviceId)
        if (device != null) {
            if (isGamepadsInputDevice(device)) {
                Log.i(TAG, "${device.name} passed input device test")
                devicesLookup[deviceId] = device
                onDeviceAdded?.invoke(device)
            } else {
                Log.e(TAG, "${device.name} failed input device test")
            }
        }
    }

    override fun onInputDeviceRemoved(deviceId: Int) {
        val name = devicesLookup[deviceId]?.name ?: "Unknown"
        devicesLookup.remove(deviceId)
        onDeviceRemoved?.invoke(deviceId, name)
    }

    override fun onInputDeviceChanged(deviceId: Int) {
        val device: InputDevice? = InputDevice.getDevice(deviceId)
        if (device != null && isGamepadsInputDevice(device)) {
            devicesLookup[deviceId] = device
        } else {
            devicesLookup.remove(deviceId)
        }
    }
}