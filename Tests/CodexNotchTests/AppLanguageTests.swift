import XCTest
@testable import CodexNotch

final class AppLanguageTests: XCTestCase {
    func testRussianIsSelectableWithoutChangingExistingLanguageValuesOrFallback() {
        XCTAssertEqual(AppLanguage.russian.title, "Русский")
        XCTAssertTrue(AppLanguage.allCases.contains(.russian))
        XCTAssertEqual(AppLanguage.fromStoredValue("ru"), .russian)
        XCTAssertEqual(AppLanguage.fromStoredValue("en"), .english)
        XCTAssertEqual(AppLanguage.fromStoredValue("zh-Hans"), .chinese)
        XCTAssertEqual(AppLanguage.fromStoredValue(nil), .english)
        XCTAssertEqual(AppLanguage.fromStoredValue("unknown"), .english)
    }

    func testRussianPreferenceRoundTripsAndDoesNotChangeOtherPreferences() throws {
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(5, forKey: RecentConversationLimit.storageKey)
        defaults.set(false, forKey: AppAnimationPreference.storageKey)
        let initial = NotchRuntimePreferences.read(from: defaults)

        for language in [AppLanguage.russian, .chinese, .english, .russian] {
            defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
            let updated = NotchRuntimePreferences.read(from: defaults)
            XCTAssertEqual(updated.language, language)
            XCTAssertEqual(updated.recentConversationLimit, initial.recentConversationLimit)
            XCTAssertEqual(updated.animationsEnabled, initial.animationsEnabled)
            XCTAssertEqual(updated.notchDisplayEnabled, initial.notchDisplayEnabled)
            XCTAssertEqual(updated.leftIndicatorEnabled, initial.leftIndicatorEnabled)
        }
    }

    func testRussianQuotaKeepsWeeklyAndFiveHourValuesDistinct() {
        let usage = UsageSnapshot(windows: [
            UsageWindow(id: "five-hour", kind: .rolling(hours: 5), usedPercent: 42),
            UsageWindow(id: "weekly", kind: .weekly, usedPercent: 25)
        ])
        XCTAssertEqual(
            NotchText.quotaSubtitle(usage: usage, language: .russian),
            "За неделю: осталось 75% · использовано 25% · За 5 ч: осталось 58% · использовано 42%"
        )
        XCTAssertEqual(NotchText.quotaSubtitle(usage: nil, language: .russian), "Лимит недоступен")
        XCTAssertEqual(NotchText.quotaSubtitle(usage: UsageSnapshot(windows: []), language: .russian), "Лимит недоступен")
        XCTAssertEqual(NotchText.quotaWindowTitle(.weekly, language: .russian), "Остаток на неделю")
        XCTAssertEqual(NotchText.quotaWindowTitle(.rolling(hours: 5), language: .russian), "Остаток на 5 ч")
    }

    func testRussianTimesKeepSecondsAndUseRussianUnits() {
        let now = Date(timeIntervalSince1970: 1_000)
        for (seconds, expected) in [(0, "только что"), (120, "2 мин назад"), (7_200, "2 ч назад"), (172_800, "2 дн. назад")] {
            XCTAssertEqual(NotchText.relativeTime(from: now.addingTimeInterval(-Double(seconds)), now: now, language: .russian), expected)
        }
        XCTAssertEqual(NotchText.resetCountdown(resetAt: now.addingTimeInterval(183_845), now: now, language: .russian), "2 дн. 03:04:05")
        XCTAssertEqual(NotchText.resetCountdown(resetAt: now, now: now, language: .russian), "00:00:00")
        let credit = ResetCredit(id: "example", expiresAt: Date(timeIntervalSince1970: 1_768_377_845))
        XCTAssertEqual(NotchText.resetCreditExpiry(credit, timeZone: TimeZone(secondsFromGMT: 0)!, language: .russian), "До 2026-01-14 08:04:05")
        XCTAssertEqual(NotchText.resetCreditExpiry(ResetCredit(id: "unknown"), language: .russian), "Срок действия недоступен")
    }

    func testRussianRecentChatCountsUseCorrectForms() {
        XCTAssertEqual(RecentConversationLimit.allCases.map { $0.title(for: .russian) },
                       ["0 чатов", "1 чат", "2 чата", "3 чата", "4 чата", "5 чатов"]
                       + (6...20).map { "\($0) чатов" })
    }

    func testRussianSettingsAndFallbackCopy() {
        XCTAssertEqual(QuotaDisplayStyle.clockwiseRing.title(for: .russian), "Кольцо")
        XCTAssertEqual(StatusIconStyle.off.title(for: .russian), "Выкл.")
        XCTAssertEqual(FloatingCenterStyle.elapsed.title(for: .russian), "Таймер")
        XCTAssertEqual(FloatingPreviewState.running.title(for: .russian), "В работе")
        XCTAssertEqual(FloatingPreviewState.completed.title(for: .russian), "Завершено")
        XCTAssertEqual(FloatingSettingsContext.notched.title(for: .russian), "Сейчас: экран с вырезом")
        XCTAssertEqual(NotchText.projectName(cwd: nil, language: .russian), "Задача без названия")
        XCTAssertEqual(NotchText.resetCreditTitle(ResetCredit(id: "unknown"), language: .russian), "Сброс лимита")
        XCTAssertEqual(NotchText.resetCredits(usage: nil, language: .russian), "Сбросы —")
    }
}
