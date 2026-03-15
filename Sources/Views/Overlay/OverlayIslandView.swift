import SwiftUI

final class IslandInteractionState: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            if isPinned { isExpanded = true }
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private var isHovered = false
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?

    func handleHover(_ hovering: Bool) {
        isHovered = hovering
        if hovering {
            collapseWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.isExpanded = true
                self?.onChange?()
            }
            expandWorkItem?.cancel()
            expandWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
        } else {
            expandWorkItem?.cancel()
            guard !isPinned else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, !self.isHovered, !self.isPinned else { return }
                self.isExpanded = false
                self.onChange?()
            }
            collapseWorkItem?.cancel()
            collapseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
        }
    }

    func collapseIfPossible() {
        guard !isPinned else { return }
        isExpanded = false
        onChange?()
    }
}

@Observable
final class IslandHUDConfig {
    var contentSize: CGSize = CGSize(width: 156, height: 56) {
        didSet {
            guard abs(contentSize.width - oldValue.width) > 2
               || abs(contentSize.height - oldValue.height) > 2 else { return }
            onContentSizeChange?(contentSize)
        }
    }

    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            onPinnedChange?(isPinned)
        }
    }

    let permissionConfig = PermissionHUDConfig()
    var compactWidth: CGFloat = 228
    var onContentSizeChange: ((CGSize) -> Void)?
    var onPinnedChange: ((Bool) -> Void)?

    func updateContentSize(_ size: CGSize) {
        contentSize = size
    }
}

private struct IslandChromeShape: InsettableShape {
    var radius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private enum IslandVisualState {
    case compact
    case expanded
    case pinned
}

private enum IslandStatusStyle {
    case idle
    case working
    case alert

    var dotColor: Color {
        switch self {
        case .idle: return Color.white.opacity(0.36)
        case .working: return Constants.orangePrimary
        case .alert: return Color(red: 1.0, green: 0.35, blue: 0.28)
        }
    }
}

private struct IslandWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct OverlayIslandView: View {
    let config: IslandHUDConfig
    let stateMachine: OverlayStateMachine?
    let loopURL: URL?

    @Environment(PendingPermissionStore.self) private var pendingPermissionStore
    @Environment(SessionStore.self) private var sessionStore
    @Environment(SessionSwitcherStore.self) private var sessionSwitcherStore
    @Environment(SessionFinishedStore.self) private var sessionFinishedStore

    @State private var isHovered = false
    @State private var hoverExpanded = false
    @State private var expandWorkItem: DispatchWorkItem?
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var statsPillWidth: CGFloat = 0
    @State private var expandedContentWidth: CGFloat = 0
    @State private var expandedContentHeight: CGFloat = 0

    private let topInset: CGFloat = 2
    private let compactBottomInset: CGFloat = 2
    private let expandedBottomInset: CGFloat = 8
    private let compactBarHeight: CGFloat = 28
    private let baseStatsPillWidth: CGFloat = 28

    private var visualState: IslandVisualState {
        if config.isPinned { return .pinned }
        if hoverExpanded { return .expanded }
        return .compact
    }

    private var statusStyle: IslandStatusStyle {
        if !pendingPermissionStore.pending.isEmpty {
            return .alert
        }
        let hasWorkingSession = sessionStore.activeSessions.contains { $0.phase == .running }
        return hasWorkingSession ? .working : .idle
    }

    private var promptCount: Int {
        pendingPermissionStore.pending.count
    }

    private var isCompactState: Bool {
        visualState == .compact
    }

    private var showsExpandedContent: Bool {
        !isCompactState
    }

    private var hasExpandedModules: Bool {
        !pendingPermissionStore.pending.isEmpty ||
        sessionSwitcherStore.isActive ||
        sessionFinishedStore.current != nil ||
        config.permissionConfig.showPreview
    }

    private var hasExpandableSection: Bool {
        true
    }

