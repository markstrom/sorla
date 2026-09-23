import AVFoundation
import ApplicationServices

public enum PermissionsManager {
    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func isMicrophoneAccessDenied() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .denied || status == .restricted
    }

    public static func microphoneAccess() -> MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    public static func promptAccessibilityIfNeeded() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
