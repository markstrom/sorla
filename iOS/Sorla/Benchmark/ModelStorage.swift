import Foundation

enum ModelStorage {
    static var modelsDirectory: URL { PianissimoModel.modelsDirectory }
    static var installedDirectory: URL { PianissimoModel.directory }

    static var stagingRoot: URL {
        modelsDirectory.appendingPathComponent(ModelStaging.rootName, isDirectory: true)
    }

    // The model can be downloaded again, so it stays out of iCloud and device backups.
    static func excludeFromBackup() {
        var directory = PianissimoModel.applicationSupportDirectory.appendingPathComponent("Sorla", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    struct InstalledModel: Equatable, Sendable {
        var version: String
        var sourceRepository: String?
        var sourceRevision: String?
    }

    // Reads the manifest copied next to the compiled model at install time.
    static func installedModel() -> InstalledModel? {
        struct Manifest: Decodable {
            struct Source: Decodable { let repo: String?; let revision: String? }
            struct Model: Decodable { let id: String?; let version: String; let source: Source? }
            let models: [Model]
        }
        let url = installedDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let model = manifest.models.first(where: { $0.id == ModelManifest.pianissimoID }) ?? manifest.models.first
        else { return nil }
        return InstalledModel(version: model.version, sourceRepository: model.source?.repo, sourceRevision: model.source?.revision)
    }
}
