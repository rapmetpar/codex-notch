import AppKit
import Foundation

struct CodexHomeLocator {
    static func home(
        environment: [String: String],
        homeDirectory: URL
    ) -> URL {
        environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }
}

final class NotchRuntimeCoordinator {
    // Events publish state immediately. This tick advances whole-second clocks
    // and performs stale-state cleanup without a faster idle polling loop.
    static let sessionPollInterval: TimeInterval = 1
    // Recovery only stats unchanged files; normal events read just changed paths.
    static let rolloutRescanInterval: TimeInterval = 5
    static let usageRefreshInterval: TimeInterval = 60
    static let titleRefreshInterval: TimeInterval = 15
    static let hoverExpandDelay: TimeInterval = 0.18
    static let hoverCollapseDelay: TimeInterval = 0.12

    private let windowController: NotchWindowController
    private let frontmostMonitor: FrontmostAppMonitor
    private let threadNavigator: CodexThreadNavigator
    private let authReader: CodexAuthReader
    private let sessionStore: ActiveSessionStore
    private let threadProjectReader: ThreadProjectReading
    private let projectOrderStore: ConversationProjectOrderStore
    private var threadProjects: [String: NativeThreadProject] = [:]
    private var metadataGeneration: UInt64 = 0
    private let threadTitleReader: ThreadTitleReading
    private let rolloutMonitor: RolloutActivityMonitor
    private let urlSession: URLSession
    private let usageEndpoint: URL
    private let nowProvider: () -> Date
    private let userDefaults: UserDefaults
    private let conversationReadStore: ConversationReadStore
    private let compactCompletionStore: CompactCompletionStore
    private let nativeReadMonitor: NativeConversationReadMonitor
    private let searchWindow = ConversationSearchWindow()
    private var searchObserver: NSObjectProtocol?
    private let viewModel: NotchViewModel
    private let titleReadQueue = DispatchQueue(
        label: "com.david.codexnotch.thread-title-read",
        qos: .utility
    )

    private var sessionTimer: Timer?
    private var rolloutRescanTimer: Timer?
    private var usageTask: Task<Void, Never>?
    private var started = false
    private var isChatGPTFrontmost = false
    private var isHovered = false
    private var isPointerInside = false
    private var isResetScheduleExpanded = false
    private var activeSessions: [SessionActivity] = []
    private var recentCompletions: [CompletedSession] = []
    private var lastSessionSnapshot: ActiveSessionStoreSnapshot?
    private var snapshotRequestSequence: UInt64 = 0
    private var lastAppliedSnapshotSequence: UInt64 = 0
    private var threadTitles: [String: String] = [:]
    private var lastTitleRefreshAt: Date?
    private var titleRefreshInFlight = false
    private var usage: UsageSnapshot?
    private var lastUsageRequestAt: Date?
    private var usageRequestID: UUID?
    private var hoverExpandWorkItem: DispatchWorkItem?
    private var hoverCollapseWorkItem: DispatchWorkItem?
    private var preferencesObserver: NSObjectProtocol?
    private var lastObservedPreferences: NotchRuntimePreferences?
    private var visibilityShortcut: NotchVisibilityShortcut?

