import SwiftUI
import UniformTypeIdentifiers

struct NotchSettingsView: View {
    @ObservedObject private var companion = PetCompanionController.shared
    @State private var petPreviewSession = PetCompanionSceneSession()
    @AppStorage(QuotaAppearance.enabledKey) private var customQuotaColorEnabled = false
    @AppStorage(QuotaAppearance.colorKey) private var customQuotaColorHex = QuotaAppearance.defaultHex
    @AppStorage(CustomStatusIcon.storageKey) private var customIconData = Data()
    @State private var choosingIcon = false
    @State private var iconImportError: String?
    @AppStorage(QuotaDisplayStyle.storageKey)
    private var quotaDisplayStyleRaw = QuotaDisplayStyle.defaultStyle.rawValue
    @AppStorage(StatusIconStyle.storageKey)
    private var statusIconStyleRaw = StatusIconStyle.defaultStyle.rawValue
    @AppStorage(RecentConversationLimit.storageKey)
    private var recentConversationLimitRaw = RecentConversationLimit.defaultLimit.rawValue
    @AppStorage(ConversationCategoryOrder.storageKey)
    private var conversationCategoryOrderRaw = ConversationCategoryOrder.defaultOrder.rawValue
    @AppStorage(AppLanguage.storageKey)
    private var appLanguageRaw = AppLanguage.defaultLanguage.rawValue
    @AppStorage(AppAnimationPreference.storageKey)
    private var animationsEnabled = AppAnimationPreference.defaultEnabled
    @AppStorage(FloatingCenterStyle.storageKey)
    private var floatingCenterStyleRaw = FloatingCenterStyle.defaultStyle.rawValue
    @AppStorage(FloatingCenterText.storageKey)
    private var floatingCenterText = FloatingCenterText.defaultText
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared

    private var appLanguage: AppLanguage {
        AppLanguage.fromStoredValue(appLanguageRaw)
    }

    private var selectedStyle: QuotaDisplayStyle {
        QuotaDisplayStyle.fromStoredValue(quotaDisplayStyleRaw)
    }

    private var selectedStyleBinding: Binding<QuotaDisplayStyle> {
        Binding(
            get: { selectedStyle },
            set: { quotaDisplayStyleRaw = $0.rawValue }
        )
    }

    private var recentConversationLimit: RecentConversationLimit {
        RecentConversationLimit.fromStoredValue(recentConversationLimitRaw)
    }

    private var statusIconStyleBinding: Binding<StatusIconStyle> {
        Binding(
            get: { StatusIconStyle.fromStoredValue(statusIconStyleRaw) },
            set: { statusIconStyleRaw = $0.rawValue }
        )
    }

    private var recentConversationLimitBinding: Binding<RecentConversationLimit> {
        Binding(
            get: { recentConversationLimit },
            set: { recentConversationLimitRaw = $0.rawValue }
        )
    }

    private var conversationCategoryOrderBinding: Binding<ConversationCategoryOrder> {
        Binding(
            get: { ConversationCategoryOrder.fromStoredValue(conversationCategoryOrderRaw) },
            set: { conversationCategoryOrderRaw = $0.rawValue }
        )
    }

    @AppStorage(NotchDisplayPreference.storageKey)
    private var notchDisplayEnabled = NotchDisplayPreference.defaultEnabled
    @State private var selectedTab: SettingsTab = .general
    @State private var layoutMode: NotchLayoutMode?
    @State private var previewState = FloatingPreviewState.running

