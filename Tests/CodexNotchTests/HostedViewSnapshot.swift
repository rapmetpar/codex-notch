import AppKit
import SwiftUI
import XCTest

/// Capture the production SwiftUI view through its AppKit host at a fixed
/// pixel scale, without ImageRenderer's offscreen rendering path.
@MainActor
func hostedViewSnapshot<Content: View>(_ content: Content, size: NSSize? = nil) throws -> NSBitmapImageRep {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: content)
    let boundsSize = size ?? host.fittingSize
    host.frame = NSRect(origin: .zero, size: boundsSize)
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(ceil(boundsSize.width * 2)), pixelsHigh: Int(ceil(boundsSize.height * 2)),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = boundsSize
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
}