    init(
        windowController: NotchWindowController = NotchWindowController(),
        frontmostMonitor: FrontmostAppMonitor = FrontmostAppMonitor(),
        threadNavigator: CodexThreadNavigator = CodexThreadNavigator(),
        authReader: CodexAuthReader = CodexAuthReader(),
        sessionStore: ActiveSessionStore = ActiveSessionStore(),
        threadTitleReader: ThreadTitleReading? = nil,
        threadProjectReader: ThreadProjectReading? = nil,
        nativeReadReader: NativeConversationReadReading? = nil,
        urlSession: URLSession = .shared,
        usageEndpoint: URL = CodexUsageClient.defaultEndpoint,
        nowProvider: @escaping () -> Date = { .now },
        userDefaults: UserDefaults = AppPreferences.store
    ) {
        self.windowController = windowController
        self.frontmostMonitor = frontmostMonitor
        self.threadNavigator = threadNavigator
        self.authReader = authReader
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        self.usageEndpoint = usageEndpoint
        self.nowProvider = nowProvider
        self.userDefaults = userDefaults
        self.conversationReadStore = ConversationReadStore(defaults: userDefaults)
        self.compactCompletionStore = CompactCompletionStore(defaults: userDefaults)
        self.projectOrderStore = ConversationProjectOrderStore(defaults: userDefaults)
        self.viewModel = NotchViewModel()

        let codexHome = CodexHomeLocator.home(
            environment: authReader.environment,
            homeDirectory: authReader.homeDirectory
        )
        self.threadTitleReader = threadTitleReader ?? CodexThreadTitleReader(codexHomeURL: codexHome)
        self.threadProjectReader = threadProjectReader ?? CodexThreadProjectReader(codexHomeURL: codexHome)
        if let nativeReadReader {
            self.nativeReadMonitor = NativeConversationReadMonitor(reader: nativeReadReader)
        } else {
            self.nativeReadMonitor = NativeConversationReadMonitor(snapshotReader: NativeThreadReadSnapshotReader(codexHomeURL: codexHome))
        }
        self.rolloutMonitor = RolloutActivityMonitor(
            rootURL: codexHome.appendingPathComponent("sessions", isDirectory: true),
            store: sessionStore
        )
    }

    func start() {
        guard !started else { return }
        started = true
        observePreferenceChanges()
        searchWindow.model.onOpen = { [weak self] id in self?.openThread(id) }
        searchObserver = NotificationCenter.default.addObserver(forName: .openConversationSearch, object: nil, queue: .main) { [weak self] _ in
            self?.showConversationSearch()
        }
        visibilityShortcut = NotchVisibilityShortcut { [weak self] in
            self?.toggleNotchDisplay()
        }

        viewModel.onProjectOrderChange = { [weak self] ids in
            guard let self, self.projectOrderStore.prioritize(ids) else { return }
            self.render()
        }
        viewModel.onOpenThread = { [weak self] threadID in
            self?.openThread(threadID)
        }
        viewModel.onActivateChatGPT = { [weak self] in
            self?.activateChatGPT()
        }
        viewModel.onHoverChanged = { [weak self] hovered in
            self?.setHovered(hovered)
        }
        viewModel.onResetScheduleExpandedChanged = { [weak self] isExpanded in
            self?.setResetScheduleExpanded(isExpanded)
        }

        windowController.onScreenParametersChanged = { [weak self] in
            self?.render()
        }
        windowController.onOpenThread = { [weak self] threadID in
            self?.openThread(threadID)
        }
        windowController.onActivateChatGPT = { [weak self] in
            self?.activateChatGPT()
        }
        windowController.setRootView(NotchView(model: viewModel).defaultAppStorage(userDefaults))

        frontmostMonitor.onChange = { [weak self] isFrontmost in
            DispatchQueue.main.async {
                self?.setChatGPTFrontmost(isFrontmost)
            }
        }
        frontmostMonitor.start()
        rolloutMonitor.onChange = { [weak self] in
            guard let self, self.started else { return }
            self.pollSessions()
        }
        rolloutMonitor.onNewCompletions = { [weak self] completions in
            guard let self, self.started else { return }
            self.compactCompletionStore.record(completions)
        }
        rolloutMonitor.start()
        nativeReadMonitor.onChange = { [weak self] in
            guard let self, self.started else { return }
            self.render()
        }
        nativeReadMonitor.start()

        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: Self.sessionPollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.handleTimerTick()
        }
        rolloutRescanTimer = Timer.scheduledTimer(
            withTimeInterval: Self.rolloutRescanInterval,
            repeats: true
        ) { [weak self] _ in
            self?.rolloutMonitor.rescan()
        }

