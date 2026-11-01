import XCTest
@testable import CodexNotch

final class NativeNotchTestPlacementTests: XCTestCase {
    func testOffscreenSyntheticFixtureBecomesFullyVisibleWithoutChangingLayoutOrCrop() {
        // These are test viewports, not asserted GitHub runner resolutions.
        let viewports = [CGRect(x: 0, y: 0, width: 1280, height: 720),
                         CGRect(x: -800, y: 100, width: 800, height: 600),
                         CGRect(x: 400, y: -900, width: 1920, height: 900)]
        for viewport in viewports {
            // Also covers an uncropped single slot and the original icon-Off
            // crop. Placement must not depend on the superseded wider pet wing.
            for leading: CGFloat in [0, 36] {
                let source = NotchLayout(mode: .notch, centerX: 570.5,
                    hoverSensorFrame: CGRect(x: 478, y: 1968, width: 185, height: 32),
                    compactFrame: CGRect(x: 400, y: 1968, width: 341, height: 32),
                    quotaExpandedFrame: CGRect(x: 360.5, y: 1740, width: 420, height: 260),
                    expandedFrame: CGRect(x: 360.5, y: 1560, width: 420, height: 440),
                    compactLeadingInset: leading)
                XCTAssertFalse(viewport.contains(source.visibleCompactFrame), "The original global-coordinate fixture is offscreen")
                let placed = NativeNotchTestPlacement.centered(source, in: viewport)
                XCTAssertTrue(viewport.contains(placed.visibleCompactFrame))
                XCTAssertEqual(placed.visibleCompactFrame.midX, viewport.midX)
                XCTAssertEqual(placed.visibleCompactFrame.midY, viewport.midY)
                XCTAssertEqual(placed.mode, source.mode)
                XCTAssertEqual(placed.compactLeadingInset, leading)
                XCTAssertEqual(placed.centerX - placed.compactFrame.minX,
                    source.centerX - source.compactFrame.minX, "Keep the camera/content anchor")
                let dx = placed.centerX - source.centerX
                let dy = placed.compactFrame.minY - source.compactFrame.minY
                for (original, translated) in [(source.compactFrame, placed.compactFrame),
                    (source.hoverSensorFrame, placed.hoverSensorFrame),
                    (source.quotaExpandedFrame, placed.quotaExpandedFrame),
                    (source.expandedFrame, placed.expandedFrame)] {
                    XCTAssertEqual(translated, original.offsetBy(dx: dx, dy: dy),
                        "Translate the entire fixture without resizing or changing its relative geometry")
                }
            }
        }
    }
}
