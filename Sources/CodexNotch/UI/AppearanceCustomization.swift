import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Cosmetic preferences are independent of quota values and runtime state.
struct QuotaAppearance: Equatable {
    static let enabledKey = "customQuotaColorEnabled"
    static let colorKey = "customQuotaColorHex"
    static let defaultHex = "#A78BFA"
    static let defaultColor = QuotaColorScale.RGB(red: 167.0 / 255, green: 139.0 / 255, blue: 250.0 / 255)
    var customColor: QuotaColorScale.RGB?

    init(enabled: Bool = false, hex: String = defaultHex) {
        customColor = enabled ? Self.parse(hex) : nil
    }

    static func parse(_ hex: String) -> QuotaColorScale.RGB? {
        guard hex.count == 7, hex.first == "#",
              hex.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return .init(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }

    static func hex(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard channels.allSatisfy({ $0.isFinite }) else { return nil }
        return String(format: "#%02X%02X%02X", arguments:
            channels.map { Int((min(max($0, 0), 1) * 255).rounded()) })
    }

    func components(for remainingPercent: Double) -> QuotaColorScale.RGB {
        customColor ?? QuotaColorScale.components(for: remainingPercent)
    }

    func color(for remainingPercent: Double) -> Color {
        components(for: remainingPercent).color
    }
}

extension QuotaColorScale.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

enum CustomStatusIcon {
    static let storageKey = "customStatusIconPNG"
    static let maximumFileBytes = 8 * 1024 * 1024
    static let pixelSize = 128
    private static let cache = NSCache<NSData, NSImage>()

    enum ImportError: Error { case invalidImage, tooLarge }

    /// Decode only a bounded thumbnail, then re-encode pixels without source
    /// metadata or a persistent dependency on the selected file's location.
    static func normalizedPNG(from data: Data) throws -> Data {
        guard data.count <= maximumFileBytes else { throw ImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImportError.invalidImage }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            result, UTType.png.identifier as CFString, 1, nil
        ) else { throw ImportError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.invalidImage }
        return result as Data
    }

    static func importFile(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumFileBytes else { throw ImportError.tooLarge }
        return try normalizedPNG(from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func image(from data: Data) -> NSImage? {
        guard !data.isEmpty, data.count <= maximumFileBytes else { return nil }
        if let cached = cache.object(forKey: data as NSData) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        image.isTemplate = false
        cache.countLimit = 8
        cache.setObject(image, forKey: data as NSData)
        return image
    }
}

private struct QuotaAppearanceKey: EnvironmentKey {
    static let defaultValue = QuotaAppearance()
}

private struct CustomStatusIconKey: EnvironmentKey {
    static let defaultValue = Data()
}

extension EnvironmentValues {
    var quotaAppearance: QuotaAppearance {
        get { self[QuotaAppearanceKey.self] }
        set { self[QuotaAppearanceKey.self] = newValue }
    }

    var customStatusIconData: Data {
        get { self[CustomStatusIconKey.self] }
        set { self[CustomStatusIconKey.self] = newValue }
    }
}
