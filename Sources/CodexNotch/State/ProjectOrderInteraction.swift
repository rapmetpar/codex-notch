import Foundation

extension NotchViewModel {
    private var projectIDs: [String] {
        guard case let .expanded(content) = state else { return [] }
        return content.allProjectIDs.isEmpty ? content.projectSections.map(\.id) : content.allProjectIDs
    }

    /// The actual drop destination routes here, sharing validation with keyboard buttons.
    @discardableResult
    func dropProjects(_ tokens: [ProjectDragToken], onto target: String) -> Bool {
        let ids = projectIDs
        guard tokens.count == 1, let source = tokens.first?.id,
              ConversationProject.isValidID(source), ConversationProject.isValidID(target),
              source != target, ids.contains(source), ids.contains(target) else { return false }
        guard let targetIndex = ids.firstIndex(of: target) else { return false }
        var next = ids.filter { $0 != source }
        next.insert(source, at: targetIndex)
        guard next != ids else { return false }
        onProjectOrderChange(next)
        return true
    }

    func moveProject(_ id: String, by offset: Int) {
        var ids = projectIDs
        guard [-1, 1].contains(offset), let index = ids.firstIndex(of: id),
              ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        onProjectOrderChange(ids)
    }

}
