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
                Button(language.localized(chinese: "导入宠物库…", english: "Import companion library…", russian: "Импортировать библиотеку питомцев…")) {
                    choosingLibrary = true
                }
                .disabled(companion.isBusy)
                if companion.isBusy { ProgressView().controlSize(.small) }
                if companion.library.entries.isEmpty {
                    Text(language.localized(chinese: "导入本地宠物库文件夹，然后选择宠物。", english: "Import a local library folder, then choose a companion.", russian: "Импортируйте локальную папку библиотеки и выберите питомца."))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(language.localized(chinese: "岛上的伙伴", english: "Island companion", russian: "Питомец на островке"))
            } footer: {
                Text(language.localized(
                    chinese: "宠物始终显示在刘海左侧，5 小时额度与任务状态各有独立位置；展开卡片不显示宠物场景。浮动横条可选择“宠物”中央样式。关闭宠物后恢复原有左侧设置。",
                    english: "Your companion stays beside the left of the notch, with separate quota and status slots. Expanded cards have no companion scene. Floating Bar offers a Companion center style. Off restores your original left-side setting.",
                    russian: "Питомец постоянно виден слева от выреза, рядом с отдельными квотой и статусом. В раскрытой карточке сцены питомца нет. В плавающей панели есть стиль центра «Питомец». Выкл. возвращает прежнюю настройку левой стороны."
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
