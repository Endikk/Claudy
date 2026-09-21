import SwiftUI
import Charts

/// Seven-day usage sparkline. No axes and no grid: the shape and the last point are enough.
/// Hovering a day marks it and shows its figures in the header, next to the title.
struct SparklineChart: View {
    let title: String
    let samples: [TokenSample]
    let tint: Color

    @State private var hovered: TokenSample?

    private var weekTotal: Int { samples.reduce(0) { $0 + $1.tokens } }

    private var upperBound: Double {
        let peak = samples.map(\.tokens).max() ?? 1
        return Double(peak) * 1.18
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            chart
        }
        .animation(Theme.Motion.gauge, value: samples)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .microLabel(0.55)
            Spacer(minLength: 4)
            if let hovered {
                Text(UsageViewModel.dayName(hovered.date))
                    .font(Theme.Font.label(10.5, .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                Text(UsageViewModel.tokens(hovered.tokens))
                    .font(Theme.Font.value(10.5, .semibold))
                    .foregroundStyle(tint)
                if weekTotal > 0 {
                    Text("\(Int((Double(hovered.tokens) / Double(weekTotal) * 100).rounded())) % of week")
                        .font(Theme.Font.value(10.5, .medium))
                        .foregroundStyle(.primary.opacity(0.4))
                }
            }
        }
        .frame(height: 12)
    }

    private var chart: some View {
        VStack(spacing: 5) {
            Chart {
                ForEach(samples) { sample in
                    AreaMark(
                        x: .value("Day", sample.date, unit: .day),
                        y: .value("Tokens", sample.tokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.38), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Day", sample.date, unit: .day),
                        y: .value("Tokens", sample.tokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                }

                if let hovered {
                    RuleMark(x: .value("Day", hovered.date, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundStyle(.primary.opacity(0.25))
                }

                if let marked = hovered ?? samples.last {
                    PointMark(
                        x: .value("Day", marked.date, unit: .day),
                        y: .value("Tokens", marked.tokens)
                    )
                    .symbolSize(38)
                    .foregroundStyle(tint)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: 0...max(upperBound, 1))
            .frame(height: 46)
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
                    Text(UsageViewModel.dayInitial(sample.date))
                        .font(Theme.Font.label(8.5, .semibold))
                        .foregroundStyle(.primary.opacity(sample.id == (hovered ?? samples.last)?.id ? 0.65 : 0.28))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// The day closest to the pointer, so the whole width is live and not only the points.
    private func nearestSample(atX x: CGFloat, proxy: ChartProxy) -> TokenSample? {
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}
