import SwiftUI

struct ConversationRowView: View {
    let conversation: ConversationSummary
    let now: Date
    let language: AppLanguage
    let action: () -> Void

    private var attention: ConversationAttention { conversation.attention }
    private var tint: Color {
        switch attention {
        case .running: return NotchPalette.accent
        case .unread: return NotchPalette.success
        case .viewed: return NotchPalette.secondaryText
        }
    }
    private var title: String {
        conversation.title ?? NotchText.projectName(cwd: conversation.cwd, language: language)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if conversation.outcome == .interrupted || conversation.outcome == .unknown {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NotchPalette.secondaryText)
                    } else if attention == .viewed {
                        Image(systemName: attention.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                    } else {
                        ConversationStatusView(activity: conversation.activity)
                    }
                }
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: attention == .unread ? .semibold : .regular))
                        .foregroundStyle(NotchPalette.primaryText.opacity(attention == .viewed ? 0.76 : 1))
                        .lineLimit(1)
                    Text(metadataText)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(NotchPalette.secondaryText)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(attention.label(language: language))
                    .font(.system(size: 10, weight: attention == .viewed ? .regular : .medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(tint.opacity(attention == .viewed ? 0 : 0.13), in: Capsule())
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background(tint.opacity(attention == .unread ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(ConversationRowButtonStyle())
        .help("\(title)\n\(conversation.outcome?.explanation(language: language).appending("\n") ?? "")\(attention.hint(language: language))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(attention.label(language: language)), \(metadataText)")
        .accessibilityHint("\(conversation.outcome?.explanation(language: language).appending(". ") ?? "")\(attention.hint(language: language))")
    }

    var metadataText: String {
        let project = NotchText.projectName(cwd: conversation.cwd, language: language)
        switch conversation.activity {
        case let .running(startedAt):
            return "\(NotchText.formatDuration(seconds: max(0, now.timeIntervalSince(startedAt)))) · \(project)"
        case let .completed(completedAt):
            return "\(conversation.outcome?.label(language: language).appending(" · ") ?? "")\(NotchText.relativeTime(from: completedAt, now: now, language: language)) · \(project)"
        }
    }
}

extension ConversationAttention {
    var symbolName: String {
        switch self {
        case .running: return "waveform"
        case .unread: return "circle.inset.filled"
        case .viewed: return "checkmark"
        }
    }
}

private struct ConversationRowButtonStyle: ButtonStyle {
    @Environment(\.notchMotionEnabled) private var motionEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.white.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.06 : 0)),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .onHover { isHovered = $0 }
            .animation(motionEnabled ? .easeOut(duration: 0.12) : nil, value: isHovered)
    }
}
