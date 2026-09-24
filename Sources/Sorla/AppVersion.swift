import Foundation

enum AppVersion {
    static var short: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
