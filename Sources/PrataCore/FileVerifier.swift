import CryptoKit
import Foundation

public enum FileVerifier {
    private static let chunkSize = 1_048_576

    public static func matches(_ url: URL, size: Int64, sha256: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let actualSize = attributes[.size] as? NSNumber,
              actualSize.int64Value == size
        else { return false }
        return (try? Self.sha256(of: url)) == sha256
    }

    // Streams in chunks so the 650 MB encoder weights never sit in memory at once.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: chunkSize) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
