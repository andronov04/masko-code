import SwiftUI

struct CompactStatsPillSegment {
    enum Leading {
        case dot(Color)
        case symbol(String, Color)
    }

    let leading: Leading
    let text: String
    let color: Color
}

struct CompactStatsPillSnapshot: Equatable {
    let activeCount: Int
    let subagentCount: Int
    let compactCount: Int
    let pendingCount: Int
    let runningCount: Int

    init(
        activeCount: Int,
        subagentCount: Int,
        compactCount: Int,
        pendingCount: Int,
        runningCount: Int
    ) {
        self.activeCount = activeCount
        self.subagentCount = subagentCount
        self.compactCount = compactCount
        self.pendingCount = pendingCount
        self.runningCount = runningCount
    }

    init(sessionStore: SessionStore, pendingCount: Int) {
        self.init(
            activeCount: sessionStore.activeSessions.count,
            subagentCount: sessionStore.totalActiveSubagents,
            compactCount: sessionStore.totalCompactCount,
            pendingCount: pendingCount,
            runningCount: sessionStore.runningSessions.count
        )
    }

    var segments: [CompactStatsPillSegment] {
        var result: [CompactStatsPillSegment] = [
            CompactStatsPillSegment(
                leading: .dot(activeCount == 0 ? .gray : .green),
                text: "\(activeCount)",
                color: .white
            )
        ]

        if subagentCount > 0 {
            result.append(
                CompactStatsPillSegment(
                    leading: .symbol("arrow.branch", .cyan),
                    text: "\(subagentCount)",
                    color: .cyan
                )
            )
        }

        if compactCount > 0 {
            result.append(
                CompactStatsPillSegment(
                    leading: .symbol("arrow.triangle.2.circlepath", .purple),
                    text: "\(compactCount)",
                    color: .purple
                )
            )
        }

        if pendingCount > 0 {
            result.append(
                CompactStatsPillSegment(
                    leading: .symbol("hand.raised.fill", .orange),
                    text: "\(pendingCount)",
                    color: .orange
                )
            )
        }

        if runningCount > 0 {
            result.append(
                CompactStatsPillSegment(
                    leading: .symbol("bolt.fill", .green),
                    text: "\(runningCount)",
                    color: .green
                )
            )
        }

        return result
    }
}

enum CompactStatsPillStyle {
    case overlay
    case island

    var background: Color {
        switch self {
        case .overlay:
            return Color.black.opacity(0.6)
        case .island:
            return Color.black
        }
    }
}

struct CompactStatsPill: View {
    let style: CompactStatsPillStyle

    @Environment(SessionStore.self) var sessionStore
    @Environment(PendingPermissionStore.self) var pendingPermissionStore

    private var snapshot: CompactStatsPillSnapshot {
        CompactStatsPillSnapshot(sessionStore: sessionStore, pendingCount: pendingPermissionStore.count)
    }

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
        .background(style.background)
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
    }
}

/// Compact stats pill displayed above the mascot overlay
struct StatsOverlayView: View {
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        let _ = PerfMonitor.shared.track(.viewBodyStatsOverlay)
        #endif
        CompactStatsPill(style: .overlay)
    }
}
