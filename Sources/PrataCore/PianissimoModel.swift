import Foundation

// Only model in the app; a namespace rather than a case, since there's nothing left to switch on.
public enum PianissimoModel {
    public static let displayName = "Pianissimo (Swedish)"

    static let requiredFileNames = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]

    public static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Prata", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("pianissimo-sv-coreml", isDirectory: true)
    }

    public static var isInstalled: Bool {
        hasRequiredFiles(at: directory)
    }

    public static func hasRequiredFiles(at directory: URL) -> Bool {
        requiredFileNames.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}