    private enum SettingsTab { case general, appearance, floating, pets }
    private var floatingStyle: FloatingCenterStyle { .fromStoredValue(floatingCenterStyleRaw) }
    private var floatingContext: FloatingSettingsContext {
        FloatingSettingsContext(layoutMode: layoutMode, displayEnabled: notchDisplayEnabled)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalSettings
                .tabItem { Label(appLanguage.localized(chinese: "通用", english: "General", russian: "Основные"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            appearanceSettings
                .tabItem { Label(appLanguage.localized(chinese: "外观", english: "Appearance", russian: "Внешний вид"), systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
            PetCompanionSettingsView(companion: companion, language: appLanguage)
                .tabItem { Label(appLanguage.localized(chinese: "宠物", english: "Companions", russian: "Питомцы"), systemImage: "pawprint") }
                .tag(SettingsTab.pets)
            floatingSettings
                .tabItem { Label(appLanguage.localized(chinese: "浮动横条", english: "Floating Bar", russian: "Плавающая панель"), systemImage: "display") }
                .tag(SettingsTab.floating)
        }
        .environment(\.customStatusIconData, customIconData)
        .fileImporter(isPresented: $choosingIcon, allowedContentTypes: [.png, .jpeg]) { result in
            switch result {
            case .success(let url):
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let png = try CustomStatusIcon.importFile(url)
                    customIconData = png
                    statusIconStyleRaw = StatusIconStyle.custom.rawValue
                } catch {
                    iconImportError = appLanguage.localized(
                        chinese: "请选择不超过 8 MB 的有效 PNG 或 JPEG 图片。",
                        english: "Choose a valid PNG or JPEG image up to 8 MB.",
                        russian: "Выберите корректную картинку PNG или JPEG размером до 8 МБ."
                    )
                }
            case .failure:
                iconImportError = appLanguage.localized(chinese: "无法打开图片。", english: "Unable to open the image.", russian: "Не удалось открыть картинку.")
            }
        }
        .alert(appLanguage.localized(chinese: "无法导入图片", english: "Image import failed", russian: "Не удалось загрузить картинку"), isPresented: Binding(
            get: { iconImportError != nil }, set: { if !$0 { iconImportError = nil } }
        )) {
            Button("OK", role: .cancel) { iconImportError = nil }
        } message: { Text(iconImportError ?? "") }
        .padding(16)
        .frame(width: 560, height: 580)
        .onAppear {
            refreshSystemState()
            SettingsWindowPresenter.bringToFront()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshSystemState()
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                launchAtLoginControls
                Picker(appLanguage.localized(chinese: "语言", english: "Language", russian: "Язык"), selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Picker(appLanguage.localized(chinese: "最近任务数量", english: "Number of recent tasks", russian: "Недавних задач"), selection: recentConversationLimitBinding) {
                    ForEach(RecentConversationLimit.allCases) { limit in
                        Text(limit.title(for: appLanguage)).tag(limit)
                    }
                }
                ConversationCategoryOrderControl(order: conversationCategoryOrderBinding, language: appLanguage)
                Button {
                    DataHealthWindowPresenter.shared.show()
                } label: {
                    Label(DataHealthText.title(appLanguage), systemImage: "checkmark.icloud")
                }
            } header: {
                Text(appLanguage.localized(chinese: "日常使用", english: "Everyday use", russian: "Общие настройки"))
            } footer: {
                Text(appLanguage.localized(
                    chinese: "将指针移至屏幕顶部可查看最近任务。超过 5 条时可滚动查看，设为 0 时隐藏列表。",
                    english: "Hover over CodexNotch to view recent tasks. Scroll to see more than 5. Set to 0 to hide the list.",
                    russian: "Наведите указатель на CodexNotch, чтобы увидеть недавние чаты. Если их больше 5, прокрутите список. Значение 0 скрывает список."
                ))
            }

            Section {
                LabeledContent(appLanguage.localized(chinese: "当前版本", english: "Current version", russian: "Текущая версия"), value: currentVersion.displayValue)
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label(appLanguage.localized(chinese: "打开更新页面…", english: "Open Updates Page…", russian: "Открыть страницу обновлений…"), systemImage: "arrow.clockwise")
                }
                .disabled(!updater.canCheckForUpdates)
                if let error = updater.startupError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text(appLanguage.localized(chinese: "更新", english: "Updates", russian: "Обновления"))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var launchAtLoginControls: some View {
        Toggle(
            appLanguage.localized(chinese: "登录时启动", english: "Launch at login", russian: "Запускать при входе"),
            isOn: Binding(get: { launchAtLogin.isRequested }, set: { launchAtLogin.setEnabled($0) })
        )
        .help(appLanguage.localized(chinese: "登录 Mac 时自动启动 CodexNotch。", english: "Automatically launch CodexNotch when you log in to your Mac.", russian: "Автоматически запускать CodexNotch при входе в macOS."))

        if launchAtLogin.status == .requiresApproval {
            Text(appLanguage.localized(chinese: "需在系统设置中允许登录时启动。", english: "Approval in System Settings is required to launch at login.", russian: "Разрешите запуск при входе в Системных настройках."))
                .font(.callout).foregroundStyle(.secondary)
            Button(appLanguage.localized(chinese: "打开登录项设置…", english: "Open Login Items…", russian: "Открыть объекты входа…")) {
                launchAtLogin.openSystemSettings()
            }
        }
        if let error = launchAtLogin.errorMessage {
            Text(appLanguage.localized(chinese: "无法保存自动启动设置：\(error)", english: "Unable to save the launch-at-login setting: \(error)", russian: "Не удалось сохранить настройку автозапуска: \(error)"))
                .font(.callout).foregroundStyle(.red)
            if launchAtLogin.status == .notFound {
                Text(appLanguage.localized(chinese: "请将 CodexNotch 移至“应用程序”文件夹后重新打开。", english: "Move CodexNotch to the Applications folder, then reopen it.", russian: "Переместите CodexNotch в папку «Программы» и откройте снова."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSettings: some View {
        Form {
            Section {
                Picker(appLanguage.localized(chinese: "额度样式", english: "Quota style", russian: "Вид лимита"), selection: selectedStyleBinding) {
                    ForEach(QuotaDisplayStyle.allCases) { style in
                        Label(style.title(for: appLanguage), systemImage: style.systemImage).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                Picker(appLanguage.localized(chinese: "左侧显示", english: "Left side", russian: "Слева"), selection: statusIconStyleBinding) {
                    ForEach(StatusIconStyle.allCases) { style in
                        Label {
                            Text(style.title(for: appLanguage))
                        } icon: {
                            StatusMark(style: style, size: 16, tint: .primary)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                if statusIconStyleBinding.wrappedValue == .custom {
                    HStack {
                        Button(appLanguage.localized(chinese: "选择图片…", english: "Choose image…", russian: "Выбрать картинку…")) {
                            choosingIcon = true
                        }
                        if !customIconData.isEmpty {
                            Button(appLanguage.localized(chinese: "移除", english: "Remove", russian: "Удалить")) {
                                statusIconStyleRaw = StatusIconStyle.defaultStyle.rawValue
                                customIconData = Data()
                            }
                        }
                    }
                    Text(appLanguage.localized(chinese: "PNG 或 JPEG，最大 8 MB。图片保存在本机。", english: "PNG or JPEG, up to 8 MB. The image is saved locally.", russian: "PNG или JPEG до 8 МБ. Картинка хранится на этом Mac."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(appLanguage.localized(chinese: "顶部显示", english: "Top display", russian: "Панель вверху экрана"))
            } footer: {
                Text(appLanguage.localized(
                    chinese: "未启用宠物时，左侧优先显示 5 小时额度；选择“关闭”可隐藏该区域，额度仍可展开查看。已选宠物在刘海左侧使用独立区域。",
                    english: "Without a companion, five-hour quota takes priority on the left; Off hides that lane while keeping expanded quota details. A selected companion uses its own physical-notch wing.",
                    russian: "Без питомца слева приоритет у лимита на 5 часов; «Выкл.» скрывает эту область, сохраняя лимиты в карточке. Выбранный питомец использует своё левое крыло у выреза."
                ))
            }

            Section {
                Toggle(appLanguage.localized(chinese: "自定义颜色", english: "Custom color", russian: "Свой цвет"), isOn: $customQuotaColorEnabled)
                if customQuotaColorEnabled {
                    ColorPicker(appLanguage.localized(chinese: "额度与光效", english: "Quota and glow", russian: "Лимиты и подсветка"), selection: Binding(
                        get: { (QuotaAppearance.parse(customQuotaColorHex) ?? QuotaAppearance.defaultColor).color },
                        set: { if let hex = QuotaAppearance.hex(for: NSColor($0)) { customQuotaColorHex = hex } }
                    ), supportsOpacity: false)
                    Button(appLanguage.localized(chinese: "恢复默认颜色", english: "Restore default colors", russian: "Вернуть стандартные цвета")) {
                        customQuotaColorEnabled = false
                        customQuotaColorHex = QuotaAppearance.defaultHex
                    }
                }
            } header: {
                Text(appLanguage.localized(chinese: "颜色", english: "Color", russian: "Цвет"))
            } footer: {
                Text(appLanguage.localized(
                    chinese: "自定义颜色将替代绿色、黄色和红色额度提示。完成勾号保持绿色。",
                    english: "A custom color replaces the green, yellow and red quota colors. The completion check stays green.",
                    russian: "Свой цвет заменит зелёный, жёлтый и красный цвета лимита. Галочка завершения останется зелёной."
                ))
            }

            Section {
                Toggle(appLanguage.localized(chinese: "动画效果", english: "Animations", russian: "Анимация"), isOn: $animationsEnabled)
            } header: {
                Text(appLanguage.localized(chinese: "动画与性能", english: "Animations and performance", russian: "Анимация и производительность"))
            } footer: {
                Text(appLanguage.localized(
                    chinese: "关闭动画可减少开销，额度和任务状态照常更新。",
                    english: "Turn off animations to reduce resource use. Quota and task status keep updating.",
                    russian: "Отключите анимацию, чтобы снизить нагрузку. Лимиты и статусы задач продолжат обновляться."
                ))
            }
        }
        .formStyle(.grouped)
    }

    private var floatingSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(floatingContext.title(for: appLanguage), systemImage: "info.circle")
                        .font(.headline)
                    Text(floatingContext.explanation(for: appLanguage))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section {
                if selectedTab == .floating {
                    FloatingBarSettingsPreview(
                        style: floatingStyle, customText: floatingCenterText, state: previewState,
                        language: appLanguage, animationsEnabled: animationsEnabled
                    )
                    .environment(\.petCompanionContext, companion.atlas.flatMap { atlas in
                        companion.library.selectedPet.map { entry in
                            PetCompanionSceneContext(atlas: atlas, name: entry.name,
                                pose: previewState == .running ? .work : .idle, session: petPreviewSession)
                        }
                    })
                }
                Picker(appLanguage.localized(chinese: "预览状态", english: "Preview state", russian: "Состояние в примере"), selection: $previewState) {
                    ForEach(FloatingPreviewState.allCases) { state in
                        Text(state.title(for: appLanguage)).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text(appLanguage.localized(chinese: "效果预览", english: "Preview", russian: "Предпросмотр"))
            } footer: {
                if !animationsEnabled {
                    Text(appLanguage.localized(chinese: "动画已关闭，可在“外观”中开启。", english: "Animations are off. Enable them in Appearance.", russian: "Анимация отключена. Включить её можно во вкладке «Внешний вид»."))
                }
            }

            Section {
                Picker(appLanguage.localized(chinese: "中间样式", english: "Center style", russian: "В центре"), selection: Binding(
                    get: { floatingStyle }, set: { floatingCenterStyleRaw = $0.rawValue }
                )) {
                    ForEach(FloatingCenterStyle.allCases) { style in
                        Text(style.title(for: appLanguage)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if floatingStyle.usesCustomText {
                    FloatingCenterTextField(text: $floatingCenterText, language: appLanguage)
                }
            } header: {
                Text(appLanguage.localized(chinese: "中间样式", english: "Center style", russian: "В центре"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(floatingStyle.explanation(for: appLanguage))
                    if floatingStyle.usesCustomText {
                        Text(appLanguage.localized(chinese: "最多 12 个字符，留空时显示 Codex。", english: "Up to 12 characters. Leave blank to display Codex.", russian: "До 12 символов. Оставьте поле пустым, чтобы показывать Codex."))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func refreshSystemState() {
        launchAtLogin.refresh()
        layoutMode = NotchScreenMetrics.preferredScreen().map {
            NotchGeometry.layout(metrics: NotchScreenMetrics(screen: $0)).mode
        }
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(get: { appLanguage }, set: { appLanguageRaw = $0.rawValue })
    }

    private var currentVersion: AppVersion { AppVersion.fromBundle() ?? .zero }
}
