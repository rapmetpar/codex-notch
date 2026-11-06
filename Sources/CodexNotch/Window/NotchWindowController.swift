import AppKit
import Foundation
import SwiftUI

enum NotchPanelFramePolicy {
    /// Keep content in its original screen coordinates while cropping the actual
    /// window. Otherwise narrowing one wing would move the surviving quota.
    static func hostingFrame(canvas: NSRect, contentCenterX: CGFloat?) -> NSRect {
        guard let centerX = contentCenterX else {
            return NSRect(origin: .zero, size: canvas.size)
        }
        let halfWidth = max(centerX - canvas.minX, canvas.maxX - centerX)
        return NSRect(x: centerX - halfWidth - canvas.minX, y: 0,
                      width: halfWidth * 2, height: canvas.height)
    }

    static func shouldSettleAfterCollapse(
        layoutMode: NotchLayoutMode
    ) -> Bool {
        layoutMode != .menuBarFallback
    }
}

final class NotchWindowController: NSWindowController {
    var onScreenParametersChanged: (() -> Void)?
    var onOpenThread: ((String) -> Void)?
    var onActivateChatGPT: (() -> Void)?

    private var localDismissMonitor: Any?
    private var globalDismissMonitor: Any?
    private var clickDismiss: (() -> Void)?
    private var screenObserver: NSObjectProtocol?

