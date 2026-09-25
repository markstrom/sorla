// Developer tool for #51: prints what macOS delivers for each key, so candidate dictation keys can be compared.
// Run with `swift Scripts/key-probe.swift`. Listen-only: it never changes, blocks or sends an event, and uses no network.
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)
let start = ProcessInfo.processInfo.systemUptime
let systemDefined = CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue))!

// Carbon kVK names for the keys worth telling apart here; anything else prints as a bare code.
let keyNames: [Int64: String] = [
    2: "D", 49: "Space", 53: "Esc", 54: "RightCmd", 55: "LeftCmd", 56: "LeftShift", 57: "CapsLock",
    58: "LeftOpt", 59: "LeftCtrl", 60: "RightShift", 61: "RightOpt", 62: "RightCtrl", 63: "Fn",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12",
]

let flagNames: [(CGEventFlags, String)] = [
    (.maskAlphaShift, "capsLock"), (.maskShift, "shift"), (.maskControl, "ctrl"), (.maskAlternate, "opt"),
    (.maskCommand, "cmd"), (.maskNumericPad, "numPad"), (.maskHelp, "help"), (.maskSecondaryFn, "fn"),
]

// NX_DEVICE* bits from IOKit's IOLLEvent.h: which physical modifier, left or right, is down.
let deviceBits: [(UInt64, String)] = [
    (0x0001, "lCtrl"), (0x0002, "lShift"), (0x0004, "rShift"), (0x0008, "lCmd"), (0x0010, "rCmd"),
    (0x0020, "lOpt"), (0x0040, "rOpt"), (0x0080, "capsStateless"), (0x2000, "rCtrl"),
]

// NX_KEYTYPE_* from IOKit's ev_keymap.h, sent in NX_SUBTYPE_AUX_CONTROL_BUTTONS events.
let nxKeyTypes = [
    "SOUND_UP", "SOUND_DOWN", "BRIGHTNESS_UP", "BRIGHTNESS_DOWN", "CAPS_LOCK", "HELP", "POWER_KEY", "MUTE",
    "UP_ARROW_KEY", "DOWN_ARROW_KEY", "NUM_LOCK", "CONTRAST_UP", "CONTRAST_DOWN", "LAUNCH_PANEL", "EJECT",
    "VIDMIRROR", "PLAY", "NEXT", "PREVIOUS", "FAST", "REWIND", "ILLUMINATION_UP", "ILLUMINATION_DOWN",
    "ILLUMINATION_TOGGLE",
]

func hex(_ value: some BinaryInteger, width: Int) -> String {
    let digits = String(value, radix: 16)
    return "0x" + String(repeating: "0", count: max(0, width - digits.count)) + digits
}

func describeFlags(_ flags: CGEventFlags) -> String {
    let named = flagNames.filter { flags.contains($0.0) }.map(\.1)
    let device = deviceBits.filter { flags.rawValue & $0.0 != 0 }.map(\.1)
    return "flags=\(hex(flags.rawValue, width: 8)) [\(named.joined(separator: ","))] dev=[\(device.joined(separator: ","))]"
}

func describeSystemDefined(_ event: CGEvent) -> String {
    guard let nsEvent = NSEvent(cgEvent: event) else { return "(not readable as NSEvent)" }
    let subtype = Int(nsEvent.subtype.rawValue)
    let data1 = nsEvent.data1
    var text = "subtype=\(subtype) data1=\(hex(UInt32(truncatingIfNeeded: data1), width: 8)) data2=\(hex(UInt32(truncatingIfNeeded: nsEvent.data2), width: 8))"
    // NX_SUBTYPE_AUX_CONTROL_BUTTONS: key type in the high 16 bits, then key state (0xA down, 0xB up) and a repeat bit.
    if subtype == 8 {
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0xFFFF
        let state = (keyFlags & 0xFF00) >> 8
        let name = keyType < nxKeyTypes.count ? "NX_KEYTYPE_\(nxKeyTypes[keyType])" : "unknown"
        let stateName = state == 0xA ? "down" : state == 0xB ? "up" : "state \(hex(state, width: 2))"
        text += " aux: keyType=\(keyType) (\(name)) \(stateName)\(keyFlags & 0x1 != 0 ? " repeat" : "")"
    } else if subtype == 7 {
        text += " (aux mouse buttons)"
    }
    return text
}

func describe(_ type: CGEventType, _ event: CGEvent) -> String {
    let time = String(format: "%8.3f", ProcessInfo.processInfo.systemUptime - start)
    let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
    let source = pid == 0 ? "" : " pid=\(pid)"
    switch type {
    case .keyDown, .keyUp, .flagsChanged:
        let name = type == .keyDown ? "keyDown" : type == .keyUp ? "keyUp" : "flagsChanged"
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let key = keyNames[code].map { "\(code) (\($0))" } ?? "\(code)"
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? " repeat" : ""
        let keyboard = event.getIntegerValueField(.keyboardEventKeyboardType)
        let padded = name.padding(toLength: 13, withPad: " ", startingAt: 0)
        return "\(time) \(padded) key=\(key.padding(toLength: 16, withPad: " ", startingAt: 0)) \(describeFlags(event.flags)) kbType=\(keyboard)\(isRepeat)\(source)"
    case systemDefined:
        return "\(time) systemDefined \(describeSystemDefined(event)) \(describeFlags(event.flags))\(source)"
    default:
        return "\(time) type=\(type.rawValue)"
    }
}

var tap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    // macOS switches off a tap that is slow or when secure input starts; switch it back on and say so.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        print("-- tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input"); re-enabling")
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    print(describe(type, event))
    return Unmanaged.passUnretained(event)
}

print("""
key-probe: prints every key, modifier and system-defined (media/aux) event macOS delivers. Quit with Ctrl+C.
Needs Input Monitoring (and, to be safe, Accessibility) for this terminal app in System Settings › Privacy & Security.
Secure Keyboard Entry (Terminal menu) or a focused password field hides key events from every tap.
Columns: seconds since start, event type, keycode (Carbon kVK), CGEventFlags with named bits, device-dependent
left/right modifier bits, keyboard type, repeat, and the sending pid when the event was posted by a process.

""")

let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, systemDefined]
    .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
guard let created = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: callback,
    userInfo: nil
) else {
    print("Could not create the event tap. Grant Input Monitoring to this terminal app, restart it, and run again.")
    print("Input Monitoring granted: \(CGPreflightListenEventAccess())")
    exit(1)
}
tap = created
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, created, 0), .commonModes)
CGEvent.tapEnable(tap: created, enable: true)
print("Listening… press the candidate keys now.")
CFRunLoopRun()
