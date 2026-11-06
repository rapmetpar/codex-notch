import SwiftUI
import UniformTypeIdentifiers

struct PetCompanionSettingsView: View {
    @ObservedObject var companion: PetCompanionController
    let language: AppLanguage
    @State private var choosingLibrary = false

    var body: some View {
        Form {
            Section {
                Picker(language.localized(chinese: "宠物", english: "Companion", russian: "Питомец"), selection: Binding(
                    get: { companion.library.selectedPetID ?? "" },
                    set: { companion.select($0.isEmpty ? nil : $0) }
                )) {
                    Text(language.localized(chinese: "关闭", english: "Off", russian: "Выкл.")).tag("")
                    ForEach(companion.library.entries) { entry in Text(entry.name).tag(entry.id) }
                }
                .disabled(companion.isBusy)
                .settingsSearchTarget(.companion)
                Button(language.localized(chinese: "导入宠物库…", english: "Import companion library…", russian: "Импортировать библиотеку питомцев…")) {
                    choosingLibrary = true
                }
                .disabled(companion.isBusy)
                .settingsSearchTarget(.importCompanions)
                if companion.isBusy { ProgressView().controlSize(.small) }
                if companion.library.entries.isEmpty {
                    Text(language.localized(chinese: "导入本地宠物库文件夹，然后选择宠物。", english: "Import a local library folder, then choose a companion.", russian: "Импортируйте локальную папку библиотеки и выберите питомца."))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(language.localized(chinese: "岛上的伙伴", english: "Island companion", russian: "Питомец на островке"))
            } footer: {
                Text(language.localized(
                    chinese: "宠物、可用的 5 小时额度与完成标记在刘海左侧同一位置淡入淡出，不增加岛的宽度。关闭动画时优先静态显示额度，任务状态仍可通过提示和详细信息查看。浮动横条可选择“宠物”中央样式。关闭宠物后恢复原有左侧设置。",
                    english: "Your companion, available five-hour quota and completed check fade through the same left slot without widening the island. With motion off, quota stays static; task state remains in the tooltip and details. Floating Bar offers a Companion center style. Off restores your original left-side setting.",
                    russian: "Питомец, доступная квота на 5 часов и галочка завершения плавно сменяются в одном месте слева, без расширения островка. Без анимации квота статична; статус доступен в подсказке и подробностях. В плавающей панели есть стиль центра «Питомец». Выкл. возвращает прежнюю настройку левой стороны."
                ))
            }
            Section {
                Text(language.localized(
                    chinese: "工作时专注，新任务完成时跳跃，空闲时偶尔散步。宠物同时遵循应用动画开关和系统“减弱动态效果”。显示宠物或悬停不会将聊天标为已读。",
                    english: "Works while tasks run, jumps for a new completion, and occasionally strolls at rest. Companion motion respects both Animations and system Reduce Motion. Showing or greeting a companion never marks chats as read.",
                    russian: "Во время работы занят делом, радуется новому завершению и иногда гуляет в покое. Учитывает переключатель анимации и системное уменьшение движения. Показ питомца и наведение не отмечают чаты прочитанными."
                )).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingLibrary, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { companion.importLibrary(from: url) }
        }
        .alert(language.localized(chinese: "无法载入宠物库", english: "Unable to load companion library", russian: "Не удалось загрузить библиотеку"), isPresented: $companion.hasError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(language.localized(chinese: "请选择包含有效 manifest.json 和图集的本地文件夹。现有选择保留。", english: "Choose a local folder with a valid manifest.json and sprite atlases. Your existing selection is retained.", russian: "Выберите локальную папку с корректным manifest.json и атласами. Текущий выбор сохранён."))
        }
    }
}
