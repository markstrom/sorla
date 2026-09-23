import Foundation

public enum LegacyModelMigration {
    // The app's folder name before the rename to Sorla; needed once to move an already downloaded model.
    static let legacyAppFolderName = "Prata"

    /// Moves the model from the legacy folder when the new location has none. Returns whether it moved.
    @discardableResult
    public static func migrate(applicationSupport: URL, fileManager: FileManager = .default) throws -> Bool {
        let legacyApp = applicationSupport.appendingPathComponent(legacyAppFolderName, isDirectory: true)
        let legacyModels = PianissimoModel.modelsDirectory(in: applicationSupport, appFolderName: legacyAppFolderName)
        let legacyModel = legacyModels.appendingPathComponent(PianissimoModel.directoryName, isDirectory: true)
        let models = PianissimoModel.modelsDirectory(in: applicationSupport)
        let model = models.appendingPathComponent(PianissimoModel.directoryName, isDirectory: true)

        guard !fileManager.fileExists(atPath: model.path), fileManager.fileExists(atPath: legacyModel.path) else {
            return false
        }
        try fileManager.createDirectory(at: models, withIntermediateDirectories: true)
        try fileManager.moveItem(at: legacyModel, to: model)
        removeIfEmpty(legacyModels, fileManager: fileManager)
        removeIfEmpty(legacyApp, fileManager: fileManager)
        return true
    }

    private static func removeIfEmpty(_ directory: URL, fileManager: FileManager) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path), contents.isEmpty else { return }
        try? fileManager.removeItem(at: directory)
    }
}