    private var compactVisibleHeight: CGFloat {
        topInset + compactBarHeight + compactBottomInset
    }

    private var expandedVisibleHeight: CGFloat {
        topInset + compactBarHeight + expandedContentHeight + expandedBottomInset
    }

    private var currentVisibleHeight: CGFloat {
        showsExpandedContent && hasExpandableSection ? expandedVisibleHeight : compactVisibleHeight
    }

    private var panelHeight: CGFloat {
        max(compactVisibleHeight, hasExpandableSection ? expandedVisibleHeight : compactVisibleHeight)
    }

    private var compactHeaderWidth: CGFloat {
        let extraStatsWidth = max(0, statsPillWidth - baseStatsPillWidth)
        return config.compactWidth + extraStatsWidth
    }

    private var panelWidth: CGFloat {
        let expandedWidth = max(compactHeaderWidth, expandedContentWidth + 20)
        return showsExpandedContent ? expandedWidth : compactHeaderWidth
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            visibleIsland
                .frame(width: panelWidth, alignment: .topLeading)
                .frame(height: currentVisibleHeight, alignment: .topLeading)
                .clipped()
        }
        .background(alignment: .topLeading) {
            expandedContent
                .hidden()
                .allowsHitTesting(false)
        }
        .frame(width: panelWidth, alignment: .topLeading)
        .frame(height: panelHeight, alignment: .topLeading)
        .onAppear(perform: syncContentSize)
        .onChange(of: panelWidth) { _, _ in syncContentSize() }
        .onChange(of: panelHeight) { _, _ in syncContentSize() }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: hoverExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: config.isPinned)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: promptCount)
    }

    private var visibleIsland: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactBar
            expandedContentContainer
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, topInset)
        .padding(.bottom, showsExpandedContent ? expandedBottomInset : compactBottomInset)
        .background(islandBackground)
        .clipShape(islandShape)
        .shadow(color: Color.black.opacity(showsExpandedContent ? 0.22 : 0.16), radius: showsExpandedContent ? 18 : 10, x: 0, y: showsExpandedContent ? 12 : 6)
        .onHover(perform: handleHover)
        .overlay(alignment: .topTrailing) {
            if promptCount > 1 {
                Text("\(promptCount)")
                    .font(Constants.heading(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Constants.orangePrimary, in: Capsule())
                    .offset(x: 4, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var compactBar: some View {
        HStack(spacing: 6) {
            mascotButton
            Spacer(minLength: 0)

            CompactStatsPill(style: .island)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: IslandWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
        }
        .padding(.horizontal, 3)
        .frame(width: compactHeaderWidth, alignment: .leading)
        .frame(height: compactBarHeight)
        .fixedSize(horizontal: true, vertical: false)
        .onPreferenceChange(IslandWidthPreferenceKey.self) { statsPillWidth = $0 }
    }

    private var expandedContentContainer: some View {
        expandedContent
            .padding(.horizontal, 10)
            .frame(height: showsExpandedContent ? expandedContentHeight : 0, alignment: .top)
            .clipped()
            .opacity(showsExpandedContent ? 1 : 0)
            .allowsHitTesting(showsExpandedContent)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !statusSubtitle.isEmpty {
                Text(statusSubtitle)
                    .font(Constants.body(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
                    .padding(.top, 12)
                    .padding(.horizontal, 2)
            }

            if hasExpandedModules {
                PermissionHUDView(config: config.permissionConfig)
                    .environment(pendingPermissionStore)
                    .environment(sessionSwitcherStore)
                    .environment(sessionStore)
                    .environment(sessionFinishedStore)
            }

            islandActiveSessionsCard
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        expandedContentWidth = geo.size.width
                        expandedContentHeight = geo.size.height
                    }
                    .onChange(of: geo.size.width) { _, newValue in
                        expandedContentWidth = newValue
                    }
                    .onChange(of: geo.size.height) { _, newValue in
                        expandedContentHeight = newValue
                    }
            }
        )
    }

    private var islandActiveSessionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active Sessions")
                .font(Constants.body(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.42))

            if sortedActiveSessions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.28))

                    Text("No active sessions")
                        .font(Constants.body(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 30/255, green: 30/255, blue: 34/255).opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedActiveSessions) { session in
                        Button {
                            IDETerminalFocus.focusSession(session)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Constants.orangePrimary)
                                    .frame(width: 14)

                                Text(sessionDisplayName(session))
                                    .font(Constants.body(size: 11, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.92))
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.46))

                                Text(sessionTrailingCount(session))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.46))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if session.id != sortedActiveSessions.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.06))
                                .padding(.leading, 34)
                        }
                    }
                }
                .background(Color(red: 30/255, green: 30/255, blue: 34/255).opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private var mascotButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.96))

            Group {
                if let stateMachine {
                    StateMachineVideoPlayer(
                        url: stateMachine.currentVideoURL,
                        isLoop: stateMachine.isLoopVideo,
                        stateMachine: stateMachine
                    )
                    .onHover { stateMachine.handleMouseOver($0) }
                } else if let loopURL {
                    MascotVideoView(url: loopURL)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(1)
        }
        .frame(width: 24, height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            stateMachine?.handleClick()
        }
    }

    private var islandBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.94),
                Color(red: 20/255, green: 20/255, blue: 24/255).opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var islandShape: IslandChromeShape {
        IslandChromeShape(radius: isCompactState ? 12 : 12)
    }

    private var statusSubtitle: String {
        if let permission = pendingPermissionStore.pending.last {
            let detail = permission.toolInputPreview
            return detail.isEmpty ? permission.toolName : detail
        }
        return ""
    }

    private var sortedActiveSessions: [ClaudeSession] {
        sessionStore.activeSessions.sorted {
            if $0.phase == .running && $1.phase != .running { return true }
            if $0.phase != .running && $1.phase == .running { return false }
            return ($0.lastEventAt ?? $0.startedAt) > ($1.lastEventAt ?? $1.startedAt)
        }
    }

    private func sessionDisplayName(_ session: ClaudeSession) -> String {
        if let name = session.projectName, !name.isEmpty {
            return name
        }
        if let dir = session.projectDir, !dir.isEmpty {
            return URL(fileURLWithPath: dir).lastPathComponent
        }
        return session.id
    }

    private func sessionTrailingCount(_ session: ClaudeSession) -> String {
        if session.activeSubagentCount > 0 {
            return "\(session.activeSubagentCount)"
        }
        return session.phase == .running ? "1" : "0"
    }

    private func handleHover(_ hovering: Bool) {
        isHovered = hovering
        if hovering {
            collapseWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                hoverExpanded = true
            }
            expandWorkItem?.cancel()
            expandWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
        } else {
            expandWorkItem?.cancel()
            guard !config.isPinned else { return }
            let workItem = DispatchWorkItem {
                if !isHovered && !config.isPinned {
                    hoverExpanded = false
                }
            }
            collapseWorkItem?.cancel()
            collapseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
        }
    }

    private func syncContentSize() {
        config.updateContentSize(CGSize(width: panelWidth, height: panelHeight))
    }
}

