import SwiftUI

struct SettingsSearchView: View {
    @Binding var search: SettingsSearchState
    let language: AppLanguage
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(language.localized(chinese: "搜索设置", english: "Search settings", russian: "Поиск настроек"), text: $search.query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .accessibilityIdentifier("settings.search")
                .onSubmit { if search.submit() { fieldFocused = false } }
                .onExitCommand {
                    if search.query.isEmpty { fieldFocused = false } else { search.clear() }
                }
            if !search.query.isEmpty {
                Button {
                    search.clear()
                    fieldFocused = true
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.localized(chinese: "清除搜索", english: "Clear search", russian: "Очистить поиск"))
            }
        }
        .overlay(alignment: .top) {
            if search.isSearching {
                results
                    .padding(.top, 34)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            if search.results.isEmpty {
                Text(language.localized(chinese: "未找到设置", english: "No settings found", russian: "Настройки не найдены"))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(search.results) { item in
                            Button {
                                if search.select(item) { fieldFocused = false }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title(for: language)).fixedSize(horizontal: false, vertical: true)
                                    Text(item.tab.title(for: language)).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.search.result.\(item.rawValue)")
                        }
                    }
                    .padding(4)
                }
                .frame(height: min(CGFloat(search.results.count) * 66, 240))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .onExitCommand { search.clear(); fieldFocused = true }
    }
}

private struct SettingsSearchRequestKey: EnvironmentKey {
    static let defaultValue: SettingsSearchState.Request? = nil
}

extension EnvironmentValues {
    var settingsSearchRequest: SettingsSearchState.Request? {
        get { self[SettingsSearchRequestKey.self] }
        set { self[SettingsSearchRequestKey.self] = newValue }
    }
}

/// Keeps the existing Form and native controls. Repeated requests scroll again;
/// a pane mounted after a tab switch consumes the same request on appearance.
struct SettingsSearchPane<Content: View>: View {
    let tab: SettingsTab
    let search: SettingsSearchState
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .environment(\.settingsSearchRequest, search.selectedTab == tab ? search.request : nil)
                .task(id: search.request) {
                    guard search.selectedTab == tab, let request = search.request,
                          request.target.tab == tab else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(request.target, anchor: .center)
                }
        }
    }
}

private struct SettingsSearchTarget: ViewModifier {
    let id: SettingsSearchID
    @Environment(\.settingsSearchRequest) private var request
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    func body(content: Content) -> some View {
        content
            .id(id)
            .focused($focused)
            .accessibilityFocused($accessibilityFocused)
            .accessibilityIdentifier("settings.control.\(id.rawValue)")
            .overlay {
                if request?.target == id {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .task(id: request) {
                guard request?.target == id else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                focused = true
                accessibilityFocused = true
            }
    }
}

extension View {
    func settingsSearchTarget(_ id: SettingsSearchID) -> some View {
        modifier(SettingsSearchTarget(id: id))
    }
}
