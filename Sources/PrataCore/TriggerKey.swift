import AppKit

public enum TriggerKey: String, CaseIterable, Sendable {
    case rightCommand
    case rightOption
    case rightControl
    case fn
    case customShortcut

    public static let `default` = TriggerKey.rightCommand

    public var keyCode: UInt16? {
        switch self {
        case .rightCommand: return 0x36
        case .rightOption: return 0x3D
        case .rightControl: return 0x3E
        case .fn: return 0x3F
        case .customShortcut: return nil
        }
    }

    public var deviceMask: UInt? {
        switch self {
        case .rightCommand: return 0x10
        case .rightOption: return 0x40
        case .rightControl: return 0x2000
        case .fn: return NSEvent.ModifierFlags.function.rawValue
        case .customShortcut: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        case .rightControl: return "Right ⌃"
        case .fn: return "Fn"
        case .customShortcut: return "Custom shortcut"
        }
    }
}

public enum RecordingMode: String, CaseIterable, Sendable {
    case pushToTalk
    case toggle

    public static let `default` = RecordingMode.pushToTalk

    public var displayName: String {
        switch self {
        case .pushToTalk: return "Push to talk"
        case .toggle: return "Toggle"
        }
    }
}
