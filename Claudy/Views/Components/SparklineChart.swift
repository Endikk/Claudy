import SwiftUI
import Charts

/// Seven-day usage sparkline. No axes and no grid: the shape and the last point are enough, and
/// the numbers live in the "Details" section.
struct SparklineChart: View {
    let samples: [TokenSample]
    let tint: Color

    private var upperBound: Double {
        let peak = samples.map(\.tokens).max() ?? 1
        return Double(peak) * 1.18
    }

    var body: some View {
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

                if let last = samples.last {
                    PointMark(
                        x: .value("Day", last.date, unit: .day),
                        y: .value("Tokens", last.tokens)
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

            HStack(spacing: 0) {
                ForEach(samples) { sample in
                    Text(UsageViewModel.dayInitial(sample.date))
                        .font(Theme.Font.label(8.5, .semibold))
                        .foregroundStyle(.primary.opacity(sample.id == samples.last?.id ? 0.65 : 0.28))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(Theme.Motion.gauge, value: samples)
    }
}
