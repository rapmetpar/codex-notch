#!/usr/bin/env python3
"""Preference upgrade/relocation guard. Only UUID-scoped synthetic domains.

Compiles production AppPreferences and PetLibraryStore into a fixture executable,
never launches the real app/runtime, changes HOME or opens a real user domain.
The legacy branch models the pre-fix implicit UserDefaults.standard behavior.
"""
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
SOURCE = r'''
import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
let mode = CommandLine.arguments[1]
let domain = CommandLine.arguments[2]
precondition(domain.hasPrefix("CodexNotch.synthetic.upgrade."))
let suite = AppPreferences.makeStore(domain: domain)
// Every process gets the SAME injected temporary app-owned root, outside all
// fixture bundles. Never resolve the real PetLibraryStore.defaultRootURL.
let rootURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true)
let expectedAtlasHash = CommandLine.arguments[5]
let library = PetLibraryStore(rootURL: rootURL)
let petID = "synthetic-upgrade-pet"
let metadata = try PetAtlasMetadata.standard(spriteVersion: 2)

let expected: [String: Any] = [
    "appLanguage": "ru", "recentConversationLimit": 20,
    "conversationCategoryOrder.v1": "viewed,unread,running",
    "animationsEnabled": false, "notchDisplayEnabled": false,
    "quotaDisplayStyle": "waveBall", "statusIconStyle": "custom",
    "customQuotaColorEnabled": true, "customQuotaColorHex": "#123456",
    "floatingCenterStyle": "pet", "floatingCenterText": "hello  ",
    // Valid project keys: opaque namespace plus 64 lowercase hexadecimal digits.
    "conversationProjectOrder.v1": ["native:" + String(repeating: "a", count: 64),
                                     "cwd:" + String(repeating: "b", count: 64), "unassigned"],
    "customStatusIconPNG": Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==")!,
    "futureFixture.v1": "preserve unknown keys"
]
func matches(_ defaults: UserDefaults) -> Bool {
    expected.allSatisfy { key, value in
        guard let stored = defaults.object(forKey: key) else { return false }
        return (stored as AnyObject).isEqual(value)
    }
}
func syntheticAtlas() throws -> Data {
    let width = metadata.columns * metadata.cellWidth
    let height = metadata.rows * metadata.cellHeight
    let context = CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
    for row in 0..<metadata.rows {
        for column in 0..<metadata.columns {
            context.fill(CGRect(x: column * metadata.cellWidth + 48,
                                y: row * metadata.cellHeight + 48, width: 48, height: 48))
        }
    }
    let result = NSMutableData()
    let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return result as Data
}
func checkLibrary(selected: Bool = true) throws {
    precondition(!FileManager.default.fileExists(atPath: sourceURL.path), "Import source must be deleted")
    let snapshot = try library.load()
    precondition(snapshot.entries.count == 1)
    precondition(snapshot.selectedPetID == (selected ? petID : nil))
    precondition(snapshot.selectedPet?.id == (selected ? petID : nil))
    let entry = snapshot.entries[0]
    precondition(entry.id == petID && entry.name == "Synthetic upgrade pet")
    precondition(entry.spriteVersion == 2 && entry.metadata == metadata)
    precondition(entry.atlasURL.path.hasPrefix(rootURL.path + "/"))
    let pixels = try Data(contentsOf: entry.atlasURL)
    let digest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
    precondition(!expectedAtlasHash.isEmpty && digest == expectedAtlasHash, "Owned atlas bytes changed")
    // load() validates the real generation/manifest/container/decode. Also prove
    // the chosen resource still exists at its app-owned location after moving app.
    precondition(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("state.json").path))
}
switch mode {
case "import-pet":
    let initial = try library.load()
    precondition(initial == .empty)
    try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
    let atlasName = "synthetic.png"
    try syntheticAtlas().write(to: sourceURL.appendingPathComponent(atlasName))
    let manifest = PetLibraryManifest(schemaVersion: 1, pets: [
        .init(id: petID, name: "Synthetic upgrade pet", atlas: atlasName,
              spriteVersion: 2, metadata: metadata)
    ])
    try JSONEncoder().encode(manifest).write(to: sourceURL.appendingPathComponent("manifest.json"))
    let imported = try library.importLibrary(from: sourceURL)
    precondition(imported.entries.count == 1 && imported.selectedPetID == nil)
    let selected = try library.selectPet(id: petID)
    precondition(selected.selectedPetID == petID)
case "read-pet":
    try checkLibrary()
case "reject-unknown-pet":
    do {
        _ = try library.selectPet(id: "not-in-library")
        fatalError("Unknown selection must be rejected")
    } catch PetLibraryError.unknownPet { }
    try checkLibrary()
case "pet-off":
    _ = try library.selectPet(id: nil)
    try checkLibrary(selected: false)
case "read-pet-off":
    try checkLibrary(selected: false)
case "legacy-write":
    precondition(Bundle.main.bundleIdentifier == domain)
    expected.forEach { UserDefaults.standard.set($0.value, forKey: $0.key) }
    // Only the process test synchronizes to establish its cross-process barrier.
    precondition(UserDefaults.standard.synchronize())
case "legacy-read":
    exit(matches(UserDefaults.standard) ? 0 : 3)
case "read":
    exit(matches(suite) ? 0 : 3)
case "write-zero":
    suite.set(0, forKey: "recentConversationLimit")
    precondition(suite.synchronize())
case "read-zero":
    precondition(suite.object(forKey: "recentConversationLimit") != nil)
    precondition(suite.integer(forKey: "recentConversationLimit") == 0)
    precondition(suite.string(forKey: "appLanguage") == "ru")
case "clean":
    suite.removePersistentDomain(forName: domain)
    precondition(suite.synchronize())
case "read-reset":
    precondition(expected.keys.allSatisfy { suite.object(forKey: $0) == nil })
default: fatalError("Unknown fixture command")
}
'''


