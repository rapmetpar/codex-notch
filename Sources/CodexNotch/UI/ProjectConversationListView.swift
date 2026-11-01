import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let codexNotchProject = UTType(exportedAs: "app.codexnotch.project-order", conformingTo: .data)
}

/// Carries no project path, title, native ID or thread data outside the app.
struct ProjectDragToken: Codable, Transferable, Equatable {
    let id: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .codexNotchProject).visibility(.ownProcess)
    }
}

struct ProjectHeadingDragPreview: View {
    let title: String
    var body: some View {
        Label(title, systemImage: "folder")
            .font(.system(size: 12, weight: .medium))
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Shared by the actual island and synthetic previews; quota/footer stay outside.
struct ProjectConversationListView: View {
    let content: ExpandedContent
    let now: Date
    let language: AppLanguage
    let onOpenThread: (String) -> Void
    let onDropProjects: ([ProjectDragToken], String) -> Bool
    let onMoveProject: (String, Int) -> Void
    @State private var targetedProjectID: String?

    private var fullIDs: [String] {
        content.allProjectIDs.isEmpty ? content.projectSections.map(\.id) : content.allProjectIDs
    }

    var body: some View {
        let height = NotchExpandedLayout.conversationListHeight(
            conversationCount: content.conversations.count, projectCount: content.projectSections.count)
        Group {
            if NotchExpandedLayout.projectListNeedsScroll(conversationCount: content.conversations.count,
                                                        projectCount: content.projectSections.count) {
                ScrollView(.vertical) { rows }
            } else {
                rows
            }
        }
        .frame(height: height, alignment: .top)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(content.projectSections) { section in
                heading(section)
                ForEach(section.conversations, id: \.threadID) { conversation in
                    ConversationRowView(conversation: conversation, now: now, language: language,
                                        action: { onOpenThread(conversation.threadID) })
                }
            }
        }
    }

    private func heading(_ section: ConversationProjectSection) -> some View {
        HStack(spacing: 5) {
            // Only headings are draggable; row clicks retain their navigation behavior.
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10))
                Text(section.title(language: language)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .semibold))
            .contentShape(Rectangle())
            .draggable(ProjectDragToken(id: section.id)) {
                ProjectHeadingDragPreview(title: section.title(language: language))
            }
            .accessibilityLabel(section.title(language: language))
            .accessibilityHint(language.localized(chinese: "拖动以调整项目优先级", english: "Drag to prioritize projects", russian: "Перетащите для изменения порядка проектов"))
            moveButton(section, offset: -1)
            moveButton(section, offset: 1)
        }
        .foregroundStyle(NotchPalette.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: NotchExpandedLayout.projectHeaderHeight)
        .background(targetedProjectID == section.id ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .dropDestination(for: ProjectDragToken.self) { items, _ in
            onDropProjects(items, section.id)
        } isTargeted: { targeted in
            if targeted { targetedProjectID = section.id }
            else if targetedProjectID == section.id { targetedProjectID = nil }
        }
        .accessibilityElement(children: .contain)
    }

    private func moveButton(_ section: ConversationProjectSection, offset: Int) -> some View {
        let index = fullIDs.firstIndex(of: section.id) ?? 0
        let title = language.localized(
            chinese: "将\(section.title(language: language))向\(offset < 0 ? "上" : "下")移动",
            english: "Move \(section.title(language: language)) \(offset < 0 ? "up" : "down")",
            russian: "Переместить \(section.title(language: language)) \(offset < 0 ? "выше" : "ниже")")
        return ProjectMoveButton(symbol: offset < 0 ? "chevron.up" : "chevron.down", title: title,
            enabled: fullIDs.indices.contains(index + offset), action: { onMoveProject(section.id, offset) })
            .frame(width: 24, height: 24)
            .disabled(!fullIDs.indices.contains(index + offset))
    }
}

/// Synthetic scene for layout/drag-preview inspection; no account assets or data.
struct ProjectIslandScenePreview: View {
    @ObservedObject var model: NotchViewModel
    var body: some View { NotchView(model: model) }
}

/// Real AppKit button retains an independent accessibility action on non-key panels.
struct ProjectMoveButton: NSViewRepresentable {
    let symbol: String
    let title: String
    let enabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = ProjectMoveNSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.press)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        button.contentTintColor = NSColor(white: 0.65, alpha: 1)
        button.isEnabled = enabled && context.environment.isEnabled
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }
    final class Coordinator: NSObject {
        var action: () -> Void = {}
        @objc func press() { action() }
    }
}

final class ProjectMoveNSButton: NSButton {
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let action else { return false }
        return sendAction(action, to: target)
    }
}
