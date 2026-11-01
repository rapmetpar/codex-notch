import Combine
import Foundation

/// One app-owned library and one event ledger, independent of individual SwiftUI mounts.
final class PetCompanionController: ObservableObject {
    static let shared = PetCompanionController()
    static let revisionKey = "petLibraryRevision.v1"
    @Published private(set) var library = PetLibrarySnapshot.empty
    @Published private(set) var atlas: PetSpriteAtlas?
    @Published private(set) var pose: PetCompanionPose = .idle
    @Published private(set) var isBusy = false
    @Published var hasError = false
    let sceneSession = PetCompanionSceneSession()
    private var policy = PetCompanionPolicy()
    private let store: PetLibraryStore
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.codexnotch.pet-library", qos: .utility)

    init(store: PetLibraryStore = PetLibraryStore(), defaults: UserDefaults = .standard, loadImmediately: Bool = true) {
        self.store = store
        self.defaults = defaults
        if loadImmediately { reload() }
    }

    var hasSelectedPet: Bool { library.selectedPet != nil && atlas != nil }

    func observe(activeSessions: [SessionActivity], completions: [CompletedSession], isHovered: Bool, now: Date) {
        policy.update(activeSessions: activeSessions, completions: completions, isHovered: isHovered, now: now)
        if pose != policy.pose { pose = policy.pose }
    }

    func reload() { perform { try $0.load() } }
    func select(_ id: String?) { perform { try $0.selectPet(id: id) } }
    func importLibrary(from url: URL) {
        perform { store in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return try store.importLibrary(from: url)
        }
    }

    private func perform(_ operation: @escaping (PetLibraryStore) throws -> PetLibrarySnapshot) {
        guard !isBusy else { return }
        isBusy = true
        hasError = false
        let store = self.store
        queue.async {
            let result = Result { () throws -> (PetLibrarySnapshot, PetSpriteAtlas?) in
                let library = try operation(store)
                let atlas = try library.selectedPet.map(PetCompanionAtlasAdapter.decode)
                return (library, atlas)
            }
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case let .success((library, atlas)):
                    let changed = self.library != library || (self.atlas != nil) != (atlas != nil)
                    self.library = library
                    self.atlas = atlas
                    // Existing runtime preference observation recalculates the fixed canvas once.
                    if changed {
                        self.defaults.set(self.defaults.integer(forKey: Self.revisionKey) &+ 1, forKey: Self.revisionKey)
                    }
                case .failure:
                    self.hasError = true
                }
            }
        }
    }
}

enum PetCompanionAtlasAdapter {
    static func decode(_ entry: PetCatalogEntry) throws -> PetSpriteAtlas {
        let metadata = entry.metadata
        let geometry = try PetSpriteGeometry(columns: metadata.columns, rows: metadata.rows,
            cellWidth: metadata.cellWidth, cellHeight: metadata.cellHeight)
        let states: [String: PetSpriteState] = [
            "idle": .idle, "running-right": .runRight, "running-left": .runLeft,
            "waving": .wave, "jumping": .jump, "failed": .failed,
            "waiting": .waiting, "running": .workRunning, "review": .review
        ]
        let clips = try metadata.clips.map { clip -> PetSpriteClip in
            guard let state = states[clip.state] else { throw PetSpriteError.invalidClip }
            return try PetSpriteClip(state: state, row: clip.row,
                columns: Array(clip.frameDurationsMilliseconds.indices),
                durations: clip.frameDurationsMilliseconds.map { Double($0) / 1000 })
        }
        return try PetSpriteAtlas(url: entry.atlasURL, geometry: geometry, clips: clips)
    }
}
