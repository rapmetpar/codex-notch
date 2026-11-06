import XCTest
@testable import CodexNotch

final class SettingsSearchTests: XCTestCase {
    func testThreeLanguagesFindTheRequestedControlRegardlessOfInterfaceLanguage() {
        let cases: [(String, SettingsSearchID)] = [
            ("motion", .animations), ("АНИМАЦИЯ", .animations), ("动画", .animations),
            ("recent limit", .recentTasks), ("число чатов", .recentTasks), ("最近任务数量", .recentTasks),
            ("pet import", .importCompanions), ("импорт питомца", .importCompanions), ("导入宠物", .importCompanions)
        ]
        for (query, target) in cases {
            var search = SettingsSearchState()
            search.query = query
            XCTAssertEqual(search.results.first, target, query)
            for language in AppLanguage.allCases {
                XCTAssertFalse(target.title(for: language).isEmpty)
                XCTAssertFalse(target.tab.title(for: language).isEmpty)
            }
            XCTAssertTrue(search.submit())
            XCTAssertEqual(search.selectedTab, target.tab)
            XCTAssertEqual(search.request?.target, target)
            XCTAssertFalse(search.isSearching)
        }
    }

    func testSearchNormalizesCaseWidthAndWhitespaceAndRequiresAllTerms() {
        XCTAssertEqual(SettingsSearchIndex.results(for: "  ＭＯＴＩＯＮ\n"), [.animations])
        XCTAssertEqual(SettingsSearchIndex.results(for: "pet\timport"), [.importCompanions])
        XCTAssertTrue(SettingsSearchIndex.results(for: "pet missingterm").isEmpty)
        for query in ["", "   \n\t", "no-such-setting-91"] {
            XCTAssertTrue(SettingsSearchIndex.results(for: query).isEmpty)
        }
    }

    func testEveryIndexedSettingNavigatesAndRepeatedSelectionHasFreshRequest() {
        for target in SettingsSearchID.allCases {
            var search = SettingsSearchState()
            for language in AppLanguage.allCases {
                search.query = target.title(for: language)
                let previous = search.request
                XCTAssertTrue(search.select(target), "\(target) / \(language)")
                XCTAssertEqual(search.selectedTab, target.tab)
                XCTAssertEqual(search.request?.target, target)
                XCTAssertNotEqual(search.request, previous)
            }
        }
    }

    func testNoResultsStaleResultsAndClearNeverNavigate() {
        var search = SettingsSearchState()
        search.query = "no-such-setting-91"
        XCTAssertFalse(search.submit())
        XCTAssertFalse(search.select(.launchAtLogin))
        XCTAssertNil(search.request)
        XCTAssertEqual(search.selectedTab, .general)
        search.query = "pet import"
        search.clear()
        XCTAssertFalse(search.select(.importCompanions), "A stale result must not navigate")
        XCTAssertNil(search.request)
        search.query = "motion"
        XCTAssertTrue(search.submit())
        let request = search.request
        search.query = "language"
        search.clear()
        XCTAssertEqual(search.request, request)
        XCTAssertEqual(search.selectedTab, .appearance)
        search.selectedTab = .general
        search.selectedTab = .appearance
        XCTAssertNil(search.request, "Manual tab changes must not replay a past search")
        search.query = "motion"
        XCTAssertTrue(search.submit())
        search.dismiss()
        XCTAssertNil(search.request)
        XCTAssertTrue(search.query.isEmpty)
        XCTAssertTrue(SettingsSearchState().query.isEmpty, "A new window never restores a query")
    }

    func testNavigationCannotWritePreferencesOrIndexTheirPrivateValues() throws {
        let domain = "CodexNotch.synthetic.search.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let values: [String: Any] = ["recentConversationLimit": 0, "animationsEnabled": false,
                                   "floatingCenterText": "private-91  ", "appLanguage": "ru"]
        defaults.setPersistentDomain(values, forName: domain)
        let before = defaults.persistentDomain(forName: domain)! as NSDictionary
        for target in SettingsSearchID.allCases {
            var search = SettingsSearchState()
            search.query = target.title(for: .english)
            XCTAssertTrue(search.select(target))
            search.clear()
            search.dismiss()
        }
        XCTAssertTrue(SettingsSearchIndex.results(for: "private-91").isEmpty)
        XCTAssertTrue(SettingsSearchIndex.results(for: "personal-pet-91").isEmpty)
        XCTAssertTrue(SettingsSearchIndex.results(for: "secret-file-91.png").isEmpty)
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before)
    }
}
