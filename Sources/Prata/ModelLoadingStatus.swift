import Combine

@MainActor
final class ModelLoadingStatus: ObservableObject {
    @Published var isModelReady = false
}