struct OverlayIslandHeaderView: View {
    let interactionState: IslandInteractionState
    let stateMachine: OverlayStateMachine?
    let loopURL: URL?

    @Environment(PendingPermissionStore.self) private var pendingPermissionStore

    var body: some View {
        HStack {
            mascotButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 4)
        .background(islandBackground)
        .clipShape(IslandChromeShape(radius: 12))
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 6)
        .onHover(perform: interactionState.handleHover)
        .overlay(alignment: .topTrailing) {
            if pendingPermissionStore.pending.count > 1 {
                Text("\(pendingPermissionStore.pending.count)")
                    .font(Constants.heading(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Constants.orangePrimary, in: Capsule())
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var mascotButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.96))

            Group {
                if let stateMachine {
                    StateMachineVideoPlayer(
                        url: stateMachine.currentVideoURL,
                        isLoop: stateMachine.isLoopVideo,
                        stateMachine: stateMachine
                    )
                    .onHover { stateMachine.handleMouseOver($0) }
                } else if let loopURL {
                    MascotVideoView(url: loopURL)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(1)
        }
        .frame(width: 24, height: 24)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            stateMachine?.handleClick()
        }
    }

    private var islandBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.94),
                Color(red: 20/255, green: 20/255, blue: 24/255).opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct OverlayIslandStatsPillView: View {
    let interactionState: IslandInteractionState
    let snapshot: CompactStatsPillSnapshot
    let sessionStore: SessionStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(snapshot.segments.enumerated()), id: \.offset) { _, segment in
                HStack(spacing: 3) {
                    switch segment.leading {
                    case .dot(let color):
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                    case .symbol(let symbol, let color):
                        Image(systemName: symbol)
                            .font(.system(size: 7))
                            .foregroundStyle(color)
                    }

                    Text(segment.text)
                        .foregroundStyle(segment.color)
                }
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .onTapGesture {
            let active = sessionStore.activeSessions
            if active.count == 1, let session = active.first {
                IDETerminalFocus.focusSession(session)
            } else if active.count > 1 {
                AppDelegate.showDashboard()
            }
        }
        .onHover(perform: interactionState.handleHover)
    }
}

