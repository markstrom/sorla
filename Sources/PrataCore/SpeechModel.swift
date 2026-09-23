import Foundation

public enum SpeechModel: String, CaseIterable, Sendable {
    case parakeet
    case pianissimo

    public static let requiredPianissimoFileNames = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]

    public var displayName: String {
        switch self {
        case .parakeet: return "Parakeet v3 (multilingual)"
        case .pianissimo: return "Pianissimo (Swedish)"
        }
    }

    public var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Prata", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("pianissimo-sv-coreml", isDirectory: true)
    }

    public var isInstalled: Bool {
        switch self {
        case .parakeet: return true
        case .pianissimo: return Self.hasRequiredFiles(at: directory)
        }
    }

    public static func hasRequiredFiles(at directory: URL) -> Bool {
        requiredPianissimoFileNames.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}
