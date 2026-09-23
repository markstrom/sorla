import AVFoundation
import ApplicationServices

public enum PermissionsManager {
    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func promptAccessibilityIfNeeded() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
