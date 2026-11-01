import SwiftUI

struct StatusIconTheme: Equatable {
    let accent: QuotaColorScale.RGB
    private let quotaLevel: WeeklyQuotaLevel
    private let hasCustomColor: Bool

    init(usage: UsageSnapshot?, appearance: QuotaAppearance = QuotaAppearance()) {
        hasCustomColor = appearance.customColor != nil
        quotaLevel = WeeklyQuotaLevel(weeklyWindow: usage?.weeklyWindow)
        if let weekly = usage?.weeklyWindow {
            accent = appearance.components(for: weekly.remainingPercent)
        } else {
            accent = QuotaColorScale.RGB(red: 0.6, green: 0.6, blue: 0.6)
        }
    }

    var flowerFill: QuotaColorScale.RGB {
        QuotaColorScale.RGB(red: 0, green: 0, blue: 0)
    }

    var runningEcho: QuotaColorScale.RGB {
        // A red quota is useful information; a recurring red pulse can read
        // as an alarm. Keep critical-quota activity neutral.
        quotaLevel == .critical && !hasCustomColor
            ? QuotaColorScale.RGB(red: 0.78, green: 0.78, blue: 0.78)
            : accent
    }

    var runningEchoColor: Color {
        Color(red: runningEcho.red, green: runningEcho.green, blue: runningEcho.blue)
    }

    var flowerColor: Color {
        Color(red: flowerFill.red, green: flowerFill.green, blue: flowerFill.blue)
    }

    var flowerOutlineColor: Color {
        .white
    }
}