def run(executable, mode, domain, library_root, import_source, atlas_hash, expected=0):
    result = subprocess.run([str(executable), mode, domain, str(library_root),
                             str(import_source), atlas_hash], capture_output=True, text=True)
    if result.returncode != expected:
        raise RuntimeError(f"synthetic preference guard {mode} failed ({result.returncode}): {result.stderr}")


def main():
    domain = "CodexNotch.synthetic.upgrade." + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="codex-notch-preferences-") as scratch:
        scratch = Path(scratch)
        helper = scratch / "main.swift"
        helper.write_text(SOURCE)
        binary = scratch / ("SyntheticPreferenceProbe-" + uuid.uuid4().hex)
        subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(scratch / "ModuleCache"),
                        str(ROOT / "Sources/CodexNotch/State/AppPreferences.swift"),
                        str(ROOT / "Sources/CodexNotch/Pets/PetLibraryStore.swift"), str(helper),
                        "-o", str(binary)], check=True, text=True)

        def package(path, generation):
            macos = path / "Contents/MacOS"
            macos.mkdir(parents=True)
            shutil.copy2(binary, macos / "SyntheticPreferenceProbe")
            (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": domain, "CFBundleExecutable": "SyntheticPreferenceProbe",
                "CFBundlePackageType": "APPL", "CFBundleVersion": str(generation),
                "CFBundleShortVersionString": f"1.{generation}",
            }))
            return macos / "SyntheticPreferenceProbe"

        library_root = scratch / "Application Support/CodexNotch/PetLibrary"
        import_source = scratch / "synthetic-pet-import"
        atlas_hash = ""

        def invoke(executable, mode, expected=0):
            run(executable, mode, domain, library_root, import_source, atlas_hash, expected)

        try:
            installed = scratch / "Install/CodexNotch.app"
            old = package(installed, 1)
            invoke(old, "legacy-write")
            invoke(old, "import-pet")
            atlas_hash = hashlib.sha256((import_source / "synthetic.png").read_bytes()).hexdigest()
            shutil.rmtree(import_source)
            invoke(old, "read-pet")
            invoke(old, "legacy-read")
            # Actual deletion/replacement of the complete fixture bundle.
            shutil.rmtree(installed)
            replacement = package(installed, 2)
            invoke(replacement, "legacy-read")
            invoke(replacement, "read")
            invoke(replacement, "read-pet")
            moved = scratch / "OtherWorktree/dist/CodexNotch.app"
            moved.parent.mkdir(parents=True)
            shutil.move(installed, moved)
            relocated = moved / "Contents/MacOS/SyntheticPreferenceProbe"
            invoke(relocated, "legacy-read")
            invoke(relocated, "read")
            invoke(relocated, "read-pet")
            invoke(relocated, "reject-unknown-pet")
            print("PASS: same-ID legacy .app replacement/relocation preserves all fixture choices")
            print("PASS: project-order opaque IDs and floating pet mode survive packaged replacement/relocation")
            print("PASS: production pet library/selection/atlas bytes survive source deletion and bundle replacement/relocation")
            # Demonstrate the pre-fix split with a missing bundle identity.
            invoke(binary, "legacy-read", expected=3)
            invoke(binary, "read")
            invoke(binary, "read-pet")
            invoke(binary, "write-zero")
            invoke(relocated, "read-zero")
            print("PASS: legacy unbundled launch reproduces split; explicit domain retains choices both ways")
            invoke(binary, "clean")
            invoke(relocated, "read-reset")
            invoke(relocated, "read-pet")
            invoke(binary, "pet-off")
            invoke(relocated, "read-pet-off")
            print("PASS: rejected pet selection preserves choice; explicit Off persists and retains owned artwork")
            print("PASS: explicit reset stays reset across generations; zero/false/data/unknown keys retained")
        finally:
            invoke(binary, "clean")


if __name__ == "__main__":
    main()