        refreshUsage()
        pollSessions()
        render()
    }

    func stop() {
        if let searchObserver { NotificationCenter.default.removeObserver(searchObserver); self.searchObserver = nil }
        searchWindow.close()
        guard started else { return }
        started = false
        metadataGeneration &+= 1
        threadProjects = [:]
        lastTitleRefreshAt = nil

        sessionTimer?.invalidate()
        sessionTimer = nil
        rolloutRescanTimer?.invalidate()
        rolloutRescanTimer = nil
        usageTask?.cancel()
        usageTask = nil
        usageRequestID = nil
        hoverExpandWorkItem?.cancel()
        hoverExpandWorkItem = nil
        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
        visibilityShortcut = nil
        stopObservingPreferenceChanges()
        isPointerInside = false
        isHovered = false
        isResetScheduleExpanded = false

        frontmostMonitor.stop()
        rolloutMonitor.stop()
        nativeReadMonitor.stop()
        viewModel.update(
            state: .hidden,
            now: nowProvider(),
            animationsEnabled: animationsEnabled
        )
        windowController.hideNotchPanel()
    }

    deinit {
        sessionTimer?.invalidate()
        rolloutRescanTimer?.invalidate()
        usageTask?.cancel()
        hoverExpandWorkItem?.cancel()
        hoverCollapseWorkItem?.cancel()
        visibilityShortcut = nil
        stopObservingPreferenceChanges()
        frontmostMonitor.stop()
        rolloutMonitor.stop()
        nativeReadMonitor.stop()
    }

    private func handleTimerTick() {
        let now = nowProvider()
        pollSessions()
        if now.timeIntervalSince(lastUsageRequestAt ?? .distantPast) >= Self.usageRefreshInterval {
            refreshUsage()
        }
    }

    private func pollSessions() {
        snapshotRequestSequence += 1
        let sequence = snapshotRequestSequence
        let store = sessionStore
        let now = nowProvider()
        Task {
            let snapshot = await store.snapshot(now: now)
            await MainActor.run { [weak self] in
                guard let self, sequence > self.lastAppliedSnapshotSequence else { return }
                self.lastAppliedSnapshotSequence = sequence
                self.apply(snapshot: snapshot, now: now)
            }
        }
    }

    private func apply(snapshot: ActiveSessionStoreSnapshot, now: Date) {
        guard started else { return }
        guard snapshot != lastSessionSnapshot else {
            viewModel.updateClock(now: now)
            PetCompanionController.shared.observe(activeSessions: activeSessions, completions: recentCompletions,
                isHovered: isHovered, now: now)
            refreshTitlesIfNeeded(now: now)
            return
        }

        lastSessionSnapshot = snapshot
        let hadActiveSessions = !activeSessions.isEmpty
        activeSessions = snapshot.activeSessions.map {
            $0.withTitle(threadTitles[$0.threadID])
        }
        if hadActiveSessions, activeSessions.isEmpty {
            resetHoverState()
        }
        recentCompletions = snapshot.recentCompletions.map { completion in
            CompletedSession(
                session: completion.session.withTitle(threadTitles[completion.session.threadID]),
                completedAt: completion.completedAt
            )
        }
        nativeReadMonitor.updateCompletions(recentCompletions)
        refreshTitlesIfNeeded(now: now)
        render(now: now)
    }

    private func refreshTitlesIfNeeded(now: Date) {
        guard !titleRefreshInFlight,
              now.timeIntervalSince(lastTitleRefreshAt ?? .distantPast) >= Self.titleRefreshInterval else {
            return
        }

        let threadIDs = visibleThreadIDs
        guard !threadIDs.isEmpty else { return }

        titleRefreshInFlight = true
        lastTitleRefreshAt = now
        let reader = threadTitleReader
        let projectReader = threadProjectReader
        let generation = metadataGeneration
        titleReadQueue.async { [weak self] in
            let titles = reader.titles(for: threadIDs)
            let projects = projectReader.projects(for: threadIDs)
            DispatchQueue.main.async {
                guard let self else { return }
                self.titleRefreshInFlight = false
                guard self.started, generation == self.metadataGeneration else { return }
                let visible = Set(self.visibleThreadIDs)
                let resolvedProjects = projects.filter { visible.contains($0.key) }
                let projectsChanged = resolvedProjects != self.threadProjects
                self.threadProjects = resolvedProjects
                self.applyResolvedTitles(titles)
                if projectsChanged { self.render() }
            }
        }
    }

    private var visibleThreadIDs: [String] {
        Array(
            Set(
                activeSessions.map(\.threadID)
                    + recentCompletions.map(\.session.threadID)
            )
        ).sorted()
    }

    private func applyResolvedTitles(_ titles: [String: String]) {
        let visibleIDs = Set(visibleThreadIDs)
        // This is a full lookup for the visible set. Drop names rejected by the
        // reader so unavailable/invalid metadata returns to the project label.
        let resolvedTitles = titles.filter { visibleIDs.contains($0.key) }
        guard resolvedTitles != threadTitles else { return }
        threadTitles = resolvedTitles

        let resolvedActiveSessions = activeSessions.map {
            $0.withTitle(threadTitles[$0.threadID])
        }
        let resolvedRecentCompletions = recentCompletions.map { completion in
            CompletedSession(
                session: completion.session.withTitle(threadTitles[completion.session.threadID]),
                completedAt: completion.completedAt
            )
        }
        guard resolvedActiveSessions != activeSessions
            || resolvedRecentCompletions != recentCompletions else {
            return
        }
        activeSessions = resolvedActiveSessions
        recentCompletions = resolvedRecentCompletions
        render()
    }

    private func refreshUsage() {
        let requestID = UUID()
        usageRequestID = requestID
        lastUsageRequestAt = nowProvider()
        usageTask?.cancel()

        let reader = authReader
        let urlSession = self.urlSession
        let endpoint = usageEndpoint
        usageTask = Task { [weak self] in
            do {
                let credentials = try reader.read()
                let snapshot = try await CodexUsageClient(
                    credentials: credentials,
                    session: urlSession,
                    endpoint: endpoint
                ).fetch()
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.usageRequestID == requestID else { return }
                    self.usage = snapshot
                    self.render()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.usageRequestID == requestID else { return }
                    // Keep the last successful snapshot. A transient usage failure
                    // must not hide an otherwise valid session indicator.
                    self.render()
                }
            }
        }
    }

    private func setChatGPTFrontmost(_ isFrontmost: Bool) {
        let frontmostStateChanged = isChatGPTFrontmost != isFrontmost
        if isChatGPTFrontmost != isFrontmost {
            isChatGPTFrontmost = isFrontmost
            if isFrontmost {
                refreshUsage()
            }
        }
        if frontmostStateChanged {
            render()
        }
        // The monitor calls this for every app switch, including transitions
        // between two non-Codex apps that both map to `false`.
        windowController.reassertNotchPanelAfterApplicationSwitch(
            displayIsEnabled: runtimePreferences.notchDisplayEnabled
        )
    }

    private func toggleNotchDisplay() {
        userDefaults.set(
            NotchDisplayPreference.toggledValue(
                for: runtimePreferences.notchDisplayEnabled
            ),
            forKey: NotchDisplayPreference.storageKey
        )
    }

    private func setHovered(_ hovered: Bool) {
        guard isPointerInside != hovered else { return }
        isPointerInside = hovered

        // Prepare the hover canvas before publishing the small shell response.
        // Reentry during a card transition keeps its accepted curve intact.
        if !isHovered && viewModel.state != .hidden && !windowController.isCardTransitionInFlight {
            render()
        }

        if hovered {
            hoverCollapseWorkItem?.cancel()
            hoverCollapseWorkItem = nil

            guard !isHovered, hoverExpandWorkItem == nil else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverExpandWorkItem = nil
                guard self.started, self.isPointerInside, !self.isHovered else { return }
                self.isHovered = true
                self.render()
            }
            hoverExpandWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.hoverExpandDelay,
                execute: workItem
            )
            return
        }

        hoverExpandWorkItem?.cancel()
        hoverExpandWorkItem = nil
        guard isHovered else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverCollapseWorkItem = nil
            guard self.isHovered, !self.isPointerInside else { return }
            self.isHovered = false
            self.isResetScheduleExpanded = false
            self.render()
        }
        hoverCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverCollapseDelay,
            execute: workItem
        )
    }

    private func resetHoverState() {
        hoverExpandWorkItem?.cancel()
        hoverExpandWorkItem = nil
        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
        isPointerInside = false
        isHovered = false
        isResetScheduleExpanded = false
    }

    private func setResetScheduleExpanded(_ isExpanded: Bool) {
        guard isHovered, isPointerInside,
              isResetScheduleExpanded != isExpanded else {
            return
        }
        isResetScheduleExpanded = isExpanded
        render()
    }

    private func openThread(_ threadID: String) {
        // Capture the completed turn before handing off. Opening a running
        // thread must never acknowledge the answer that will arrive later.
        let completion = activeSessions.contains(where: { $0.threadID == threadID })
            ? nil : recentCompletions.first(where: { $0.session.threadID == threadID })
        let opened = threadNavigator.open(threadID: threadID)
        if let completion,
           conversationReadStore.acknowledge(completion, threadLinkOpened: opened) {
            render()
        }
    }

    private func activateChatGPT() {
        _ = threadNavigator.activateCodex()
    }

    private var recentConversationLimit: RecentConversationLimit {
        runtimePreferences.recentConversationLimit
    }

    private var animationsEnabled: Bool {
        AppAnimationPreference.allowsMotion(
            animationsEnabled: runtimePreferences.animationsEnabled
        )
    }

    private var runtimePreferences: NotchRuntimePreferences {
        NotchRuntimePreferences.read(from: userDefaults)
    }

    private func observePreferenceChanges() {
        guard preferencesObserver == nil else { return }
        lastObservedPreferences = runtimePreferences
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.started else { return }
            let preferences = self.runtimePreferences
            guard preferences != self.lastObservedPreferences else { return }
            self.lastObservedPreferences = preferences
            self.render()
        }
    }

    private func stopObservingPreferenceChanges() {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        preferencesObserver = nil
        lastObservedPreferences = nil
    }

    private func expandedContentSize(
        for state: NotchPresentationState,
        isResetScheduleExpanded: Bool
    ) -> NSSize {
        guard case let .expanded(content) = state,
              !content.conversations.isEmpty else {
            return NotchExpandedLayout.taskContentSize(
                conversationCount: 2,
                isResetScheduleExpanded: isResetScheduleExpanded,
                resetCreditCount: resetCreditCount(in: state),
                hasFiveHourWindow: hasFiveHourWindow(in: state)
            )
        }
        return NotchExpandedLayout.taskContentSize(
            conversationCount: content.conversations.count,
            projectCount: content.projectSections.count,
            isResetScheduleExpanded: isResetScheduleExpanded,
            resetCreditCount: content.usage?.resetCredits.count ?? 0,
            hasFiveHourWindow: content.usage?.fiveHourWindow != nil
        )
    }

    private func quotaExpandedContentSize(
        for state: NotchPresentationState,
        isResetScheduleExpanded: Bool
    ) -> NSSize {
        NotchExpandedLayout.quotaContentSize(
            isResetScheduleExpanded: isResetScheduleExpanded,
            resetCreditCount: resetCreditCount(in: state),
            hasFiveHourWindow: hasFiveHourWindow(in: state)
        )
    }

    private func resetCreditCount(in state: NotchPresentationState) -> Int {
        guard case let .expanded(content) = state else { return 0 }
        return content.usage?.resetCredits.count ?? 0
    }

    private func hasFiveHourWindow(in state: NotchPresentationState) -> Bool {
        guard case let .expanded(content) = state else { return false }
        return content.usage?.fiveHourWindow != nil
    }

    private func showConversationSearch() {
        guard recentConversationLimit != .none else { return }
        updateConversationSearch()
        searchWindow.show()
    }

    private func updateConversationSearch() {
        let preferences = runtimePreferences
        guard preferences.recentConversationLimit != .none else { searchWindow.close(); return }
        let input = NotchPresentationInput(now: nowProvider(), isChatGPTFrontmost: isChatGPTFrontmost,
            activeSessions: activeSessions, recentCompletions: recentCompletions, usage: usage, isHovered: true,
            readReceipts: conversationReadStore.receipts, nativeReadReceipts: nativeReadMonitor.receipts,
            conversationCategoryOrder: preferences.conversationCategoryOrder, threadProjects: threadProjects,
            conversationProjectOrder: preferences.conversationProjectOrder)
        if case let .expanded(content) = NotchPresentationReducer.reduce(input).limitingRecentConversations(to: preferences.recentConversationLimit) {
            searchWindow.model.conversations = content.conversations
            searchWindow.model.language = preferences.language
        }
    }

    private func render(now: Date? = nil) {
        if searchWindow.isOpen { updateConversationSearch() }
        let renderDate = now ?? nowProvider()
        let preferences = runtimePreferences
        PetCompanionController.shared.observe(activeSessions: activeSessions, completions: recentCompletions,
            isHovered: isHovered, now: renderDate)
        guard let screen = NotchScreenMetrics.preferredScreen() else {
            resetHoverState()
            windowController.hideNotchPanel()
            return
        }
        let metrics = NotchScreenMetrics(screen: screen)
        let baseLayout = NotchGeometry.layout(metrics: metrics, leftIndicatorEnabled: preferences.leftIndicatorEnabled,
            companionEnabled: PetCompanionController.shared.hasSelectedPet)

        if NotchPanelVisibilityPolicy.shouldUseMenuBarFallback(
            layoutMode: baseLayout.mode,
            displayIsEnabled: preferences.notchDisplayEnabled
        ) {
            resetHoverState()
            viewModel.update(
                state: .hidden,
                now: renderDate,
                layoutMode: baseLayout.mode,
                animationsEnabled: false
            )
            windowController.showDisplayDisabledFallback()
            return
        }

        if NotchPanelVisibilityPolicy.shouldKeepHiddenHoverSensor(
            layoutMode: baseLayout.mode,
            displayIsEnabled: preferences.notchDisplayEnabled
        ), !isHovered {
            return renderHiddenHoverSensor(
                now: renderDate,
                screen: screen,
                metrics: metrics
            )
        }

        compactCompletionStore.removeViewed(local: conversationReadStore.receipts, native: nativeReadMonitor.receipts)
        let input = NotchPresentationInput(
            now: renderDate,
            isChatGPTFrontmost: isChatGPTFrontmost,
            activeSessions: activeSessions,
            recentCompletions: recentCompletions,
            usage: usage,
            isHovered: isHovered,
            readReceipts: conversationReadStore.receipts,
            nativeReadReceipts: nativeReadMonitor.receipts,
            compactCompletionSignals: compactCompletionStore.signals,
            conversationCategoryOrder: preferences.conversationCategoryOrder,
            threadProjects: threadProjects,
            conversationProjectOrder: preferences.conversationProjectOrder
        )

        let state = NotchPresentationReducer.reduce(input)
        let stateForWindow: NotchPresentationState
        if baseLayout.mode == .menuBarFallback {
            stateForWindow = NotchPresentationReducer.reduce(
                NotchPresentationInput(
                    now: input.now,
                    isChatGPTFrontmost: input.isChatGPTFrontmost,
                    activeSessions: input.activeSessions,
                    recentCompletions: input.recentCompletions,
                    usage: input.usage,
                    isHovered: true,
                    readReceipts: input.readReceipts,
                    nativeReadReceipts: input.nativeReadReceipts,
                    conversationCategoryOrder: input.conversationCategoryOrder,
                    threadProjects: input.threadProjects,
                    conversationProjectOrder: input.conversationProjectOrder
                )
            )
        } else {
            stateForWindow = state
        }
        if case let .expanded(content) = stateForWindow {
            projectOrderStore.discover(content.allProjectIDs)
        }
        let displayState = stateForWindow.limitingRecentConversations(
            to: recentConversationLimit
        )
        guard case .expanded = displayState else {
            isResetScheduleExpanded = false
            return renderCompactState(displayState, now: renderDate, screen: screen, metrics: metrics)
        }
        if resetCreditCount(in: displayState) == 0 {
            isResetScheduleExpanded = false
        }
        let layout = NotchGeometry.layout(
            metrics: metrics,
            leftIndicatorEnabled: preferences.leftIndicatorEnabled,
            companionEnabled: PetCompanionController.shared.hasSelectedPet,
            quotaExpandedSize: quotaExpandedContentSize(
                for: displayState,
                isResetScheduleExpanded: isResetScheduleExpanded
            ),
            expandedSize: expandedContentSize(
                for: displayState,
                isResetScheduleExpanded: isResetScheduleExpanded
            )
        )
        let targetFrame = layout.frame(for: displayState)
        // The controller allocates the final canvas before the SwiftUI state
        // changes. That lets the island grow within one stable window instead
        // of animating the NSPanel itself.
        let transitionIdentifier = windowController.prepare(
            layout: layout,
            state: displayState,
            isHovering: isPointerInside,
            animationsEnabled: animationsEnabled
        )
        let animationWillComplete = viewModel.update(
            state: displayState,
            now: renderDate,
            layoutMode: layout.mode,
            cameraSafeAreaInset: layout.mode == .notch
                ? max(0, screen.safeAreaInsets.top)
                : 0,
            compactWidth: layout.compactFrame.width,
            compactHeight: layout.compactFrame.height,
            compactLeadingInset: layout.compactLeadingInset,
            surfaceSize: targetFrame.size,
            isResetScheduleExpanded: isResetScheduleExpanded,
            isPointerInside: isPointerInside,
            animationsEnabled: animationsEnabled,
            onSurfaceAnimationCompleted: { [weak windowController] in
                windowController?.finishSurfaceAnimation(
                    identifier: transitionIdentifier, targetFrame: targetFrame
                )
            }
        )
        windowController.settleFrame(
            layout: layout,
            state: displayState,
            animationsEnabled: animationsEnabled,
            animationWillComplete: animationWillComplete
        )
    }

    private func renderHiddenHoverSensor(
        now: Date,
        screen: NSScreen,
        metrics: NotchScreenMetrics
    ) {
        let layout = NotchGeometry.layout(metrics: metrics, leftIndicatorEnabled: runtimePreferences.leftIndicatorEnabled, companionEnabled: PetCompanionController.shared.hasSelectedPet)
        guard layout.mode != .menuBarFallback else {
            windowController.showDisplayDisabledFallback()
            return
        }

        let hiddenState = NotchPresentationState.hidden
        let targetFrame = layout.frame(for: hiddenState)
        windowController.prepare(
            layout: layout,
            state: hiddenState,
            animationsEnabled: false
        )
        viewModel.update(
            state: hiddenState,
            now: now,
            layoutMode: layout.mode,
            cameraSafeAreaInset: max(0, screen.safeAreaInsets.top),
            compactWidth: layout.compactFrame.width,
            compactHeight: layout.compactFrame.height,
            compactLeadingInset: layout.compactLeadingInset,
            surfaceSize: targetFrame.size,
            isResetScheduleExpanded: false,
            animationsEnabled: false
        )
        windowController.settleFrame(
            layout: layout,
            state: hiddenState,
            animationsEnabled: false
        )
    }

    private func renderCompactState(
        _ displayState: NotchPresentationState,
        now: Date,
        screen: NSScreen,
        metrics: NotchScreenMetrics
    ) {
        let layout = NotchGeometry.layout(metrics: metrics, leftIndicatorEnabled: runtimePreferences.leftIndicatorEnabled, companionEnabled: PetCompanionController.shared.hasSelectedPet)
        let targetFrame = layout.frame(for: displayState)
        let transitionIdentifier = windowController.prepare(
            layout: layout,
            state: displayState,
            isHovering: isPointerInside && displayState != .hidden,
            animationsEnabled: animationsEnabled
        )
        let animationWillComplete = viewModel.update(
            state: displayState,
            now: now,
            layoutMode: layout.mode,
            cameraSafeAreaInset: layout.mode == .notch
                ? max(0, screen.safeAreaInsets.top)
                : 0,
            compactWidth: layout.compactFrame.width,
            compactHeight: layout.compactFrame.height,
            compactLeadingInset: layout.compactLeadingInset,
            surfaceSize: displayState == .hidden ? targetFrame.size : layout.compactFrame.size,
            isResetScheduleExpanded: false,
            isPointerInside: isPointerInside && displayState != .hidden,
            animationsEnabled: animationsEnabled,
            onSurfaceAnimationCompleted: { [weak windowController] in
                windowController?.finishSurfaceAnimation(
                    identifier: transitionIdentifier, targetFrame: targetFrame
                )
            }
        )
        windowController.settleFrame(
            layout: layout,
            state: displayState,
            animationsEnabled: animationsEnabled,
            animationWillComplete: animationWillComplete
        )
    }

}
