import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class SettingsSearchViewTests: XCTestCase {
    private final class Session: ObservableObject {
        @Published var search = SettingsSearchState()
        @Published var language = AppLanguage.english
        @Published var animations = false
    }

    private struct Fixture: View {
        @ObservedObject var session: Session
        @ObservedObject var companion: PetCompanionController
        var body: some View {
            VStack {
                SettingsSearchView(search: $session.search, language: session.language).zIndex(1)
                TabView(selection: $session.search.selectedTab) {
                    Text("Synthetic general tab").tabItem { Text("General") }.tag(SettingsTab.general)
                    SettingsSearchPane(tab: .pets, search: session.search) {
                        PetCompanionSettingsView(companion: companion, language: session.language)
                    }.tabItem { Text("Companions") }.tag(SettingsTab.pets)
                    SettingsSearchPane(tab: .appearance, search: session.search) {
                        Form {
                            Section {
                                ForEach(0..<40) { Text("Synthetic row \($0)") }
                                Toggle("Animations", isOn: $session.animations)
                                    .settingsSearchTarget(.animations)
                                ForEach(40..<60) { Text("Synthetic row \($0)") }
                            }
                        }
                        .formStyle(.grouped)
                    }.tabItem { Text("Appearance") }.tag(SettingsTab.appearance)
                }
            }.padding(16).frame(width: 560, height: 580)
                .accentColor(.red)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        }
    }

    @MainActor
    func testNativeSubmitRevealsRealImportControlWithoutOpeningImporterOrWritingData() throws {
        _ = NSApplication.shared
        let domain = "CodexNotch.synthetic.searchUI.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let companion = PetCompanionController(store: PetLibraryStore(rootURL: root), defaults: defaults, loadImmediately: false)
        let session = Session()
        let host = NSHostingView(rootView: Fixture(session: session, companion: companion).defaultAppStorage(defaults))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: 1_000, width: 560, height: 580),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(editableField(in: host))
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("pet import", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(session.search.results, [.importCompanions])
        session.language = .russian
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(session.search.query, "pet import", "Live localization must not discard the query")
        sendKey("\r", code: 36, to: editor, window: window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(session.search.selectedTab, .pets)
        XCTAssertEqual(session.search.request?.target, .importCompanions)
        XCTAssertTrue(session.search.query.isEmpty)
        XCTAssertTrue(try hasHighlight(in: host), "The real import row must show a visible outline")
        XCTAssertNil(window.attachedSheet, "Return navigates; it must not open the import dialog")
        XCTAssertFalse(companion.isBusy)
        XCTAssertTrue(companion.library.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(defaults.persistentDomain(forName: domain)?.isEmpty ?? true)
        session.search.dismiss()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(try hasHighlight(in: host), "The same pane must lack the outline without a request")
    }

    @MainActor
    func testNativeEscapeClearsQueryAndDoesNotNavigate() throws {
        _ = NSApplication.shared
        let session = Session()
        let host = NSHostingView(rootView: SettingsSearchView(search: Binding(
            get: { session.search }, set: { session.search = $0 }
        ), language: .english).frame(width: 500, height: 40))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: 1_000, width: 500, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(editableField(in: host))
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("motion", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        sendKey("\u{1b}", code: 53, to: editor, window: window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(session.search.query.isEmpty)
        XCTAssertNil(session.search.request)
        XCTAssertEqual(session.search.selectedTab, .general)
    }

    @MainActor
    func testNativeReturnScrollsToAnOffscreenToggleWithoutChangingItsValue() throws {
        _ = NSApplication.shared
        let domain = "CodexNotch.synthetic.searchScroll.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        let companion = PetCompanionController(store: PetLibraryStore(rootURL: root), defaults: defaults, loadImmediately: false)
        let session = Session()
        session.search.selectedTab = .appearance
        let host = NSHostingView(rootView: Fixture(session: session, companion: companion).defaultAppStorage(defaults))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: 1_000, width: 560, height: 580),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(try hasHighlight(in: host))
        let field = try XCTUnwrap(editableField(in: host))
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("motion", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        sendKey("\r", code: 36, to: editor, window: window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(try hasHighlight(in: host), "The initially offscreen toggle must scroll into view")
        XCTAssertFalse(session.animations, "Return navigates without toggling")
    }

    @MainActor
    private func hasHighlight(in host: NSView) throws -> Bool {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // In this monochrome fixture the outline is the only long colored
        // horizontal segment in the upper form. Sample below the search field.
        for y in (bitmap.pixelsHigh / 8)..<(bitmap.pixelsHigh * 7 / 8) {
            var span = 0
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.saturationComponent > 0.5 {
                    span += 2
                    if span >= bitmap.pixelsWide / 8 { return true }
                } else {
                    span = 0
                }
            }
        }
        return false
    }

    @MainActor
    private func sendKey(_ characters: String, code: UInt16, to editor: NSTextView, window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        editor.keyDown(with: event)
    }

    @MainActor
    private func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { self.editableField(in: $0) }.first
    }
}
