import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", initial: .init(.space, modifiers: [.option]))
}

@MainActor
public final class HotkeyController {
    public init(onStart: @escaping @MainActor () -> Void, onStop: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) {
            MainActor.assumeIsolated {
                onStart()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) {
            MainActor.assumeIsolated {
                onStop()
            }
        }
    }
}
