#!/usr/bin/env python3
"""Preference upgrade/relocation guard. Only UUID-scoped synthetic domains.

Compiles the production preference factory into a tiny fixture executable,
never launches the real app/runtime, changes HOME or opens a real user domain.
The legacy branch models the pre-fix implicit UserDefaults.standard behavior.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
SOURCE = r'''
import Foundation
let mode = CommandLine.arguments[1]
let domain = CommandLine.arguments[2]
precondition(domain.hasPrefix("CodexNotch.synthetic.upgrade."))
let suite = AppPreferences.makeStore(domain: domain)
let expected: [String: Any] = [
    "appLanguage": "ru", "recentConversationLimit": 20,
    "conversationCategoryOrder.v1": "viewed,unread,running",
    "animationsEnabled": false, "notchDisplayEnabled": false,
    "quotaDisplayStyle": "waveBall", "statusIconStyle": "custom",
    "customQuotaColorEnabled": true, "customQuotaColorHex": "#123456",
    "floatingCenterStyle": "signature", "floatingCenterText": "hello  ",
    "customStatusIconPNG": Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==")!,
    "futureFixture.v1": "preserve unknown keys"
]
func matches(_ defaults: UserDefaults) -> Bool {
    expected.allSatisfy { key, value in
        guard let stored = defaults.object(forKey: key) else { return false }
        return (stored as AnyObject).isEqual(value)
    }
}
switch mode {
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


def run(executable, mode, domain, expected=0):
    result = subprocess.run([str(executable), mode, domain], capture_output=True, text=True)
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
                        str(ROOT / "Sources/CodexNotch/State/AppPreferences.swift"), str(helper),
                        "-o", str(binary)], check=True, capture_output=True, text=True)

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

        try:
            installed = scratch / "Install/CodexNotch.app"
            old = package(installed, 1)
            run(old, "legacy-write", domain)
            run(old, "legacy-read", domain)
            # Actual deletion/replacement of the complete fixture bundle.
            shutil.rmtree(installed)
            replacement = package(installed, 2)
            run(replacement, "legacy-read", domain)
            run(replacement, "read", domain)
            moved = scratch / "OtherWorktree/dist/CodexNotch.app"
            moved.parent.mkdir(parents=True)
            shutil.move(installed, moved)
            relocated = moved / "Contents/MacOS/SyntheticPreferenceProbe"
            run(relocated, "legacy-read", domain)
            run(relocated, "read", domain)
            print("PASS: same-ID legacy .app replacement/relocation preserves all fixture choices")
            # Demonstrate the pre-fix split with a missing bundle identity.
            run(binary, "legacy-read", domain, expected=3)
            run(binary, "read", domain)
            run(binary, "write-zero", domain)
            run(relocated, "read-zero", domain)
            print("PASS: legacy unbundled launch reproduces split; explicit domain retains choices both ways")
            run(binary, "clean", domain)
            run(relocated, "read-reset", domain)
            print("PASS: explicit reset stays reset across generations; zero/false/data/unknown keys retained")
        finally:
            run(binary, "clean", domain)


if __name__ == "__main__":
    main()
