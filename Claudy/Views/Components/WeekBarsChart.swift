import SwiftUI
import Charts

/// Seven days of local tokens as bars, today brightest, with the daily average as a dashed
/// line. Bars grow in when the chart appears; hovering a bar puts its figures in the header.
struct WeekBarsChart: View {
    let samples: [TokenSample]
    let tint: Color

    @State private var hovered: TokenSample?
    @State private var grown = false

    private var average: Double {
        guard !samples.isEmpty else { return 0 }
        return Double(samples.reduce(0) { $0 + $1.tokens }) / Double(samples.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            Chart {
                ForEach(samples) { sample in
                    BarMark(
                        x: .value("Day", sample.date, unit: .day),
                        y: .value("Tokens", grown ? sample.tokens : 0),
                        width: .ratio(0.62)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(tint.opacity(opacity(for: sample)))
                }

                if average > 0 {
                    RuleMark(y: .value("Average", grown ? average : 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.primary.opacity(0.25))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(UsageViewModel.dayInitial(date))
                                .font(Theme.Font.label(8.5, .semibold))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...max(Double(samples.map(\.tokens).max() ?? 1) * 1.1, 1))
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
            .frame(height: 70)
        }
        .onAppear {
            withAnimation(Theme.Motion.gauge.delay(0.15)) { grown = true }
        }
        .onDisappear { grown = false }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Last 7 days")
                .microLabel(0.55)
            Spacer(minLength: 4)
            if let hovered {
                Text(UsageViewModel.dayName(hovered.date))
                    .font(Theme.Font.label(10.5, .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                Text(UsageViewModel.tokens(hovered.tokens))
                    .font(Theme.Font.value(10.5, .semibold))
                    .foregroundStyle(tint)
            } else if average > 0 {
                Text("avg \(UsageViewModel.tokens(Int(average))) / day")
                    .font(Theme.Font.value(10.5, .medium))
                    .foregroundStyle(.primary.opacity(0.4))
            }
        }
        .frame(height: 12)
    }

    private func opacity(for sample: TokenSample) -> Double {
        if let hovered { return sample.id == hovered.id ? 1 : 0.3 }
        return sample.id == samples.last?.id ? 1 : 0.45
    }

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
