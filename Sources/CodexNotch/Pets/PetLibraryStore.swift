import Darwin
import Foundation
import ImageIO

/// Portable atlas description; artwork and account inventory are never bundled in source.
struct PetAnimationClipMetadata: Codable, Equatable, Sendable {
    let state: String
    let row: Int
    let frameDurationsMilliseconds: [Int]
}

struct PetAtlasMetadata: Codable, Equatable, Sendable {
    let columns: Int
    let rows: Int
    let cellWidth: Int
    let cellHeight: Int
    let clips: [PetAnimationClipMetadata]
    let lookDirectionCount: Int

    static func standard(spriteVersion: Int) throws -> Self {
        guard spriteVersion == 1 || spriteVersion == 2 else { throw PetLibraryError.unsupportedFormat }
        let states = ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"]
        let timings = [
            [280, 110, 110, 140, 140, 320],
            [120, 120, 120, 120, 120, 120, 120, 220],
            [120, 120, 120, 120, 120, 120, 120, 220],
            [140, 140, 140, 280], [140, 140, 140, 140, 280],
            [140, 140, 140, 140, 140, 140, 140, 240],
            [150, 150, 150, 150, 150, 260],
            [120, 120, 120, 120, 120, 220],
            [150, 150, 150, 150, 150, 280]
        ]
        return Self(columns: 8, rows: spriteVersion == 1 ? 9 : 11, cellWidth: 192, cellHeight: 208,
                    clips: states.enumerated().map {
                        PetAnimationClipMetadata(state: $0.element, row: $0.offset,
                                                 frameDurationsMilliseconds: timings[$0.offset])
                    }, lookDirectionCount: spriteVersion == 1 ? 0 : 16)
    }
}

struct PetCatalogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let atlasURL: URL
    let spriteVersion: Int
    let metadata: PetAtlasMetadata
}

struct PetLibrarySnapshot: Equatable, Sendable {
    let entries: [PetCatalogEntry]
    let selectedPetID: String?
    var selectedPet: PetCatalogEntry? { entries.first { $0.id == selectedPetID } }
    static let empty = Self(entries: [], selectedPetID: nil)
}

struct PetLibraryManifest: Codable, Equatable, Sendable {
    struct Pet: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let atlas: String
        let spriteVersion: Int
        let metadata: PetAtlasMetadata
    }
    let schemaVersion: Int
    let pets: [Pet]
}

enum PetLibraryError: Error, Equatable {
    case unsupportedFormat
    case invalidManifest
    case unsafePath
    case duplicateIdentifier
    case resourceLimit
    case invalidImage
    case unknownPet
    case invalidState
}