struct OverlayIslandTopBarView: View {
    let interactionState: IslandInteractionState
    let stateMachine: OverlayStateMachine?
    let loopURL: URL?
    let snapshot: CompactStatsPillSnapshot
    let sessionStore: SessionStore
    let notchGap: CGFloat
    let pendingCount: Int
    let barHeight: CGFloat

    var body: some View {
        ZStack {
            islandBackground

            HStack(spacing: 0) {
                mascotButton
                Spacer(minLength: notchGap)
                OverlayIslandStatsPillView(
                    interactionState: interactionState,
                    snapshot: snapshot,
                    sessionStore: sessionStore
                )
            }
            .padding(.horizontal, 3)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: barHeight)
        .clipShape(IslandChromeShape(radius: 10))
        .onHover(perform: interactionState.handleHover)
        .overlay(alignment: .topTrailing) {
            if pendingCount > 1 {
                Text("\(pendingCount)")
                    .font(Constants.heading(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Constants.orangePrimary, in: Capsule())
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var mascotButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.96))

            Group {
                if let stateMachine {
                    if snapshot.activeCount == 0 {
                        StaticVideoFrameView(url: stateMachine.currentVideoURL)
                            .id("static-\(snapshot.activeCount)-\(stateMachine.currentVideoURL?.absoluteString ?? "none")")
                    } else {
                        StateMachineVideoPlayer(
                            url: stateMachine.currentVideoURL,
                            isLoop: stateMachine.isLoopVideo,
                            stateMachine: stateMachine
                        )
                        .id("animated-\(snapshot.activeCount)-\(stateMachine.currentVideoURL?.absoluteString ?? "none")")
                        .onHover { stateMachine.handleMouseOver($0) }
                    }
                } else if let loopURL {
                    if snapshot.activeCount == 0 {
                        StaticVideoFrameView(url: loopURL)
                            .id("static-\(snapshot.activeCount)-\(loopURL.absoluteString)")
                    } else {
                        MascotVideoView(url: loopURL)
                            .id("animated-\(snapshot.activeCount)-\(loopURL.absoluteString)")
                    }
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(1)
        }
        .frame(width: 24, height: 24)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            stateMachine?.handleClick()
        }
    }

    private var islandBackground: some View {
        Color.black
    }
}

struct OverlayIslandBackdropView: View {
    let interactionState: IslandInteractionState

    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.96),
                Color(red: 18/255, green: 18/255, blue: 22/255).opacity(0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .clipShape(IslandChromeShape(radius: 12))
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
        .onHover(perform: interactionState.handleHover)
    }
}

