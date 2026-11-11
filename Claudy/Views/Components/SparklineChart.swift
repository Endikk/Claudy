import SwiftUI
import Charts

/// Seven-day usage curve. No axes and no grid: the shape and the last point are enough. The
/// header carries today's and the week's totals; hovering a day puts its own figures there.
struct SparklineChart: View {
    let title: String
    let samples: [TokenSample]
    let tint: Color
    var today: Int?
    var week: Int?

    @Environment(\.colorScheme) private var scheme
    @State private var hovered: TokenSample?

    private var weekTotal: Int { samples.reduce(0) { $0 + $1.tokens } }

    private var upperBound: Double {
        let peak = samples.map(\.tokens).max() ?? 1
        return Double(peak) * 1.18
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
        }
        .animation(Theme.Motion.gauge, value: samples)
    }

    /// The title, or once the totals are known, the totals themselves: "Today" and "7 days" say
    /// what the curve is, and the title beside them pushed the figures to an ellipsis.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let hovered {
                Text(UsageViewModel.dayName(hovered.date))
                    .meta()
                Text(UsageViewModel.tokens(hovered.tokens))
                    .font(Theme.Font.value(13, .semibold))
                    .ink(.coral)
                Spacer(minLength: 4)
                if weekTotal > 0 {
                    Text("\(Int((Double(hovered.tokens) / Double(weekTotal) * 100).rounded()))% of week")
                        .meta()
                }
            } else if let today, let week {
                total("Today", today, ink: .coral)
                Spacer(minLength: 8)
                total("7 days", week, ink: .sky)
            } else {
                Text(title)
                    .sectionLabel()
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .frame(height: 16)
    }

    private func total(_ label: String, _ value: Int, ink: Theme.Ink) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .meta()
            Text(UsageViewModel.tokens(value))
                .font(Theme.Font.value(13, .semibold))
                .ink(ink)
        }
    }

    private var chart: some View {
        VStack(spacing: 6) {
            Chart {
                ForEach(samples) { sample in
                    AreaMark(
                        x: .value("Day", sample.date, unit: .day),
                        y: .value("Tokens", sample.tokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.42), tint.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Day", sample.date, unit: .day),
                        y: .value("Tokens", sample.tokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                }

                if let hovered {
                    RuleMark(x: .value("Day", hovered.date, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundStyle(.tertiary)
                }

                if let marked = hovered ?? samples.last {
                    PointMark(
                        x: .value("Day", marked.date, unit: .day),
                        y: .value("Tokens", marked.tokens)
                    )
                    .symbol {
                        Circle()
                            .fill(tint)
                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                            .frame(width: 11, height: 11)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: 0...max(upperBound, 1))
            .frame(height: 64)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plot = geometry[proxy.plotAreaFrame]
                                hovered = nearestSample(atX: location.x - plot.origin.x, proxy: proxy)
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }

            HStack(spacing: 0) {
                ForEach(samples) { sample in
                    let isMarked = sample.id == (hovered ?? samples.last)?.id
                    Text(UsageViewModel.dayInitial(sample.date))
                        .font(Theme.Font.label(11, isMarked ? .bold : .medium))
                        .foregroundStyle(isMarked ? Theme.Ink.coral.color(scheme) : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// The day closest to the pointer, so the whole width is live and not only the points.
    private func nearestSample(atX x: CGFloat, proxy: ChartProxy) -> TokenSample? {
        guard let date: Date = proxy.value(atX: x) else { return nil }
        // Marks with `unit: .day` span the whole day, so match the day, not the nearest midnight.
        if let sameDay = samples.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            return sameDay
        }
        return samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}
