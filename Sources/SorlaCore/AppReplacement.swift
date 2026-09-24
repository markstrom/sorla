import Foundation

// What a file on disk is right now; a new copy of the app gets a new inode or date even at the same path.
public struct FileIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let size: UInt64
    public let modificationDate: Date?

    public init(device: UInt64, inode: UInt64, size: UInt64, modificationDate: Date?) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modificationDate = modificationDate
    }
}

public protocol FileIdentityProviding {
    func identity(of url: URL) -> FileIdentity?
}

public struct SystemFileIdentityProvider: FileIdentityProviding {
    public init() {}

    public func identity(of url: URL) -> FileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else { return nil }
        return FileIdentity(
            device: device,
            inode: inode,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date
        )
    }
}

// macOS checks Accessibility against the app on disk, so once Sorla.app is replaced its ⌘V is silently dropped.
public struct AppReplacementCheck {
    private let executableURL: URL?
    private let provider: FileIdentityProviding
    private let atLaunch: FileIdentity?
    public private(set) var isReplaced = false

    public init(executableURL: URL?, provider: FileIdentityProviding = SystemFileIdentityProvider()) {
        self.executableURL = executableURL
        self.provider = provider
        self.atLaunch = executableURL.flatMap { provider.identity(of: $0) }
    }

    // One stat when asked, never on a timer. A missing file has no new copy to restart into, so it doesn't count.
    @discardableResult
    public mutating func check() -> Bool {
        guard !isReplaced, let executableURL, let atLaunch,
              let current = provider.identity(of: executableURL)
        else { return isReplaced }
        isReplaced = current != atLaunch
        return isReplaced
    }
}

public enum AppRelaunch {
    // Quitting can take a while mid-transcription, and giving up leaves no Sorla running at all.
    public static let exitTimeout: TimeInterval = 30

    // A translocated copy runs from a temporary mount that is gone once Sorla quits, so there is nothing to reopen.
    public static func canReopen(_ bundleURL: URL) -> Bool {
        !bundleURL.path.contains("/AppTranslocation/")
    }

    // Waits for this process to be gone before opening the new copy, so two Sorlas never run at once.
    static let script = """
        i=0
        while kill -0 "$1" 2>/dev/null; do
          i=$((i + 1))
          [ "$i" -gt "$3" ] && exit 1
          sleep 0.1
        done
        exec "$4" "$2"
        """

    // The pid and path go in as arguments, never into the script text, so any path is safe.
    public static func arguments(
        waitingFor pid: Int32,
        thenOpen bundleURL: URL,
        timeout: TimeInterval = exitTimeout,
        opener: String = "/usr/bin/open"
    ) -> [String] {
        ["-c", script, "sorla-relaunch", String(pid), bundleURL.path, String(Int(timeout * 10)), opener]
    }

    public static let shell = URL(fileURLWithPath: "/bin/sh")
}
