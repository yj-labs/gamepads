import 'package:gamepads_platform_interface/api/gamepad_controller.dart';
import 'package:gamepads_platform_interface/api/gamepad_event.dart';
import 'package:gamepads_platform_interface/method_channel_gamepads_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class GamepadsPlatformInterface extends PlatformInterface {
  static final Object _token = Object();

  GamepadsPlatformInterface() : super(token: _token);

  /// The default instance of [GamepadsPlatformInterface] to use.
  ///
  /// Defaults to [MethodChannelGamepadsPlatformInterface].
  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [GamepadsPlatformInterface] when they register
  /// themselves.
  static GamepadsPlatformInterface instance =
      MethodChannelGamepadsPlatformInterface();

  Future<List<GamepadController>> listGamepads();

  Stream<GamepadEvent> get gamepadEventsStream;

  /// Stream of gamepad connection events.
  Stream<GamepadController> get gamepadConnectedStream;

  /// Stream of gamepad disconnection events.
  Stream<GamepadController> get gamepadDisconnectedStream;

  /// Sends a haptic/rumble effect to the specified gamepad.
  ///
  /// [gamepadId] — the id from [GamepadController.id].
  /// [weakMotor] — intensity of the high-frequency (right/weak) motor, 0.0–1.0.
  /// [strongMotor] — intensity of the low-frequency (left/strong) motor, 0.0–1.0.
  /// [durationMs] — duration in milliseconds.
  ///
  /// Returns true if the platform accepted the request, false if unsupported.
  Future<bool> rumble({
    required String gamepadId,
    double weakMotor = 0.5,
    double strongMotor = 0.5,
    int durationMs = 200,
  });

  Stream<GamepadEvent> eventsByGamepad(String gamepadId) =>
      gamepadEventsStream.where((event) => event.gamepadId == gamepadId);
}
