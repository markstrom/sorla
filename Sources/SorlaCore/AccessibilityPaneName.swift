import Foundation

// macOS 27 renamed System Settings' Accessibility privacy pane, so Sorla names it the way the running system does (#74).
public enum AccessibilityPaneName {
    // Tests pin a version; the app always reads the running system's.
    @TaskLocal public static var systemMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    public static var current: String { self.for(majorVersion: systemMajorVersion) }

    public static func `for`(majorVersion: Int) -> String {
        majorVersion >= 27
            ? String(localized: "Device Control and Data Access", bundle: Localization.bundle)
            : String(localized: "Accessibility", bundle: Localization.bundle)
    }
}