/// Synchronous local I/O. The UI owns serialization/refresh and may invoke imports on a utility queue.
/// A whole package is committed by one atomic state-file write; a failed import never changes selection.
struct PetLibraryStore {
    static let maximumManifestBytes = 256 * 1024
    static let maximumAtlasBytes = 20 * 1024 * 1024
    static let maximumTotalBytes = 128 * 1024 * 1024
    static let maximumPets = 64
    static var defaultRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexNotch/PetLibrary", isDirectory: true)
    }
    let rootURL: URL

    init(rootURL: URL = Self.defaultRootURL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    private struct State: Codable {
        let schemaVersion: Int
        let generation: String
        let selectedPetID: String?
    }

    func load() throws -> PetLibrarySnapshot {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return .empty }
        let root = try SafePetDirectory(url: rootURL)
        guard try root.hasFile("state.json") else { return .empty }
        let state = try decodeState(root.read("state.json", limit: 4096))
        let directory = try SafePetDirectory(url: rootURL.appendingPathComponent(state.generation))
        let package = try readPackage(directory)
        guard state.selectedPetID == nil || package.manifest.pets.contains(where: { $0.id == state.selectedPetID }) else {
            throw PetLibraryError.invalidState
        }
        return snapshot(package.manifest, generation: state.generation, selectedID: state.selectedPetID)
    }

    @discardableResult
    func importLibrary(from directoryURL: URL) throws -> PetLibrarySnapshot {
        guard directoryURL.isFileURL else { throw PetLibraryError.unsafePath }
        let package = try readPackage(SafePetDirectory(url: directoryURL))
        let previous = try load()
        let preservedID = previous.selectedPetID.flatMap { id in
            package.manifest.pets.contains(where: { $0.id == id }) ? id : nil
        }
        let manager = FileManager.default
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        // Refuse a symlink root/state even when the import itself is valid.
        let root = try SafePetDirectory(url: rootURL)
        if try root.hasFile("state.json") { _ = try decodeState(root.read("state.json", limit: 4096)) }
        let generation = UUID().uuidString
        let destination = rootURL.appendingPathComponent(generation, isDirectory: true)
        try manager.createDirectory(at: destination, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        var committed = false
        defer { if !committed { try? manager.removeItem(at: destination) } }
        for (path, data) in package.resources {
            let target = destination.appendingPathComponent(path)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try data.write(to: target, options: .atomic)
        }
        // Re-encode known metadata only; unknown source keys (including transport URLs) are discarded.
        try encoder.encode(package.manifest).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
        try writeState(State(schemaVersion: 1, generation: generation, selectedPetID: preservedID))
        committed = true
        // Old immutable generations are retained for any renderer still using their URLs.
        return snapshot(package.manifest, generation: generation, selectedID: preservedID)
    }

    @discardableResult
    func selectPet(id: String?) throws -> PetLibrarySnapshot {
        let current = try load()
        guard id == nil || current.entries.contains(where: { $0.id == id }) else { throw PetLibraryError.unknownPet }
        guard !current.entries.isEmpty else { return .empty }
        let root = try SafePetDirectory(url: rootURL)
        let state = try decodeState(root.read("state.json", limit: 4096))
        try writeState(State(schemaVersion: 1, generation: state.generation, selectedPetID: id))
        return PetLibrarySnapshot(entries: current.entries, selectedPetID: id)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func writeState(_ state: State) throws {
        try encoder.encode(state).write(to: rootURL.appendingPathComponent("state.json"), options: .atomic)
    }

    private func decodeState(_ data: Data) throws -> State {
        guard let state = try? JSONDecoder().decode(State.self, from: data), state.schemaVersion == 1,
              UUID(uuidString: state.generation)?.uuidString == state.generation else { throw PetLibraryError.invalidState }
        return state
    }

    private func snapshot(_ manifest: PetLibraryManifest, generation: String, selectedID: String?) -> PetLibrarySnapshot {
        PetLibrarySnapshot(entries: manifest.pets.map {
            PetCatalogEntry(id: $0.id, name: $0.name,
                            atlasURL: rootURL.appendingPathComponent(generation).appendingPathComponent($0.atlas),
                            spriteVersion: $0.spriteVersion, metadata: $0.metadata)
        }, selectedPetID: selectedID)
    }

    private func readPackage(_ directory: SafePetDirectory) throws -> (manifest: PetLibraryManifest, resources: [(String, Data)]) {
        let encoded = try directory.read("manifest.json", limit: Self.maximumManifestBytes)
        guard let manifest = try? JSONDecoder().decode(PetLibraryManifest.self, from: encoded),
              manifest.schemaVersion == 1, !manifest.pets.isEmpty,
              manifest.pets.count <= Self.maximumPets else { throw PetLibraryError.invalidManifest }
        var ids = Set<String>()
        var paths = Set<String>()
        var total = 0
        var resources: [(String, Data)] = []
        for pet in manifest.pets {
            guard (1...128).contains(pet.id.utf8.count),
                  pet.id.utf8.allSatisfy({ Self.identifierBytes.contains($0) }),
                  (1...128).contains(pet.name.count), pet.name.utf8.count <= 512,
                  !pet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !pet.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  pet.metadata == (try PetAtlasMetadata.standard(spriteVersion: pet.spriteVersion)) else {
                throw PetLibraryError.invalidManifest
            }
            guard ids.insert(pet.id).inserted, paths.insert(pet.atlas.lowercased()).inserted else {
                throw PetLibraryError.duplicateIdentifier
            }
            try SafePetDirectory.validate(path: pet.atlas)
            let ext = URL(fileURLWithPath: pet.atlas).pathExtension.lowercased()
            guard ext == "png" || ext == "webp" else { throw PetLibraryError.unsupportedFormat }
            let data = try directory.read(pet.atlas, limit: Self.maximumAtlasBytes)
            total += data.count
            guard total <= Self.maximumTotalBytes else { throw PetLibraryError.resourceLimit }
            try validateImage(data, fileExtension: ext, metadata: pet.metadata)
            resources.append((pet.atlas, data))
        }
        return (manifest, resources)
    }

    private static let identifierBytes = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".utf8)

    private func validateImage(_ data: Data, fileExtension ext: String, metadata: PetAtlasMetadata) throws {
        guard PetAtlasContainer.isComplete(data, fileExtension: ext) else { throw PetLibraryError.invalidImage }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let type = CGImageSourceGetType(source) as String?,
              (ext == "png" && type == "public.png") || (ext == "webp" && type == "org.webmproject.webp"),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == metadata.columns * metadata.cellWidth, height == metadata.rows * metadata.cellHeight,
              let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == width, image.height == height,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw PetLibraryError.invalidImage }
    }
}

