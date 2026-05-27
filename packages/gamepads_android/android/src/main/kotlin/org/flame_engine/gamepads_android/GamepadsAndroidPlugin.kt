package org.flame_engine.gamepads_android

import androidx.annotation.NonNull
import android.app.Activity
import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.concurrent.thread

class GamepadsAndroidPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  companion object {
    private const val TAG = "GamepadsAndroidPlugin"
  }
  private lateinit var channel : MethodChannel
  private lateinit var devices : DeviceListener
  private lateinit var events : EventListener
  private var activity: Activity? = null

  private fun listGamepads(): List<Map<String, String>>  {
    return devices.getDevices().map { device ->
      mapOf(
        "id" to device.key.toString(),
        "name" to device.value.name
      )
    }
  }

  // FlutterPlugin
  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "xyz.luan/gamepads")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "listGamepads" -> result.success(listGamepads())
      "rumble" -> handleRumble(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleRumble(call: MethodCall, result: Result) {
    val gamepadIdStr = call.argument<String>("gamepadId") ?: run { result.success(false); return }
    val gamepadId = gamepadIdStr.toIntOrNull() ?: run { result.success(false); return }
    val weakMotor = call.argument<Double>("weakMotor") ?: 0.5
    val strongMotor = call.argument<Double>("strongMotor") ?: 0.5
    val durationMs = call.argument<Int>("durationMs") ?: 200

    val device = devices.getDevices()[gamepadId]
    if (device == null) {
      result.success(false)
      return
    }

    // Try InputDevice vibrator first (API 31+)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val vibratorManager = device.vibratorManager
      val vibrators = vibratorManager.vibratorIds
      if (vibrators.isNotEmpty()) {
        val amplitude = ((strongMotor + weakMotor) / 2.0 * 255).toInt().coerceIn(1, 255)
        val effect = VibrationEffect.createOneShot(durationMs.toLong(), amplitude)
        vibrators.forEach { id -> vibratorManager.getVibrator(id).vibrate(effect) }
        result.success(true)
        return
      }
    }

    // Fallback: device vibrator (API 26+)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      @Suppress("DEPRECATION")
      val vibrator = device.vibrator
      if (vibrator.hasVibrator()) {
        val amplitude = ((strongMotor + weakMotor) / 2.0 * 255).toInt().coerceIn(1, 255)
        vibrator.vibrate(VibrationEffect.createOneShot(durationMs.toLong(), amplitude))
        result.success(true)
        return
      }
    }

    result.success(false)
  }

  // Activity Aware
  override fun onAttachedToActivity(activityPluginBinding: ActivityPluginBinding) {
    onAttachedToActivityShared(activityPluginBinding.activity)
  }

  fun onAttachedToActivityShared(activity: Activity) {
    this.activity = activity
    val compatibleActivity = activity as GamepadsCompatibleActivity
    devices = DeviceListener(
        isGamepadsInputDevice = { compatibleActivity.isGamepadsInputDevice(it) },
        onDeviceAdded = { device ->
            channel.invokeMethod("onGamepadConnected", mapOf(
                "id" to device.id.toString(),
                "name" to device.name,
            ))
        },
        onDeviceRemoved = { deviceId, name ->
            channel.invokeMethod("onGamepadDisconnected", mapOf(
                "id" to deviceId.toString(),
                "name" to name,
            ))
        },
    )
    events = EventListener()
    compatibleActivity.registerInputDeviceListener(devices, handler = null)
    compatibleActivity.registerKeyEventHandler { event ->
      if (devices.containsKey(event.deviceId)) {
        events.onKeyEvent(event, channel)
      } else {
        false
      }
     }
    compatibleActivity.registerMotionEventHandler { event ->
      if (devices.containsKey(event.deviceId)) {
        events.onMotionEvent(event, channel)
      } else {
        false
      }
    }
  }

  override fun onDetachedFromActivity() {
    // No-op
  }

  override fun onDetachedFromActivityForConfigChanges() {
    // No-op
  }

  override fun onReattachedToActivityForConfigChanges(activityPluginBinding: ActivityPluginBinding) {
    onAttachedToActivityShared(activityPluginBinding.activity)
  }
}