    func setClickDisclosureOpen(_ open: Bool, onDismiss: @escaping () -> Void) {
        guard let panel = window as? NotchPanel else { return }
        if let monitor = localDismissMonitor { NSEvent.removeMonitor(monitor); localDismissMonitor = nil }
        if let monitor = globalDismissMonitor { NSEvent.removeMonitor(monitor); globalDismissMonitor = nil }
        clickDismiss = open ? onDismiss : nil
        panel.onEscape = open ? onDismiss : nil
        panel.acceptsDisclosureKeys = open
        if !open { if panel.isKeyWindow { panel.resignKey() }; return }
        panel.makeKey()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleClickDisclosureMouseDown(at: NSEvent.mouseLocation)
            return event
        }
        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handleClickDisclosureMouseDown(at: NSEvent.mouseLocation)
        }
    }

    func handleClickDisclosureMouseDown(at point: NSPoint) {
        guard let frame = lastPreparedTargetFrame, !frame.contains(point) else { return }
        clickDismiss?()
    }

    func setHiddenSensorInteractive(_ interactive: Bool) {
        window?.ignoresMouseEvents = !interactive
    }
    private var hostingView: NSHostingView<AnyView>?
    private var statusItem: NSStatusItem?
    private var deferredFrameWorkItem: DispatchWorkItem?
    private var deferredFrameIdentifier: UUID?
    private var lastPreparedTargetFrame: NSRect?
    private var lastPreparedSettledFrame: NSRect?
    private var lastPreparedIsExpanded = false
    private(set) var isCardTransitionInFlight = false
    private var canvasTransitionIdentifier = UUID()
    private var awaitingSurfaceCompletion = false
    private var requestedLayoutMode: NotchLayoutMode = .menuBarFallback
    private var contentCenterX: CGFloat?

    private var appLanguage: AppLanguage {
        AppLanguage.fromStoredValue(
            AppPreferences.store.string(forKey: AppLanguage.storageKey)
        )
    }

    init() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1))
        super.init(window: panel)
        observeScreenChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeScreenChanges()
    }

    func setRootView<Content: View>(_ rootView: Content) {
        guard let panel = window as? NotchPanel else { return }
        let hostingView = NSHostingView(rootView: AnyView(rootView))
        // A hosting view used directly as window.contentView can drive animated
        // window sizing on macOS 26 even with sizingOptions disabled. A plain
        // AppKit canvas keeps panel geometry owned by this controller while
        // SwiftUI animates only the surface inside it.
        let canvas = NSView(frame: panel.contentView?.bounds ?? .zero)
        hostingView.sizingOptions = []
        hostingView.frame = canvas.bounds
        hostingView.autoresizingMask = []
        canvas.addSubview(hostingView)
        panel.contentView = canvas
        self.hostingView = hostingView
    }

    /// Atoll's motion model is intentional here: make room for the final panel
    /// first, then let SwiftUI animate the visible island inside that stable
    /// canvas. Repeatedly resizing an NSPanel during a SwiftUI layout pass is
    /// both visually rough and prone to re-entrant layout crashes.
    @discardableResult
    func prepare(
        layout: NotchLayout,
        state: NotchPresentationState,
        isHovering: Bool = false,
        animationsEnabled: Bool = AppAnimationPreference.defaultEnabled
    ) -> UUID {
        guard let panel = window as? NotchPanel else { return canvasTransitionIdentifier }

        if layout.mode == .menuBarFallback {
            hideNotchPanel()
            showFallbackMenu(for: state)
            return canvasTransitionIdentifier
        }

        requestedLayoutMode = layout.mode
        contentCenterX = layout.compactLeadingInset > 0 ? layout.centerX : nil
        hideFallbackMenu()
        let targetFrame = layout.frame(for: state)
        let isExpanded: Bool
        if case .expanded = state { isExpanded = true } else { isExpanded = false }
        let settledFrame = NotchPresentationMotion.settledCanvasFrame(
            for: targetFrame, isExpanded: isExpanded, isHovering: isHovering,
            animationsEnabled: animationsEnabled
        )
        let wasVisible = panel.isVisible
        let wasIgnoringMouseEvents = panel.ignoresMouseEvents
        let changesTarget = lastPreparedTargetFrame != targetFrame
            || lastPreparedSettledFrame != settledFrame
            || !wasVisible
            || (deferredFrameWorkItem == nil && !awaitingSurfaceCompletion && panel.frame != settledFrame)
        if changesTarget || !animationsEnabled {
            cancelDeferredFrameSettlement()
            canvasTransitionIdentifier = UUID()
            isCardTransitionInFlight = animationsEnabled && (isExpanded || lastPreparedIsExpanded)
        }
        lastPreparedTargetFrame = targetFrame
        lastPreparedSettledFrame = settledFrame
        lastPreparedIsExpanded = isExpanded
        let frame = changesTarget
            ? NotchPresentationMotion.canvasFrame(
                for: targetFrame, isExpanded: isExpanded, isHovering: isHovering, animationsEnabled: animationsEnabled
            )
            : (deferredFrameWorkItem == nil && !awaitingSurfaceCompletion ? settledFrame : panel.frame)

        let setsFrameImmediately = shouldSetFrameImmediately(
            from: panel.frame,
            to: frame,
            wasVisible: wasVisible
        )
        if setsFrameImmediately {
            applyCanvasFrame(frame)
        } else {
            updateHostingFrame()
        }
        panel.ignoresMouseEvents = false
        if wasVisible {
            // A periodic clock update does not need to reorder a panel that is
            // already visible. Workspace changes use the dedicated reassertion
            // path below, so preserving the z-order no longer wakes
            // WindowServer once per tick.
            if setsFrameImmediately || wasIgnoringMouseEvents {
                panel.orderFrontRegardless()
            }
        } else if !animationsEnabled {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        return canvasTransitionIdentifier
    }

    /// Once the SwiftUI surface has visibly collapsed, remove the unused clear
    /// canvas so it cannot intercept clicks outside the compact notch.
    func settleFrame(
        layout: NotchLayout,
        state: NotchPresentationState,
        animationsEnabled: Bool = AppAnimationPreference.defaultEnabled,
        animationWillComplete: Bool = false
    ) {
        guard NotchPanelFramePolicy.shouldSettleAfterCollapse(
            layoutMode: layout.mode
        ),
              let panel = window as? NotchPanel else {
            return
        }

        let targetFrame = lastPreparedSettledFrame ?? layout.frame(for: state)
        guard shouldDeferFrameSettlement(from: panel.frame, to: targetFrame) else {
            return
        }

        guard NotchPresentationMotion.shouldAnimateSurface(
            changesSurface: true,
            animationsEnabled: animationsEnabled
        ) else {
            cancelDeferredFrameSettlement()
            isCardTransitionInFlight = false
            applyCanvasFrame(targetFrame)
            return
        }

        if animationWillComplete {
            cancelDeferredFrameSettlement()
            awaitingSurfaceCompletion = true
            return
        }
        // Same-target clock updates must not finish an in-flight surface.
        guard !awaitingSurfaceCompletion else { return }

        // A clock/event refresh of the same target must not postpone settlement.
        guard deferredFrameWorkItem == nil else { return }

        let identifier = UUID()
        deferredFrameIdentifier = identifier
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.deferredFrameIdentifier == identifier else {
                return
            }
            self.applyCanvasFrame(targetFrame)
            self.isCardTransitionInFlight = false
            self.deferredFrameIdentifier = nil
            self.deferredFrameWorkItem = nil
        }
        deferredFrameWorkItem = workItem
        let delay: TimeInterval
        if case .expanded = state { delay = NotchPresentationMotion.expandDuration }
        else { delay = NotchPresentationMotion.collapseDuration }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    func finishSurfaceAnimation(identifier: UUID, targetFrame: NSRect) {
        guard identifier == canvasTransitionIdentifier,
              targetFrame == lastPreparedTargetFrame else { return }
        cancelDeferredFrameSettlement()
        isCardTransitionInFlight = false
        applyCanvasFrame(lastPreparedSettledFrame ?? targetFrame)
    }

    private func applyCanvasFrame(_ frame: NSRect) {
        guard let panel = window as? NotchPanel else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                panel.setFrame(frame, display: false)
                updateHostingFrame()
                // Resolve the old compact surface in the new canvas before
                // the caller starts a SwiftUI animation. Otherwise its old
                // local x coordinate is animated after the window moved left.
                panel.contentView?.layoutSubtreeIfNeeded()
                hostingView?.layoutSubtreeIfNeeded()
                panel.displayIfNeeded()
            }
        }
    }

    private func updateHostingFrame() {
        guard let panel = window else { return }
        hostingView?.frame = NotchPanelFramePolicy.hostingFrame(
            canvas: panel.frame, contentCenterX: contentCenterX
        )
    }

    private func shouldDeferFrameSettlement(from current: NSRect, to target: NSRect) -> Bool {
        let growsWidth = target.width > current.width + 0.5
        let growsHeight = target.height > current.height + 0.5
        let shrinksWidth = target.width < current.width - 0.5
        let shrinksHeight = target.height < current.height - 0.5
        return (shrinksWidth || shrinksHeight) && !(growsWidth || growsHeight)
    }

    private func cancelDeferredFrameSettlement() {
        deferredFrameWorkItem?.cancel()
        deferredFrameWorkItem = nil
        deferredFrameIdentifier = nil
        awaitingSurfaceCompletion = false
    }

    private func shouldSetFrameImmediately(
        from current: NSRect,
        to target: NSRect,
        wasVisible: Bool
    ) -> Bool {
        guard wasVisible else { return true }
        guard !current.equalTo(target) else { return false }

        let growsWidth = target.width > current.width + 0.5
        let growsHeight = target.height > current.height + 0.5
        let changesTopAttachment = abs(target.maxY - current.maxY) > 0.5
        return growsWidth || growsHeight || changesTopAttachment
    }

    func hideNotchPanel() {
        requestedLayoutMode = .menuBarFallback
        isCardTransitionInFlight = false
        lastPreparedIsExpanded = false
        lastPreparedSettledFrame = nil
        cancelDeferredFrameSettlement()
        canvasTransitionIdentifier = UUID()
        guard let panel = window as? NotchPanel else { return }
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    deinit {
        if let monitor = localDismissMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalDismissMonitor { NSEvent.removeMonitor(monitor) }
        cancelDeferredFrameSettlement()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenParametersChanged?()
        }
    }

    func reassertNotchPanelAfterApplicationSwitch(displayIsEnabled: Bool) {
        // AppKit can finish applying an app switch after the workspace
        // activation callback has already rendered the panel. Reassert on the
        // next main-loop turn so an accessory panel remains above normal
        // frontmost applications such as Feishu.
        DispatchQueue.main.async { [weak self] in
            self?.restoreNotchPanelAfterApplicationSwitch(
                displayIsEnabled: displayIsEnabled
            )
        }
    }

    func showDisplayDisabledFallback() {
        hideNotchPanel()
        showFallbackMenu(for: .hidden, includesShowNotchAction: true)
    }

    private func restoreNotchPanelAfterApplicationSwitch(displayIsEnabled: Bool) {
        guard NotchPanelVisibilityPolicy.shouldRestoreAfterApplicationSwitch(
            panelIsRequested: requestedLayoutMode != .menuBarFallback,
            layoutMode: requestedLayoutMode,
            displayIsEnabled: displayIsEnabled
        ), let panel = window as? NotchPanel else {
            return
        }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    private func showFallbackMenu(
        for state: NotchPresentationState,
        includesShowNotchAction: Bool = false
    ) {
        let statusItem = statusItem ?? makeStatusItem()
        statusItem.isVisible = true
        statusItem.button?.title = "Codex"
        statusItem.button?.toolTip = "CodexNotch"

        let menu = NSMenu()
        menu.autoenablesItems = false
        switch state {
        case .hidden:
            let title = includesShowNotchAction
                ? appLanguage.localized(chinese: "CodexNotch 已隐藏", english: "CodexNotch hidden", russian: "CodexNotch скрыт")
                : "CodexNotch"
            menu.addItem(disabledItem(title: title))

        case let .quotaCompact(usage):
            menu.addItem(disabledItem(title: "Codex · \(NotchText.quotaSubtitle(usage: usage, language: appLanguage))"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(actionItem(
                title: appLanguage.localized(chinese: "打开 ChatGPT", english: "Open ChatGPT", russian: "Открыть ChatGPT"),
                representedObject: "__activate__"
            ))

        case let .workingCompact(primary, count, usage):
            let title = count > 1
                ? appLanguage.localized(
                    chinese: "Codex 正在运行 · \(count) 个任务",
                    english: "Codex running · \(count) tasks",
                    russian: "Codex работает · задач: \(count)"
                )
                : appLanguage.localized(chinese: "Codex 正在运行", english: "Codex running", russian: "Codex работает")
            menu.addItem(disabledItem(title: title))
            menu.addItem(disabledItem(
                title: NotchText.sessionSubtitle(primary, now: .now, language: appLanguage)
            ))
            if let usage, !usage.windows.isEmpty {
                menu.addItem(disabledItem(
                    title: NotchText.quotaSubtitle(usage: usage, language: appLanguage)
                ))
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(actionItem(
                title: appLanguage.localized(chinese: "打开当前任务", english: "Open current task", russian: "Открыть текущую задачу"),
                representedObject: primary.threadID
            ))

        case let .completedCompact(session, usage):
            menu.addItem(disabledItem(
                title: appLanguage.localized(chinese: "Codex 已完成", english: "Codex completed", russian: "Codex завершил работу")
            ))
            if let usage, !usage.windows.isEmpty {
                menu.addItem(disabledItem(
                    title: NotchText.quotaSubtitle(usage: usage, language: appLanguage)
                ))
            }
            menu.addItem(actionItem(
                title: appLanguage.localized(
                    chinese: "打开 \(NotchText.projectName(cwd: session.cwd, language: appLanguage))",
                    english: "Open \(NotchText.projectName(cwd: session.cwd, language: appLanguage))",
                    russian: "Открыть \(NotchText.projectName(cwd: session.cwd, language: appLanguage))"
                ),
                representedObject: session.threadID
            ))

        case let .expanded(content):
            let headerTitle: String
            if !content.conversations.isEmpty {
                headerTitle = appLanguage.localized(
                    chinese: "Codex 最近对话",
                    english: "Codex recent conversations",
                    russian: "Недавние чаты Codex"
                )
            } else if !content.sessions.isEmpty || content.headerConversation != nil {
                headerTitle = appLanguage.localized(
                    chinese: "Codex 活动",
                    english: "Codex activity",
                    russian: "Активность Codex"
                )
            } else {
                headerTitle = appLanguage.localized(chinese: "Codex 额度", english: "Codex quota", russian: "Лимиты Codex")
            }
            menu.addItem(disabledItem(title: headerTitle))
            if let usage = content.usage,
               !usage.resetCredits.isEmpty {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(disabledItem(title: appLanguage.localized(
                    chinese: "使用限额重置",
                    english: "Usage reset",
                    russian: "Сброс лимита"
                )))
                for credit in usage.resetCredits {
                    menu.addItem(disabledItem(
                        title: "\(NotchText.resetCreditTitle(credit, language: appLanguage)) · \(NotchText.resetCreditExpiry(credit, language: appLanguage))"
                    ))
                }
            }
            if !content.conversations.isEmpty {
                menu.addItem(NSMenuItem.separator())
                for conversation in content.conversations {
                    menu.addItem(actionItem(
                        title: conversation.title
                            ?? NotchText.projectName(cwd: conversation.cwd, language: appLanguage),
                        representedObject: conversation.threadID
                    ))
                }
            } else if !content.sessions.isEmpty {
                menu.addItem(disabledItem(title: appLanguage.localized(
                    chinese: "Codex 正在运行",
                    english: "Codex running",
                    russian: "Codex работает"
                )))
                menu.addItem(NSMenuItem.separator())
                for session in content.sessions {
                    menu.addItem(actionItem(
                        title: appLanguage.localized(
                            chinese: "打开 \(NotchText.projectName(cwd: session.cwd, language: appLanguage))",
                            english: "Open \(NotchText.projectName(cwd: session.cwd, language: appLanguage))",
                            russian: "Открыть \(NotchText.projectName(cwd: session.cwd, language: appLanguage))"
                        ),
                        representedObject: session.threadID
                    ))
                }
            } else if let conversation = content.headerConversation {
                menu.addItem(disabledItem(title: appLanguage.localized(
                    chinese: "Codex 已完成",
                    english: "Codex completed",
                    russian: "Codex завершил работу"
                )))
                menu.addItem(NSMenuItem.separator())
                menu.addItem(actionItem(
                    title: appLanguage.localized(
                        chinese: "打开 \(NotchText.projectName(cwd: conversation.cwd, language: appLanguage))",
                        english: "Open \(NotchText.projectName(cwd: conversation.cwd, language: appLanguage))",
                        russian: "Открыть \(NotchText.projectName(cwd: conversation.cwd, language: appLanguage))"
                    ),
                    representedObject: conversation.threadID
                ))
            } else {
                if let usage = content.usage, !usage.windows.isEmpty {
                    for window in usage.windows {
                        menu.addItem(disabledItem(
                            title: NotchText.compactWindow(window, language: appLanguage)
                        ))
                    }
                } else {
                    menu.addItem(disabledItem(title: appLanguage.localized(
                        chinese: "额度暂不可用",
                        english: "Quota unavailable",
                        russian: "Лимит недоступен"
                    )))
                }
                menu.addItem(NSMenuItem.separator())
                menu.addItem(actionItem(
                    title: appLanguage.localized(chinese: "打开 ChatGPT", english: "Open ChatGPT", russian: "Открыть ChatGPT"),
                    representedObject: "__activate__"
                ))
            }
        }
        if includesShowNotchAction {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(actionItem(
                title: appLanguage.localized(
                    chinese: "显示刘海 (⌥⌘N)",
                    english: "Show notch (⌥⌘N)",
                    russian: "Показать панель (⌥⌘N)"
                ),
                representedObject: "__show_notch__"
            ))
        }
        statusItem.menu = menu
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        return item
    }

    private func hideFallbackMenu() {
        statusItem?.isVisible = false
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(title: String, representedObject: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(handleStatusItemAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = representedObject
        return item
    }

    @objc private func handleStatusItemAction(_ sender: NSMenuItem) {
        guard let representedObject = sender.representedObject as? String else { return }
        if representedObject == "__show_notch__" {
            AppPreferences.store.set(
                true,
                forKey: NotchDisplayPreference.storageKey
            )
        } else if representedObject == "__activate__" {
            onActivateChatGPT?()
        } else {
            onOpenThread?(representedObject)
        }
    }
}
