import SwiftUI

public struct HeaderRow: View {
    let trailing: Text
    public init(trailing: Text) { self.trailing = trailing }
    public init(trailing: String) { self.trailing = Text(trailing) }

    public var body: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(Theme.clay).frame(width: 8, height: 8)
                Text("claude").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            trailing.font(.system(size: 11)).foregroundStyle(Theme.textMuted)
        }
    }
}

public struct LimitBar: View {
    let label: Text
    let fraction: Double
    let barColor: Color
    let valueColor: Color
    let emphasized: Bool

    public init(label: Text, fraction: Double, barColor: Color, valueColor: Color, emphasized: Bool = false) {
        self.label = label
        self.fraction = min(max(fraction, 0), 1)
        self.barColor = barColor
        self.valueColor = valueColor
        self.emphasized = emphasized
    }

    public init(label: String, fraction: Double, barColor: Color, valueColor: Color, emphasized: Bool = false) {
        self.init(label: Text(label), fraction: fraction, barColor: barColor,
                  valueColor: valueColor, emphasized: emphasized)
    }

    public var body: some View {
        VStack(spacing: 5) {
            HStack {
                label
                    .font(.system(size: 12, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(emphasized ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 12, weight: emphasized ? .medium : .regular))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(barColor).frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
    }
}

public struct Sparkline: View {
    let points: [HourPoint]

    public init(points: [HourPoint]) { self.points = points }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxTok = Double(points.map(\.tokens).max() ?? 1)
            let coords: [CGPoint] = points.enumerated().map { i, p in
                let x = points.count > 1 ? w * Double(i) / Double(points.count - 1) : w
                let y = h - (h - 4) * Double(p.tokens) / maxTok - 2
                return CGPoint(x: x, y: y)
            }
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h - 0.5))
                    path.addLine(to: CGPoint(x: w, y: h - 0.5))
                }
                .stroke(Theme.barQuiet, lineWidth: 1)
                if coords.count > 1 {
                    Path { path in
                        path.move(to: coords[0])
                        for c in coords.dropFirst() { path.addLine(to: c) }
                    }
                    .stroke(Theme.clay, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let last = coords.last {
                    Circle().fill(Theme.clay).frame(width: 7, height: 7).position(last)
                }
            }
        }
    }
}

public struct MonthBars: View {
    let daily: [DayUsage]

    public init(daily: [DayUsage]) { self.daily = daily }

    public var body: some View {
        GeometryReader { geo in
            let maxTok = Double(daily.map(\.tokens).max() ?? 1)
            let peak = daily.max { $0.tokens < $1.tokens }?.id
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(daily) { day in
                    let frac = maxTok > 0 ? Double(day.tokens) / maxTok : 0
                    UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                        .fill(day.id == peak ? Theme.clay : (frac < 0.15 ? Theme.barQuiet : Theme.barDim))
                        .frame(height: max(2, geo.size.height * frac))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

public struct SessionRow: View {
    let session: SessionUsage
    let rank: Int
    let maxTokens: Int
    let showBar: Bool

    public init(session: SessionUsage, rank: Int, maxTokens: Int, showBar: Bool = true) {
        self.session = session
        self.rank = rank
        self.maxTokens = maxTokens
        self.showBar = showBar
    }

    var barColor: Color {
        switch rank {
        case 0: return Theme.clay
        case 1: return Theme.clayDim
        default: return Theme.clayDimmer
        }
    }

    public var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(session.name)
                    .font(.system(size: 12, weight: rank == 0 ? .medium : .regular))
                    .foregroundStyle(rank == 0 ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(UsageStats.formatTokens(session.tokens))
                    .font(.system(size: 11, weight: rank == 0 ? .medium : .regular))
                    .monospacedDigit()
                    .foregroundStyle(rank == 0 ? Theme.clay : Theme.textMuted)
            }
            if showBar {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(barColor)
                            .frame(width: max(4, geo.size.width * Double(session.tokens) / Double(max(maxTokens, 1))))
                    }
                }
                .frame(height: 3)
            }
        }
    }
}

public struct RingGauge: View {
    let fraction: Double
    let ringColor: Color
    let valueColor: Color
    let label: String
    let sublabel: Text
    let sublabelColor: Color
    let emphasized: Bool
    let size: CGFloat

    public init(fraction: Double, ringColor: Color, valueColor: Color,
                label: String, sublabel: Text, sublabelColor: Color = Theme.textMuted,
                emphasized: Bool = false, size: CGFloat = 72) {
        self.fraction = min(max(fraction, 0), 1)
        self.ringColor = ringColor
        self.valueColor = valueColor
        self.label = label
        self.sublabel = sublabel
        self.sublabelColor = sublabelColor
        self.emphasized = emphasized
        self.size = size
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: size / 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: size / 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: size * 0.23, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
            .frame(width: size, height: size)
            .padding(size / 20)
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(emphasized ? Theme.textPrimary : Theme.textSecondary)
                sublabel
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(sublabelColor)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

public struct SignInButton: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Text("Sign in to Claude Code")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textBright)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.clay, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Opens Terminal and runs: claude auth login")
    }
}