struct OverlayIslandExpandedView: View {
    let config: IslandHUDConfig
    let interactionState: IslandInteractionState
    let availableWidth: CGFloat

    private let horizontalInset: CGFloat = 10

    @Environment(PendingPermissionStore.self) private var pendingPermissionStore
    @Environment(SessionStore.self) private var sessionStore
    @Environment(SessionSwitcherStore.self) private var sessionSwitcherStore
    @Environment(SessionFinishedStore.self) private var sessionFinishedStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !statusSubtitle.isEmpty {
                Text(statusSubtitle)
                    .font(Constants.body(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
                    .padding(.top, 12)
                    .padding(.horizontal, 2)
            }

            if hasExpandedModules {
                PermissionHUDView(config: config.permissionConfig)
                    .environment(pendingPermissionStore)
                    .environment(sessionSwitcherStore)
                    .environment(sessionStore)
                    .environment(sessionFinishedStore)
            }

            islandActiveSessionsCard
        }
        .frame(width: max(availableWidth - horizontalInset * 2, 0), alignment: .leading)
        .padding(.top, 10)
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 8)
        .background(expandedBackground)
        .clipShape(IslandChromeShape(radius: 12))
//        .shadow(color: Color.black.opacity(0.28), radius: 28, x: 0, y: 18)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        config.updateContentSize(geo.size)
                    }
                    .onChange(of: geo.size) { _, newValue in
                        config.updateContentSize(newValue)
                    }
            }
        )
        .onHover(perform: interactionState.handleHover)
    }

    private var hasExpandedModules: Bool {
        !pendingPermissionStore.pending.isEmpty ||
        sessionSwitcherStore.isActive ||
        sessionFinishedStore.current != nil ||
        config.permissionConfig.showPreview
    }

    private var statusSubtitle: String {
        if let permission = pendingPermissionStore.pending.last {
            let detail = permission.toolInputPreview
            return detail.isEmpty ? permission.toolName : detail
        }
        return ""
    }

    private var islandActiveSessionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active Sessions")
                .font(Constants.body(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.42))

            if sortedActiveSessions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.28))

                    Text("No active sessions")
                        .font(Constants.body(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 30/255, green: 30/255, blue: 34/255).opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedActiveSessions) { session in
                        Button {
                            IDETerminalFocus.focusSession(session)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Constants.orangePrimary)
                                    .frame(width: 14)

                                Text(sessionDisplayName(session))
                                    .font(Constants.body(size: 11, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.92))
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.46))

                                Text(sessionTrailingCount(session))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.46))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if session.id != sortedActiveSessions.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.06))
                                .padding(.leading, 34)
                        }
                    }
                }
                .background(Color(red: 30/255, green: 30/255, blue: 34/255).opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private var sortedActiveSessions: [ClaudeSession] {
        sessionStore.activeSessions.sorted {
            if $0.phase == .running && $1.phase != .running { return true }
            if $0.phase != .running && $1.phase == .running { return false }
            return ($0.lastEventAt ?? $0.startedAt) > ($1.lastEventAt ?? $1.startedAt)
        }
    }

    private func sessionDisplayName(_ session: ClaudeSession) -> String {
        if let name = session.projectName, !name.isEmpty {
            return name
        }
        if let dir = session.projectDir, !dir.isEmpty {
            return URL(fileURLWithPath: dir).lastPathComponent
        }
        return session.id
    }

    private func sessionTrailingCount(_ session: ClaudeSession) -> String {
        if session.activeSubagentCount > 0 {
            return "\(session.activeSubagentCount)"
        }
        return session.phase == .running ? "1" : "0"
    }

    private var expandedBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.94),
                Color(red: 20/255, green: 20/255, blue: 24/255).opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
