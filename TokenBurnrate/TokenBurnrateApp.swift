import SwiftUI
import WidgetKit

@main
struct TokenBurnrateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

enum StatsTab: String, CaseIterable {
    case sessions, models
}

struct ContentView: View {
    @State private var stats = UsageStats()
    @State private var loading = true
    @State private var watcher: ClaudeWatcher?
    @AppStorage("statsTab") private var tab: StatsTab = .sessions
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(Theme.clay).frame(width: 8, height: 8)
                    Text("claude").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text(relativeTime).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                Button {
                    refresh(forceOfficial: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }

            if loading {
                ProgressView("Reading ~/.claude transcripts…")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                RingsRow(stats: stats, onReauth: signIn)

                if stats.official != nil, let failure = stats.fetchFailure {
                    FetchFailureBanner(failure: failure, onReauth: signIn)
                }

                if let tip = stats.smartTip {
                    Text(tip)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.tipBackground, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(spacing: 6) {
                    SectionLabel("today", trailing: "\(UsageStats.formatTokens(stats.todayTotal)) tok")
                    if stats.hourlyCumulative.isEmpty {
                        Text("no usage yet today")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    } else {
                        Sparkline(points: stats.hourlyCumulative).frame(height: 36)
                        TimeAxis(hours: stats.hourlyCumulative.map(\.hour))
                    }
                }

                tabSwitcher

                Group {
                    switch tab {
                    case .sessions: sessionsPane
                    case .models: modelsPane
                    }
                }
                .frame(minHeight: 84, alignment: .top)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .task {
            refresh()
            watcher = ClaudeWatcher(url: UsageParser.projectsDirectory()) {
                refresh(silent: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the sign-in Terminal is the moment a retry can succeed,
            // and the failure back-off would otherwise hold it off for five minutes.
            if phase == .active, stats.fetchFailure != nil {
                refresh(silent: true, forceOfficial: true)
            }
        }
    }

    func signIn() {
        Reauth.launch()
    }

    var tabSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(StatsTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11, weight: tab == t ? .medium : .regular))
                        .foregroundStyle(tab == t ? Theme.textPrimary : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            tab == t ? Theme.barQuiet : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.tipBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    var sessionsPane: some View {
        VStack(spacing: 8) {
            if stats.topSessions.isEmpty {
                Text("no sessions yet today")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(stats.topSessions.enumerated()), id: \.element.id) { i, session in
                    SessionRow(session: session, rank: i,
                               maxTokens: stats.topSessions.first?.tokens ?? 1)
                }
            }
        }
    }

    var modelsPane: some View {
        VStack(spacing: 8) {
            ForEach(stats.byModel) { m in
                HStack {
                    Text(m.shortName)
                        .font(.system(size: 12, weight: m.id == stats.topModel?.id ? .medium : .regular))
                        .foregroundStyle(m.id == stats.topModel?.id ? Theme.textPrimary : Theme.textSecondary)
                    Spacer()
                    Text("\(m.messages) msgs")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    Text(UsageStats.formatTokens(m.tokens))
                        .font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }

    var relativeTime: String {
        guard !loading else { return "loading…" }
        let day = stats.generatedAt.formatted(.dateTime.month(.abbreviated).day())
        let time = stats.generatedAt.formatted(date: .omitted, time: .shortened)
        return "updated \(day) \(time)"
    }

    func refresh(silent: Bool = false, forceOfficial: Bool = false) {
        if !silent { loading = true }
        Task.detached(priority: .userInitiated) {
            if forceOfficial || OfficialUsage.shouldAttemptFetch() {
                switch OfficialUsage.fetchViaCLI() {
                case .success(let official):
                    official.save()
                    OfficialUsage.clearFailure()
                case .failure(let failure):
                    OfficialUsage.record(failure)
                }
            }
            let fresh = UsageParser.loadStats()
            SharedStore.save(fresh)
            await MainActor.run {
                stats = fresh
                loading = false
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
