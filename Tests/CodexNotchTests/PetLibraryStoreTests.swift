import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CodexNotch

final class PetLibraryStoreTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PetLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporary)
    }
    private var store: PetLibraryStore { PetLibraryStore(rootURL: temporary.appendingPathComponent("app-owned")) }

    func testBothVersionsImportAndSelectionSurvivesRestartAndSourceDeletion() throws {
        let package = try makePackage(versions: [1, 2])
        let imported = try store.importLibrary(from: package)
        XCTAssertNil(imported.selectedPetID, "Import must not opt users in")
        XCTAssertEqual(imported.entries.map(\.id), ["pet-0", "pet-1"])
        XCTAssertEqual(imported.entries.map { $0.metadata.rows }, [9, 11])
        XCTAssertEqual(imported.entries.map { $0.metadata.lookDirectionCount }, [0, 16])
        XCTAssertEqual(imported.entries[1].name, "Тест 1")
        let selected = try store.selectPet(id: "pet-1")
        try FileManager.default.removeItem(at: package)
        let restarted = PetLibraryStore(rootURL: store.rootURL)
        XCTAssertEqual(try restarted.load(), selected)
        XCTAssertNotNil(try restarted.load().selectedPet)
        XCTAssertTrue(try restarted.load().entries.allSatisfy { $0.atlasURL.path.hasPrefix(store.rootURL.path + "/") })
        XCTAssertNil(try restarted.selectPet(id: nil).selectedPet)
        XCTAssertNil(try PetLibraryStore(rootURL: store.rootURL).load().selectedPetID)
    }

    func testReimportPreservesStableSelectionAndRemovedIDTurnsOff() throws {
        let package = try makePackage(versions: [1, 2])
        _ = try store.importLibrary(from: package)
        _ = try store.selectPet(id: "pet-1")
        try editManifest(package) { value in
            var pets = value["pets"] as! [[String: Any]]
            pets.reverse()
            pets[0]["name"] = "Renamed"
            value["pets"] = pets
        }
        let replaced = try store.importLibrary(from: package)
        XCTAssertEqual(replaced.selectedPetID, "pet-1")
        XCTAssertEqual(replaced.selectedPet?.name, "Renamed")
        try editManifest(package) { value in
            value["pets"] = (value["pets"] as! [[String: Any]]).filter { $0["id"] as? String != "pet-1" }
        }
        XCTAssertNil(try store.importLibrary(from: package).selectedPetID)
        XCTAssertThrowsError(try store.selectPet(id: "unknown"))
        XCTAssertNil(try store.load().selectedPetID)
    }

    func testTraversalAbsoluteURLBackslashAndSymlinkImportsPreservePreviousLibrary() throws {
        let source = try makePackage()
        _ = try store.importLibrary(from: source)
        let previous = try store.selectPet(id: "pet-0")
        for path in ["../escape.png", "/tmp/file.png", "https://host/pet.png", "atlases\\pet.png", "atlases//pet.png", "atlases/./pet.png", "atlases/../pet.png", "atlases/%2e%2e/pet.png"] {
            try setPetField(source, key: "atlas", value: path)
            XCTAssertThrowsError(try store.importLibrary(from: source), path)
            XCTAssertEqual(try store.load(), previous)
        }
        try setPetField(source, key: "atlas", value: "atlases/pet-0.png")
        let atlas = source.appendingPathComponent("atlases/pet-0.png")
        let outside = temporary.appendingPathComponent("outside.png")
        try FileManager.default.moveItem(at: atlas, to: outside)
        try FileManager.default.createSymbolicLink(at: atlas, withDestinationURL: outside)
        XCTAssertThrowsError(try store.importLibrary(from: source))
        try FileManager.default.removeItem(at: atlas)
        try FileManager.default.moveItem(at: outside, to: atlas)
        let folder = source.appendingPathComponent("atlases")
        let externalFolder = temporary.appendingPathComponent("outside-folder")
        try FileManager.default.moveItem(at: folder, to: externalFolder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: externalFolder)
        XCTAssertThrowsError(try store.importLibrary(from: source))
        XCTAssertEqual(try store.load(), previous)
    }

    func testMalformedVersionsMetadataDuplicatesAndUnsafeIdentifiersAreRejected() throws {
        let package = try makePackage()
        let original = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["schemaVersion"] = 99 },
            { $0["pets"] = [] },
            { value in var pets = value["pets"] as! [[String: Any]]; pets.append(pets[0]); value["pets"] = pets },
            { value in var pets = value["pets"] as! [[String: Any]]; var copy = pets[0]; copy["id"] = "other"; pets.append(copy); value["pets"] = pets }
        ]
        for mutation in mutations {
            try original.write(to: package.appendingPathComponent("manifest.json"))
            try editManifest(package, mutation)
            XCTAssertThrowsError(try store.importLibrary(from: package))
        }
        for (key, bad) in [("id", "../bad"), ("id", ""), ("name", " \n"), ("name", "bad\u{0000}name"), ("id", String(repeating: "x", count: 129))] {
            try original.write(to: package.appendingPathComponent("manifest.json"))
            try setPetField(package, key: key, value: bad)
            XCTAssertThrowsError(try store.importLibrary(from: package))
        }
        try original.write(to: package.appendingPathComponent("manifest.json"))
        try editManifest(package) { value in
            let pet = (value["pets"] as! [[String: Any]])[0]
            value["pets"] = Array(repeating: pet, count: PetLibraryStore.maximumPets + 1)
        }
        XCTAssertThrowsError(try store.importLibrary(from: package))
        try original.write(to: package.appendingPathComponent("manifest.json"))
        try setPetField(package, key: "spriteVersion", value: 3)
        XCTAssertThrowsError(try store.importLibrary(from: package))
        try original.write(to: package.appendingPathComponent("manifest.json"))
        try editManifest(package) { value in
            var pets = value["pets"] as! [[String: Any]]
            var metadata = pets[0]["metadata"] as! [String: Any]
            var clips = metadata["clips"] as! [[String: Any]]
            clips[0]["frameDurationsMilliseconds"] = [1]
            metadata["clips"] = clips
            pets[0]["metadata"] = metadata
            value["pets"] = pets
        }
        XCTAssertThrowsError(try store.importLibrary(from: package))
        try Data("{ broken".utf8).write(to: package.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try store.importLibrary(from: package))
        XCTAssertEqual(try store.load(), .empty)
    }

    func testWrongDimensionsMIMETruncationAndOversizedFilesFailBeforeCommit() throws {
        let package = try makePackage()
        _ = try store.importLibrary(from: package)
        let previous = try store.selectPet(id: "pet-0")
        let atlas = package.appendingPathComponent("atlases/pet-0.png")
        let validPNG = try Data(contentsOf: atlas)
        let truncated = Data(validPNG.prefix(validPNG.count / 2))
        for invalid in [try png(width: 192, height: 208), Data("not png".utf8), Data([0x89, 0x50, 0x4e, 0x47]), truncated] {
            try invalid.write(to: atlas)
            XCTAssertThrowsError(try store.importLibrary(from: package))
            XCTAssertEqual(try store.load(), previous)
        }
        let mismatched = package.appendingPathComponent("atlases/pet-0.webp")
        try png(width: 1536, height: 1872).write(to: mismatched)
        try setPetField(package, key: "atlas", value: "atlases/pet-0.webp")
        XCTAssertThrowsError(try store.importLibrary(from: package), "Extension must match encoded MIME")
        try setPetField(package, key: "atlas", value: "atlases/pet-0.png")
        try Data([0]).write(to: atlas)
        let file = try FileHandle(forWritingTo: atlas)
        try file.truncate(atOffset: UInt64(PetLibraryStore.maximumAtlasBytes + 1))
        try file.close()
        XCTAssertThrowsError(try store.importLibrary(from: package))
        try Data(count: PetLibraryStore.maximumManifestBytes + 1).write(to: package.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try store.importLibrary(from: package))
        XCTAssertEqual(try store.load(), previous)
    }

    func testCorruptLocalStateAndSymlinkCannotEscapeAppOwnedRoot() throws {
        let package = try makePackage()
        _ = try store.importLibrary(from: package)
        let state = store.rootURL.appendingPathComponent("state.json")
        try Data(#"{"schemaVersion":1,"generation":"../escape","selectedPetID":null}"#.utf8).write(to: state)
        XCTAssertThrowsError(try store.load())
        let target = temporary.appendingPathComponent("private-state")
        try Data("secret".utf8).write(to: target)
        try FileManager.default.removeItem(at: state)
        try FileManager.default.createSymbolicLink(at: state, withDestinationURL: target)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.importLibrary(from: package))
        XCTAssertEqual(try String(contentsOf: target), "secret")
    }

    func testUnknownSourceFieldsAndUnlistedFilesAreNotCopied() throws {
        let package = try makePackage()
        try editManifest(package) { $0["transportURL"] = "private-transport-placeholder" }
        try Data("private".utf8).write(to: package.appendingPathComponent("unlisted.txt"))
        let imported = try store.importLibrary(from: package)
        let generation = try XCTUnwrap(imported.entries.first).atlasURL.deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: generation.appendingPathComponent("unlisted.txt").path))
        let stored = try String(contentsOf: generation.appendingPathComponent("manifest.json"))
        XCTAssertFalse(stored.contains("transportURL"))
        XCTAssertFalse(stored.contains("private-transport-placeholder"))
    }

    /// Opt-in QA of an explicitly supplied personal package. Never reads a user's collection or auth.
    func testExplicitExternalPackageIfRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_NOTCH_TEST_PET_PACKAGE"] else {
            throw XCTSkip("Set CODEX_NOTCH_TEST_PET_PACKAGE to validate an explicitly exported package")
        }
        let result = try store.importLibrary(from: URL(fileURLWithPath: path))
        XCTAssertFalse(result.entries.isEmpty)
        XCTAssertNil(result.selectedPetID)
        for entry in result.entries {
            XCTAssertNotNil(CGImageSourceCreateWithURL(entry.atlasURL as CFURL, nil))
            XCTAssertEqual(try store.selectPet(id: entry.id).selectedPetID, entry.id)
        }
        XCTAssertEqual(try PetLibraryStore(rootURL: store.rootURL).load().entries, result.entries)
    }

    private func makePackage(versions: [Int] = [1]) throws -> URL {
        let root = temporary.appendingPathComponent("input-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("atlases"), withIntermediateDirectories: true)
        var pets: [PetLibraryManifest.Pet] = []
        for (index, version) in versions.enumerated() {
            let metadata = try PetAtlasMetadata.standard(spriteVersion: version)
            let atlas = "atlases/pet-\(index).png"
            try png(width: metadata.columns * metadata.cellWidth, height: metadata.rows * metadata.cellHeight)
                .write(to: root.appendingPathComponent(atlas))
            pets.append(.init(id: "pet-\(index)", name: "Тест \(index)", atlas: atlas, spriteVersion: version, metadata: metadata))
        }
        try JSONEncoder().encode(PetLibraryManifest(schemaVersion: 1, pets: pets))
            .write(to: root.appendingPathComponent("manifest.json"))
        return root
    }

    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 20, y: 20, width: 24, height: 24))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func editManifest(_ root: URL, _ body: (inout [String: Any]) -> Void) throws {
        let url = root.appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        body(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private func setPetField(_ root: URL, key: String, value: Any) throws {
        try editManifest(root) { object in
            var pets = object["pets"] as! [[String: Any]]
            pets[0][key] = value
            object["pets"] = pets
        }
    }
}