/// Shown when the rings still hold a usable reading but refreshes have started
/// failing, so the numbers are believable now and will quietly rot if ignored.
public struct FetchFailureBanner: View {
    let failure: OfficialUsage.FetchFailure
    let onReauth: (() -> Void)?

    public init(failure: OfficialUsage.FetchFailure, onReauth: (() -> Void)? = nil) {
        self.failure = failure
        self.onReauth = onReauth
    }

    public var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(failure.headline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.amber)
                Text("showing the last reading · \(failure.hint)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if failure == .signedOut, let onReauth {
                SignInButton(action: onReauth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.tipBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

public struct RingsRow: View {
    let stats: UsageStats
    let ringSize: CGFloat
    let liveCountdown: Bool
    /// Supplied by the app only. A widget cannot start an interactive sign-in, so
    /// there it stays nil and the hint text carries the instruction instead.
    let onReauth: (() -> Void)?

    public init(stats: UsageStats, ringSize: CGFloat = 72, liveCountdown: Bool = false,
                onReauth: (() -> Void)? = nil) {
        self.stats = stats
        self.ringSize = ringSize
        self.liveCountdown = liveCountdown
        self.onReauth = onReauth
    }

    private var sessionSublabel: Text {
        guard let reset = stats.displaySessionReset, reset > .now else { return Text("idle") }
        return Text("resets \(UsageStats.exactTime(reset))")
    }

    private var weekModelResetText: String {
        if let reset = stats.official?.weekModelReset {
            return "resets \(UsageStats.exactTime(reset))"
        }
        return "resets \(stats.weeklyResetText)"
    }

    private var weekAllResetText: String {
        if let reset = stats.official?.weekAllReset {
            return "resets \(UsageStats.exactTime(reset))"
        }
        return "resets \(stats.weeklyResetText)"
    }

    public var body: some View {
        if stats.official == nil {
            unavailable
        } else {
            rings
        }
    }

    private var unavailable: some View {
        VStack(spacing: 4) {
            Text(stats.fetchFailure?.headline ?? "usage data not available")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(stats.needsReauth ? Theme.amber : Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text(stats.fetchFailure?.hint ?? "start a claude session and it refreshes")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            if stats.needsReauth, let onReauth {
                SignInButton(action: onReauth).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Theme.tipBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var rings: some View {
        HStack(spacing: 8) {
            if let modelFraction = stats.displayWeekModelFraction {
                RingGauge(
                    fraction: modelFraction,
                    ringColor: Theme.amber, valueColor: Theme.amber,
                    label: stats.displayWeekModelLabel,
                    sublabel: Text(weekModelResetText),
                    emphasized: true, size: ringSize
                )
            }
            RingGauge(
                fraction: stats.displayWeekAllFraction,
                ringColor: Theme.textMuted, valueColor: Theme.textSecondary,
                label: "all models",
                sublabel: Text(weekAllResetText),
                size: ringSize
            )
            RingGauge(
                fraction: stats.displaySessionFraction,
                ringColor: Theme.clay, valueColor: Theme.clay,
                label: "session",
                sublabel: sessionSublabel,
                sublabelColor: Theme.clay,
                emphasized: true, size: ringSize
            )
        }
    }
}

public struct TimeAxis: View {
    let hours: [Int]

    public init(hours: [Int]) { self.hours = hours }

    private func hourLabel(_ h: Int) -> String {
        switch h {
        case 0: return "12am"
        case ..<12: return "\(h)am"
        case 12: return "12pm"
        default: return "\(h - 12)pm"
        }
    }

    public var body: some View {
        HStack {
            if let first = hours.first {
                Text(hourLabel(first)).font(.system(size: 10)).foregroundStyle(Theme.textDim)
                if hours.count > 2, let mid = hours.dropFirst(hours.count / 2).first, mid != first {
                    Spacer()
                    Text(hourLabel(mid)).font(.system(size: 10)).foregroundStyle(Theme.textDim)
                }
            }
            Spacer()
            Text("now · \(Date.now.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10)).foregroundStyle(Theme.textDim)
        }
    }
}

public struct SectionLabel: View {
    let text: String
    let trailing: String

    public init(_ text: String, trailing: String = "") {
        self.text = text
        self.trailing = trailing
    }

    public var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if !trailing.isEmpty {
                Text(trailing).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.textMuted)
            }
        }
    }
}
