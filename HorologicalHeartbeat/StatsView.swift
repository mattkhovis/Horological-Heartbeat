import SwiftUI

// MARK: - StatsView

/// "Luxury movement" stats panel — horological instrument aesthetic.
struct StatsView: View {

    @EnvironmentObject var engine: TimeEngine

    var body: some View {
        let stats = engine.store.stats(over: 3600)

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("CLOCK ACCURACY")

            statRow(
                label: "CURRENT DRIFT",
                value: formatMicroseconds(engine.latestMachDrift),
                sublabel: "right now"
            )

            statRow(
                label: "TIME SERVER OFFSET",
                value: formatMicroseconds(engine.latestNTPOffset),
                sublabel: engine.isNTPConnected ? "synced · time.apple.com" : "not connected",
                accent: engine.isNTPConnected ? .green : .orange
            )

            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 8)

            sectionHeader("LAST HOUR SUMMARY")

            statRow(label: "VARIATION",     value: formatMicroseconds(stats.stdDev),       sublabel: "how much drift varies")
            statRow(label: "DRIFT RANGE",   value: "\(formatMicroseconds(stats.min)) / \(formatMicroseconds(stats.max))", sublabel: "lowest / highest")
            statRow(label: "AVERAGE DRIFT", value: formatMicroseconds(stats.mean),          sublabel: "average over time")

            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 8)

            sectionHeader("FORECAST")

            statRow(
                label: "DRIFT PER DAY",
                value: formatDailyDrift(stats.projectedDailyDrift),
                sublabel: "if current rate continues"
            )

            statRow(
                label: "READINGS TAKEN",
                value: "\(stats.sampleCount)",
                sublabel: "in last hour"
            )

            Spacer()

            statusDot()
        }
        .padding(16)
        .frame(width: 240)
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
    }

    // MARK: - Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.3))
            .tracking(2)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func statRow(label: String, value: String, sublabel: String, accent: Color = .green) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(1.5)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .light, design: .monospaced))
                    .foregroundColor(accent)
                    .monospacedDigit()
            }
            Text(sublabel)
                .font(.system(size: 8, weight: .light, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
                .tracking(0.5)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func statusDot() -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(engine.isNTPConnected ? Color.green : Color.orange)
                .frame(width: 5, height: 5)
                .shadow(color: engine.isNTPConnected ? .green : .orange, radius: 3)
            Text(engine.isNTPConnected ? "TIME SYNCED" : "SYNCING...")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(2)
        }
    }

    // MARK: - Formatters

    private func formatMicroseconds(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%+.2f ms", value / 1000.0)
        }
        return String(format: "%+.2f μs", value)
    }

    private func formatDailyDrift(_ seconds: Double) -> String {
        if abs(seconds) < 0.001 {
            return String(format: "%+.3f ms/day", seconds * 1000)
        }
        return String(format: "%+.4f s/day", seconds)
    }
}
