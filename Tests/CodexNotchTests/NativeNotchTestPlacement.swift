import Foundation
@testable import CodexNotch

/// Synthetic geometry tests may use any screen. Native playback tests must put
/// their real window on the desktop hosting the test process, not at synthetic
/// global coordinates that can be above/outside a smaller CI display.
enum NativeNotchTestPlacement {
    static func centered(_ layout: NotchLayout, in visibleFrame: CGRect) -> NotchLayout {
        let compact = layout.visibleCompactFrame
        let dx = visibleFrame.midX - compact.midX
        let dy = visibleFrame.midY - compact.midY
        return NotchLayout(
            mode: layout.mode,
            centerX: layout.centerX + dx,
            hoverSensorFrame: layout.hoverSensorFrame.offsetBy(dx: dx, dy: dy),
            compactFrame: layout.compactFrame.offsetBy(dx: dx, dy: dy),
            quotaExpandedFrame: layout.quotaExpandedFrame.offsetBy(dx: dx, dy: dy),
            expandedFrame: layout.expandedFrame.offsetBy(dx: dx, dy: dy),
            compactLeadingInset: layout.compactLeadingInset,
            compactTrailingInset: layout.compactTrailingInset
        )
    }
}
