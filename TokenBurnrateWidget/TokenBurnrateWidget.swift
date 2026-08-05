import WidgetKit
import SwiftUI

@main
struct TokenBurnrateWidgets: WidgetBundle {
    var body: some Widget {
        TokenBurnrateWidget()
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let stats: UsageStats
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, stats: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: .now, stats: .sample))
        } else {
            completion(UsageEntry(date: .now, stats: SharedStore.load() ?? UsageStats()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: .now, stats: SharedStore.load() ?? UsageStats())
        let refresh = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct TokenBurnrateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenBurnrateWidget", provider: UsageProvider()) { entry in
            UsageWidgetView(stats: entry.stats)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Claude usage")
        .description("Token burn, trends, and your top sessions today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) var family
    let stats: UsageStats

    var body: some View {
        switch family {
        case .systemSmall: SmallView(stats: stats)
        case .systemMedium: MediumView(stats: stats)
        default: LargeView(stats: stats)
        }
    }
}

func resetsText(_ stats: UsageStats) -> String {
    guard let reset = stats.displaySessionReset, reset > .now else { return "idle" }
    return "resets \(UsageStats.exactTime(reset))"
}

func dateTimeLabel(_ stats: UsageStats) -> String {
    let f = DateFormatter()
    f.dateFormat = "EEE MMM d"
    let day = f.string(from: stats.generatedAt).lowercased()
    let time = stats.generatedAt.formatted(date: .omitted, time: .shortened)
    return "\(day) · \(time)"
}

struct SmallView: View {
    let stats: UsageStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Theme.clay).frame(width: 7, height: 7)
                Text("claude").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(Theme.track, lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: stats.displaySessionFraction)
                            .stroke(Theme.clay, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int((stats.displaySessionFraction * 100).rounded()))%")
                            .font(.system(size: 14, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.clay)
                    }
                    .frame(width: 56, height: 56)
                    Text(resetsText(stats))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if !stats.hourlyCumulative.isEmpty {
                Sparkline(points: stats.hourlyCumulative).frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MediumView: View {
    let stats: UsageStats

    var body: some View {
        VStack(spacing: 8) {
            HeaderRow(trailing: dateTimeLabel(stats))
            RingsRow(stats: stats, ringSize: 46)
            if !stats.hourlyCumulative.isEmpty {
                Sparkline(points: stats.hourlyCumulative).frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct LargeView: View {
    let stats: UsageStats

    var body: some View {
        VStack(spacing: 9) {
            HeaderRow(trailing: dateTimeLabel(stats))

            RingsRow(stats: stats, ringSize: 58)

            VStack(spacing: 4) {
                SectionLabel("today", trailing: "\(UsageStats.formatTokens(stats.todayTotal)) tok")
                if stats.hourlyCumulative.isEmpty {
                    Text("no usage yet today")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, minHeight: 24)
                } else {
                    Sparkline(points: stats.hourlyCumulative).frame(height: 24)
                    TimeAxis(hours: stats.hourlyCumulative.map(\.hour))
                }
            }
            .padding(.bottom, 4)

            Rectangle()
                .fill(Theme.track)
                .frame(height: 1)

            VStack(spacing: 5) {
                SectionLabel("top sessions today")
                    .padding(.top, 2)
                if stats.topSessions.isEmpty {
                    Text("no sessions yet")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(stats.topSessions.enumerated()), id: \.element.id) { i, session in
                        SessionRow(session: session, rank: i,
                                   maxTokens: stats.topSessions.first?.tokens ?? 1, showBar: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
