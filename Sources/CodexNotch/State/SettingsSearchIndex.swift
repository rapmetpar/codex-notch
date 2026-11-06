import Foundation

enum SettingsTab: String, CaseIterable {
    case general, appearance, pets, floating

    func title(for language: AppLanguage) -> String {
        switch self {
        case .general: return language.localized(chinese: "通用", english: "General", russian: "Основные")
        case .appearance: return language.localized(chinese: "外观", english: "Appearance", russian: "Внешний вид")
        case .pets: return language.localized(chinese: "宠物", english: "Companions", russian: "Питомцы")
        case .floating: return language.localized(chinese: "浮动横条", english: "Floating Bar", russian: "Плавающая панель")
        }
    }
}

/// Only static UI metadata belongs here. Never pass preference values, filenames,
/// companion names, signatures or runtime services into the search index.
enum SettingsSearchID: String, CaseIterable, Identifiable {
    case launchAtLogin, language, recentTasks, categoryOrder, updates
    case quotaStyle, statusIcon, quotaColor, animations
    case companion, importCompanions, floatingPreview, floatingCenter

    var id: String { rawValue }
    var tab: SettingsTab {
        switch self {
        case .launchAtLogin, .language, .recentTasks, .categoryOrder, .updates: return .general
        case .quotaStyle, .statusIcon, .quotaColor, .animations: return .appearance
        case .companion, .importCompanions: return .pets
        case .floatingPreview, .floatingCenter: return .floating
        }
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .launchAtLogin: return language.localized(chinese: "登录时启动", english: "Launch at login", russian: "Запускать при входе")
        case .language: return language.localized(chinese: "语言", english: "Language", russian: "Язык")
        case .recentTasks: return language.localized(chinese: "最近任务数量", english: "Number of recent tasks", russian: "Недавних задач")
        case .categoryOrder: return language.localized(chinese: "对话分类顺序", english: "Chat category order", russian: "Порядок категорий чатов")
        case .updates: return language.localized(chinese: "打开更新页面…", english: "Open Updates Page…", russian: "Открыть страницу обновлений…")
        case .quotaStyle: return language.localized(chinese: "额度样式", english: "Quota style", russian: "Вид лимита")
        case .statusIcon: return language.localized(chinese: "左侧显示与图片", english: "Left side and image", russian: "Слева: значок и картинка")
        case .quotaColor: return language.localized(chinese: "自定义颜色", english: "Custom color", russian: "Свой цвет")
        case .animations: return language.localized(chinese: "动画效果", english: "Animations", russian: "Анимация")
        case .companion: return language.localized(chinese: "宠物", english: "Companion", russian: "Питомец")
        case .importCompanions: return language.localized(chinese: "导入宠物库…", english: "Import companion library…", russian: "Импортировать библиотеку питомцев…")
        case .floatingPreview: return language.localized(chinese: "预览状态", english: "Preview state", russian: "Состояние в примере")
        case .floatingCenter: return language.localized(chinese: "中间样式与自定义文字", english: "Center style and custom text", russian: "Стиль центра и свой текст")
        }
    }

    private var keywords: String {
        switch self {
        case .launchAtLogin: return "startup automatic launch login автозапуск вход запуск 开机 自动 登录"
        case .language: return "locale english russian chinese язык русский английский китайский 语言 中文 英文 俄语"
        case .recentTasks: return "recent limit chats count history number hide недавние чаты чатов число количество лимит история скрыть 最近 聊天 任务 数量 历史 隐藏"
        case .categoryOrder: return "reorder categories running unread viewed порядок категории работа непрочитанные просмотренные 分类 顺序 运行 未读 已读"
        case .updates: return "update version release обновления версия релиз 更新 版本"
        case .quotaStyle: return "quota ring wave ball лимит квота кольцо волна шар 额度 圆环 波浪 水球"
        case .statusIcon: return "icon image picture custom import left off значок картинка изображение импорт слева выключить 图标 图片 自定义 导入 左侧 关闭"
        case .quotaColor: return "color colour glow reset palette цвет подсветка палитра сброс 颜色 光效 恢复"
        case .animations: return "motion animation performance effects анимация движение производительность эффекты 动画 动效 性能"
        case .companion: return "pet companion select off питомец выбор выключить 宠物 选择 关闭"
        case .importCompanions: return "pet pets import companion library folder импорт питомца питомцев библиотека папка 导入 宠物 宠物库 文件夹"
        case .floatingPreview: return "floating bar preview sample running idle completed панель предпросмотр пример состояние 浮动 横条 预览 状态"
        case .floatingCenter: return "floating bar center signature text elapsed orbit flow pet панель центр подпись текст время орбита поток питомец 浮动 横条 中间 签名 文字 计时 轨道 流光 宠物"
        }
    }

    var searchText: String {
        Self.normalize((AppLanguage.allCases.map { title(for: $0) + " " + tab.title(for: $0) } + [keywords]).joined(separator: " "))
    }

    fileprivate static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum SettingsSearchIndex {
    static func results(for query: String) -> [SettingsSearchID] {
        let terms = SettingsSearchID.normalize(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return [] }
        return SettingsSearchID.allCases.filter { item in terms.allSatisfy { item.searchText.contains($0) } }
    }
}

/// Transient navigation only: there are no preference bindings or action closures.
struct SettingsSearchState {
    struct Request: Equatable {
        let target: SettingsSearchID
        let token = UUID()
    }

    var query = ""
    var selectedTab = SettingsTab.general {
        didSet {
            if oldValue != selectedTab { request = nil }
        }
    }
    private(set) var request: Request?
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var results: [SettingsSearchID] { SettingsSearchIndex.results(for: query) }

    @discardableResult
    mutating func select(_ target: SettingsSearchID) -> Bool {
        guard results.contains(target) else { return false }
        selectedTab = target.tab
        request = Request(target: target)
        query = ""
        return true
    }

    @discardableResult
    mutating func submit() -> Bool {
        guard let first = results.first else { return false }
        return select(first)
    }

    mutating func clear() { query = "" }
    mutating func dismiss() { query = ""; request = nil }
}
