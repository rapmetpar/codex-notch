import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import CodexNotch

final class AppearanceCustomizationTests: XCTestCase {
    func testCustomColorOverridesEveryBandAndRestoringDefaultsRestoresWarnings() throws {
        let custom = QuotaAppearance(enabled: true, hex: "#A78BFA")
        let rgb = try XCTUnwrap(custom.customColor)
        for remaining in [100.0, 50, 20, 10, 0] {
            XCTAssertEqual(custom.components(for: remaining), rgb)
            let usage = UsageSnapshot(windows: [UsageWindow(
                id: "weekly", kind: .weekly, usedPercent: 100 - remaining
            )])
            XCTAssertEqual(StatusIconTheme(usage: usage, appearance: custom).runningEcho, rgb)
            XCTAssertEqual(QuotaAppearance(enabled: false, hex: "#A78BFA").components(for: remaining),
                           QuotaColorScale.components(for: remaining))
        }
        XCTAssertEqual(StatusIconTheme(usage: nil, appearance: custom).accent,
                       StatusIconTheme(usage: nil).accent, "Missing quota stays neutral")
        for value in ["", "#123", "#12345678", "#GGGGGG", "123456", "#１２３４５６"] {
            XCTAssertNil(QuotaAppearance(enabled: true, hex: value).customColor)
        }
        XCTAssertEqual(QuotaAppearance.hex(for: NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)), "#A78BFA")
    }

    @MainActor
    func testImportedIconIsBoundedTransparentAndRetainsOriginalColors() throws {
        let data = try iconPNG(width: 512, height: 256, color: .systemPink)
        let normalized = try CustomStatusIcon.normalizedPNG(from: data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(normalized as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 64)
        let renderer = ImageRenderer(content: StatusMark(style: .custom, size: 18)
            .environment(\.customStatusIconData, normalized))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        let center = try XCTUnwrap(bitmap.colorAt(x: 18, y: 18)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.redComponent, 0.7)
        XCTAssertLessThan(center.greenComponent, 0.6)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.01)
        XCTAssertFalse(try XCTUnwrap(CustomStatusIcon.image(from: normalized)).isTemplate)
    }

    @MainActor
    func testInvalidImageAndOversizedInputFailWithoutReplacingSavedArtwork() throws {
        XCTAssertThrowsError(try CustomStatusIcon.normalizedPNG(from: Data("not an image".utf8)))
        XCTAssertThrowsError(try CustomStatusIcon.normalizedPNG(from: Data(count: CustomStatusIcon.maximumFileBytes + 1)))
        XCTAssertNil(CustomStatusIcon.image(from: Data("bad".utf8)))
        let renderer = ImageRenderer(content: StatusMark(style: .custom, size: 18)
            .environment(\.customStatusIconData, Data("bad".utf8)))
        XCTAssertNotNil(renderer.cgImage, "A missing/corrupt custom icon keeps the embedded fallback")
    }

    @MainActor
    func testPreferencesReopenWithoutSourceFileAndDoNotChangeRuntimeData() throws {
        let suite = "AppearanceCustomization.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = NotchRuntimePreferences.read(from: defaults)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try iconPNG(width: 64, height: 64, color: .systemPurple).write(to: url)
        let normalized = try CustomStatusIcon.importFile(url)
        defaults.set(normalized, forKey: CustomStatusIcon.storageKey)
        defaults.set(StatusIconStyle.custom.rawValue, forKey: StatusIconStyle.storageKey)
        defaults.set(true, forKey: QuotaAppearance.enabledKey)
        defaults.set("#A78BFA", forKey: QuotaAppearance.colorKey)
        try FileManager.default.removeItem(at: url)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertNotNil(CustomStatusIcon.image(from: try XCTUnwrap(reopened.data(forKey: CustomStatusIcon.storageKey))))
        XCTAssertEqual(StatusIconStyle.fromStoredValue(reopened.string(forKey: StatusIconStyle.storageKey)), .custom)
        XCTAssertEqual(QuotaAppearance(enabled: reopened.bool(forKey: QuotaAppearance.enabledKey),
                                       hex: try XCTUnwrap(reopened.string(forKey: QuotaAppearance.colorKey))).customColor,
                       QuotaAppearance.parse("#A78BFA"))
        XCTAssertEqual(NotchRuntimePreferences.read(from: reopened), runtime)
        for mode in [NotchLayoutMode.notch, .floatingBar] {
            XCTAssertEqual(CompactLeftIndicatorPolicy.content(layoutMode: mode, hasFiveHourWindow: true, iconStyle: .custom), .fiveHourQuota)
            XCTAssertEqual(CompactLeftIndicatorPolicy.content(layoutMode: mode, hasFiveHourWindow: false, iconStyle: .custom), .appStatus)
        }
    }

    @MainActor
    func testChangingCustomArtworkAndTintKeepsTheEchoAnimationPhaseAndGeometry() throws {
        let view = StatusMarkEchoLayerView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        view.layout()
        let first = try CustomStatusIcon.normalizedPNG(from: iconPNG(width: 64, height: 64, color: .red))
        let second = try CustomStatusIcon.normalizedPNG(from: iconPNG(width: 64, height: 32, color: .blue))
        view.configure(iconStyle: .custom, isAnimating: true, customIconData: first)
        let echo = try XCTUnwrap(view.layer?.sublayers?.first)
        view.startLayerAnimation()
        let key = try XCTUnwrap(echo.animationKeys()?.first)
        let pulse = try XCTUnwrap(echo.animation(forKey: key)?.copy() as? CAAnimation)
        pulse.beginTime = CACurrentMediaTime() - 0.5
        echo.add(pulse, forKey: key)
        let maskBefore = try maskImage(from: echo)
        let color = try XCTUnwrap(QuotaAppearance.parse("#A78BFA"))
        view.configure(iconStyle: .custom, color: color, isAnimating: true, customIconData: second)
        let maskAfter = try maskImage(from: echo)
        XCTAssertNotEqual(maskBefore.height, maskAfter.height)
        XCTAssertEqual(echo.bounds.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(try XCTUnwrap(echo.animation(forKey: key)).beginTime, pulse.beginTime)
        XCTAssertEqual(try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(echo.backgroundColor))).redComponent, color.red, accuracy: 0.001)
        view.viewWillMove(toWindow: nil)
        XCTAssertTrue(echo.animationKeys()?.isEmpty ?? true)
    }

    @MainActor
    func testRingRendersCustomColorAtLowQuotaAndRestoresRed() throws {
        _ = NSApplication.shared
        func gradients(in view: NSView) -> [QuotaGradientLayerView] {
            (view as? QuotaGradientLayerView).map { [$0] }
                ?? view.subviews.flatMap { gradients(in: $0) }
        }
        for appearance in [QuotaAppearance(enabled: true), QuotaAppearance()] {
            let hosting = NSHostingView(rootView: QuotaRing(
                style: .clockwiseRing,
                window: UsageWindow(id: "weekly", kind: .weekly, usedPercent: 95),
                activity: .running, diameter: 40, lineWidth: 4, fontSize: 10
            ).environment(\.quotaAppearance, appearance).environment(\.notchMotionEnabled, true))
            hosting.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
            hosting.layoutSubtreeIfNeeded()
            let layers = gradients(in: hosting)
            XCTAssertEqual(layers.count, 2, "Both the quota arc and inner glow remain present")
            let gradient = try XCTUnwrap(layers.first?.layer?.sublayers?.first as? CAGradientLayer)
            let colors = try XCTUnwrap(gradient.colors)
            let expected = appearance.components(for: 5)
            for value in colors {
                let color = try XCTUnwrap(NSColor(cgColor: value as! CGColor)?.usingColorSpace(.sRGB))
                XCTAssertEqual(color.redComponent, expected.red, accuracy: 0.001)
                XCTAssertEqual(color.greenComponent, expected.green, accuracy: 0.001)
                XCTAssertEqual(color.blueComponent, expected.blue, accuracy: 0.001)
            }
        }
    }

    private func maskImage(from layer: CALayer) throws -> CGImage {
        let contents = try XCTUnwrap(layer.mask?.contents)
        XCTAssertEqual(CFGetTypeID(contents as CFTypeRef), CGImage.typeID)
        return contents as! CGImage
    }

    private func iconPNG(width: Int, height: Int, color: NSColor) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: rgb.redComponent, green: rgb.greenComponent,
                             blue: rgb.blueComponent, alpha: 1)
        context.fill(CGRect(x: width / 4, y: 0, width: width - width / 4, height: height))
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
