import Cocoa
import CoreHaptics
import GameController
import FlutterMacOS
import IOKit
import IOKit.hid

enum FixedKey: String {
    case buttonMenu
    case buttonOptions
    case buttonHome
    case touchpadButton
}

public class GamepadsDarwinPlugin: NSObject, FlutterPlugin {
    let channel: FlutterMethodChannel
    let gamepads = GamepadsListener()
    var hidManager: IOHIDManager?
    var lastHomeState: Bool = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()

        self.gamepads.listener = onGamepadEvent
        self.gamepads.connectListener = { [weak self] id, gamepad in
            guard let self = self else { return }
            self.channel.invokeMethod("onGamepadConnected", arguments: [
                "id": String(id),
                "name": self.getName(gamepad: gamepad),
            ])
        }
        self.gamepads.disconnectListener = { [weak self] id, gamepad in
            guard let self = self else { return }
            self.channel.invokeMethod("onGamepadDisconnected", arguments: [
                "id": String(id),
                "name": self.getName(gamepad: gamepad),
            ])
        }
        setupHIDListener()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "xyz.luan/gamepads", binaryMessenger: registrar.messenger)
        let instance = GamepadsDarwinPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listGamepads":
            result(listGamepads())
        case "rumble":
            handleRumble(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func onGamepadEvent(gamepadId: Int, gamepad: GCExtendedGamepad, element: GCControllerElement) {
        let fixedKey = getFixedKey(gamepad: gamepad, element: element)
        for (key, value) in getValues(element: element, fixedKey: fixedKey) {
            let arguments: [String: Any] = [
                "gamepadId": String(gamepadId),
                "time": Int(getTimestamp(gamepad: gamepad)),
                "type": element.isAnalog ? "analog" : "button",
                "key": key,
                "value": value,
            ]
            channel.invokeMethod("onGamepadEvent", arguments: arguments)
        }
    }

    /// Returns a fixed key name for elements whose SF Symbol names are
    /// ambiguous across controller types (e.g. both DualSense system
    /// buttons report "capsule.portrait"). For other elements, returns
    /// nil so the caller falls back to SF Symbol names.
    private func getFixedKey(gamepad: GCExtendedGamepad, element: GCControllerElement) -> FixedKey? {
        if element === gamepad.buttonMenu {
            return .buttonMenu
        }
        if let opt = gamepad.buttonOptions, element === opt {
            return .buttonOptions
        }
        if #available(macOS 11.0, *) {
            if let home = gamepad.buttonHome, element === home {
                return .buttonHome
            }
        }
        if #available(macOS 11.3, *) {
            if let ds = gamepad as? GCDualSenseGamepad,
               element === ds.touchpadButton {
                return .touchpadButton
            }
        }
        if #available(macOS 11.0, *) {
            if let ds = gamepad as? GCDualShockGamepad,
               element === ds.touchpadButton {
                return .touchpadButton
            }
        }
        return nil
    }

    private func getValues(element: GCControllerElement, fixedKey: FixedKey? = nil) -> [(String, Float)] {
        if let element = element as? GCControllerButtonInput {
            var button: String = fixedKey?.rawValue ?? "Unknown button"
            if fixedKey == nil {
                if #available(macOS 11.0, *) {
                    if let name = element.sfSymbolsName {
                        button = name
                    }
                }
            }
            return [(button, element.value)]
        } else if let element = element as? GCControllerAxisInput {
            var axis: String = fixedKey?.rawValue ?? "Unknown axis"
            if fixedKey == nil {
                if #available(macOS 11.0, *) {
                    if let name = element.sfSymbolsName {
                        axis = name
                    }
                }
            }
            return [(axis, element.value)]
        } else if let element = element as? GCControllerDirectionPad {
            var directionPad: String = fixedKey?.rawValue ?? "Unknown direction pad"
            if fixedKey == nil {
                if #available(macOS 11.0, *) {
                    if let name = element.sfSymbolsName {
                        directionPad = name
                    }
                }
            }
            return [
                (maybeConcat(directionPad, "xAxis"), element.xAxis.value),
                (maybeConcat(directionPad, "yAxis"), element.yAxis.value)
            ]
        } else {
            return []
        }
    }
    
    private func getNameForElement(element: GCControllerElement) -> String? {
        if #available(macOS 11.0, *) {
            return element.sfSymbolsName
        } else {
            return nil
        }
    }

    private func getTimestamp(gamepad: GCExtendedGamepad) -> TimeInterval {
        if #available(macOS 11.0, *) {
            return gamepad.lastEventTimestamp
        } else {
            return Date().timeIntervalSince1970
        }
    }

    private func getName(gamepad: GCExtendedGamepad) -> String {
        if #available(macOS 11.0, *) {
            let device = gamepad.device
            return maybeConcat(device?.vendorName, device?.productCategory) ?? "Unknown device"
        } else {
            return "Unknown device"
        }
    }

    private func listGamepads() -> [[String: Any?]] {
        return gamepads.gamepads.enumerated().map { (index, gamepad) in
            [ "id": String(index), "name": getName(gamepad: gamepad) ]
        }
    }

    // MARK: - Rumble / Haptics

    private func handleRumble(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(macOS 11.0, *) else {
            result(false)
            return
        }
        guard let args = call.arguments as? [String: Any],
              let gamepadIdStr = args["gamepadId"] as? String,
              let gamepadId = Int(gamepadIdStr),
              gamepadId >= 0 && gamepadId < gamepads.gamepads.count else {
            result(false)
            return
        }
        let gamepad = gamepads.gamepads[gamepadId]
        guard let haptics = gamepad.controller?.haptics else {
            result(false)
            return
        }
        let weakMotor = (args["weakMotor"] as? Double) ?? 0.5
        let strongMotor = (args["strongMotor"] as? Double) ?? 0.5
        let durationMs = (args["durationMs"] as? Int) ?? 200

        // Play on both motors simultaneously
        for locality: GCHapticsLocality in [.leftHandle, .rightHandle] {
            guard let engine = try? haptics.createEngine(withLocality: locality) else { continue }
            let intensity: Float = locality == .leftHandle ? Float(strongMotor) : Float(weakMotor)
            let durationSec = Double(durationMs) / 1000.0
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ],
                relativeTime: 0,
                duration: durationSec
            )
            if let pattern = try? CHHapticPattern(events: [event], parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? engine.start()
                try? player.start(atTime: 0)
            }
        }
        result(true)
    }

    private func maybeConcat(_ string1: String?, _ string2: String) -> String {
        return maybeConcat(string1, string2)!
    }

    private func maybeConcat(_ strings: String?...) -> String? {
        let nonNull = strings.compactMap { $0 }
        if (nonNull.isEmpty) {
            return nil
        }
        return nonNull.joined(separator: " - ")
    }
    
    // MARK: - HID Listener for HOME button
    
    private func setupHIDListener() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("[gamepads_darwin] Failed to create HID manager")
            return
        }
        
        // Match gamepad devices (Usage Page: Generic Desktop, Usage: Game Pad or Joystick)
        let matchingDict: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
            ]
        ]
        
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDict as CFArray)
        
        // Register input report callback (for raw HID reports)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, reportId, report, reportLength in
            guard let context = context else { return }
            let plugin = Unmanaged<GamepadsDarwinPlugin>.fromOpaque(context).takeUnretainedValue()
            if let sender = sender {
                let device = unsafeBitCast(sender, to: IOHIDDevice.self)
                plugin.handleHIDReport(device: device, reportId: reportId, report: report, length: reportLength)
            }
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            print("[gamepads_darwin] HID manager opened successfully")
        } else {
            print("[gamepads_darwin] Failed to open HID manager: \(openResult)")
        }
    }
    
    private func handleHIDReport(device: IOHIDDevice, reportId: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // Switch Pro Controller 标准格式：
        // Byte 3: Y X B A SR SL R ZR (右侧按钮)
        // Byte 4: Minus Plus RStick LStick Home Capture - - (系统按钮)
        // Byte 5: Down Up Right Left SR SL L ZL (左侧按钮+方向键)
        if length >= 5 {
            let buttonByte2 = report[4]
            
            // HOME 键在 Byte 4 的 bit 4 (0x10)
            let homePressed = (buttonByte2 & 0x10) != 0
            
            if homePressed != lastHomeState {
                lastHomeState = homePressed
                print("[gamepads_darwin] ✅ HOME button: \(homePressed ? "PRESSED" : "RELEASED")")
                
                if let gamepadId = findGamepadIdForHIDDevice(device) {
                    let arguments: [String: Any] = [
                        "gamepadId": String(gamepadId),
                        "time": Int(Date().timeIntervalSince1970 * 1000),
                        "type": "button",
                        "key": "buttonHome",
                        "value": Float(homePressed ? 1 : 0),
                    ]
                    channel.invokeMethod("onGamepadEvent", arguments: arguments)
                }
            }
        }
    }
    
    private func findGamepadIdForHIDDevice(_ device: IOHIDDevice) -> Int? {
        // Simple heuristic - assumes first connected gamepad matches
        // In production, you'd want to match by vendor/product ID
        if !gamepads.gamepads.isEmpty {
            return 0
        }
        return nil
    }
    
    deinit {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}

extension Optional {
    func map<T>(_ closure: (Wrapped) -> T) -> T? {
        if let value = self {
            return closure(value)
        } else {
            return nil
        }
    }
}
