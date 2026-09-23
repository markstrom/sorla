import Foundation

public enum LegacyModelMigration {
    // The app's folder name before the rename to Sorla; needed once to move an already downloaded model.
    static let legacyAppFolderName = "Prata"

    /// Moves the whole legacy models folder, with any swap leftovers and staging, when Sorla has none. Returns whether it moved.
    @discardableResult
    public static func migrate(applicationSupport: URL, fileManager: FileManager = .default) throws -> Bool {
        let legacyApp = applicationSupport.appendingPathComponent(legacyAppFolderName, isDirectory: true)
        let legacyModels = PianissimoModel.modelsDirectory(in: applicationSupport, appFolderName: legacyAppFolderName)
        let models = PianissimoModel.modelsDirectory(in: applicationSupport)

        guard !fileManager.fileExists(atPath: models.path), fileManager.fileExists(atPath: legacyModels.path) else {
            return false
        }
        try fileManager.createDirectory(at: models.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: legacyModels, to: models)
        removeIfEmpty(legacyApp, fileManager: fileManager)
        return true
    }

    private static func removeIfEmpty(_ directory: URL, fileManager: FileManager) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path), contents.isEmpty else { return }
        try? fileManager.removeItem(at: directory)
    }
}
