import AppKit
import SwiftUI

enum AppIdentity {
    static let bundleIdentifier = "com.david.codexnotch"
    static let chatGPTCodexBundleIdentifier = "com.openai.codex"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtimeCoordinator: NotchRuntimeCoordinator?
    private var quotaWindow: NSWindow?

    func showQuotaCheckpoint() {
        guard let checkpoint = runtimeCoordinator?.quotaCheckpoint else { return }
        if quotaWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 230), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: QuotaCheckpointView(checkpoint: checkpoint))
            window.center()
            quotaWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        quotaWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--verify-bundled-resources") {
            // Exit before reading credentials or starting session monitoring.
            let valid = SwordWandererAsset.pixelSize == CGSize(width: 1_536, height: 2_288)
                && SwordWandererAsset.swordImage != nil
                && SwordWandererAsset.slimeImage != nil
                && SwordWandererAsset.hitSparkImage != nil
            print(valid ? "Bundled resources verified" : "Bundled resources missing or invalid")
            exit(valid ? 0 : 1)
        }
        NSApp.setActivationPolicy(.accessory)
        runtimeCoordinator = NotchRuntimeCoordinator()
        runtimeCoordinator?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtimeCoordinator?.stop()
    }
}