/// Descriptor-relative reads reject links in EVERY path component, traversal, special files and
/// oversized files before allocation. Read from the opened inode so replacing the source path
/// after validation cannot cause a later copy to follow a symlink.
private final class SafePetDirectory {
    private let descriptor: Int32
    init(url: URL) throws {
        guard url.isFileURL else { throw PetLibraryError.unsafePath }
        descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw PetLibraryError.unsafePath }
    }
    deinit { close(descriptor) }

    static func validate(path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.".utf8)
        guard !path.isEmpty, path.utf8.count <= 512, parts.count <= 8,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.allSatisfy(allowed.contains) }) else {
            throw PetLibraryError.unsafePath
        }
    }

    func hasFile(_ path: String) throws -> Bool {
        var info = stat()
        if fstatat(descriptor, path, &info, AT_SYMLINK_NOFOLLOW) == -1 {
            if errno == ENOENT { return false }
            throw PetLibraryError.unsafePath
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw PetLibraryError.unsafePath }
        return true
    }

    func read(_ path: String, limit: Int) throws -> Data {
        try Self.validate(path: path)
        let parts = path.split(separator: "/").map(String.init)
        var parent = dup(descriptor)
        guard parent >= 0 else { throw PetLibraryError.unsafePath }
        defer { close(parent) }
        for part in parts.dropLast() {
            let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw PetLibraryError.unsafePath }
            close(parent)
            parent = next
        }
        let file = openat(parent, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw PetLibraryError.unsafePath }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw PetLibraryError.unsafePath }
        guard info.st_size > 0, info.st_size <= limit else { throw PetLibraryError.resourceLimit }
        var result = Data()
        while result.count <= limit {
            guard let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - result.count)), !chunk.isEmpty else { break }
            result.append(chunk)
        }
        guard result.count <= limit else { throw PetLibraryError.resourceLimit }
        return result
    }
}

/// ImageIO deliberately tolerates partial images. Check encoded container completion first so
/// a truncated PNG/WebP cannot replace the previous working generation with recovered pixels.
private enum PetAtlasContainer {
    static func isComplete(_ data: Data, fileExtension: String) -> Bool {
        let bytes = [UInt8](data)
        if fileExtension == "png" { return completePNG(bytes) }
        return completeWebP(bytes)
    }

    private static func integer(_ bytes: [UInt8], at index: Int, littleEndian: Bool = false) -> Int {
        let shifts = littleEndian ? [0, 8, 16, 24] : [24, 16, 8, 0]
        return (0..<4).reduce(0) { $0 | (Int(bytes[index + $1]) << shifts[$1]) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        return crc
    }

    private static func completePNG(_ bytes: [UInt8]) -> Bool {
        guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { return false }
        var offset = 8
        var hasPixels = false
        while offset + 12 <= bytes.count {
            let count = integer(bytes, at: offset)
            guard count <= bytes.count - offset - 12 else { return false }
            let kind = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)
            if offset == 8 && (kind != "IHDR" || count != 13) { return false }
            if offset != 8 && kind == "IHDR" { return false }
            if kind == "acTL" { return false } // Animated containers are not sprite atlases.
            var crc: UInt32 = 0xffffffff
            for byte in bytes[(offset + 4)..<(offset + 8 + count)] {
                crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 255)]
            }
            guard Int(crc ^ 0xffffffff) == integer(bytes, at: offset + 8 + count) else { return false }
            if kind == "IDAT" { hasPixels = true }
            offset += count + 12
            if kind == "IEND" { return count == 0 && hasPixels && offset == bytes.count }
        }
        return false
    }

    private static func completeWebP(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 12, bytes[0..<4].elementsEqual("RIFF".utf8),
              bytes[8..<12].elementsEqual("WEBP".utf8),
              integer(bytes, at: 4, littleEndian: true) == bytes.count - 8 else { return false }
        var offset = 12
        var hasPixels = false
        while offset + 8 <= bytes.count {
            let kind = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
            let count = integer(bytes, at: offset + 4, littleEndian: true)
            guard count <= bytes.count - offset - 8 else { return false }
            if kind == "ANIM" || kind == "ANMF" { return false }
            if kind == "VP8 " || kind == "VP8L" { hasPixels = true }
            offset += 8 + count + count % 2
        }
        return hasPixels && offset == bytes.count
    }
}
