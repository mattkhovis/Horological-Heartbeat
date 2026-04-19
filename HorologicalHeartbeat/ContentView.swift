import SwiftUI

struct ContentView: View {

    @EnvironmentObject var engine: TimeEngine

    @State private var smoothingWindow: Int = 10
    @State private var visibleSeconds: Int = 300

    var body: some View {
        HStack(spacing: 0) {
            // Left: oscilloscope
            VStack(spacing: 0) {
                header()
                PulseView(
                    visibleSeconds: visibleSeconds,
                    smoothingWindow: $smoothingWindow
                )
                .environmentObject(engine)

                controlBar()
            }

            // Right: stats panel
            Divider()
                .background(Color.white.opacity(0.08))
            StatsView()
                .environmentObject(engine)
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.03))
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    @ViewBuilder
    private func header() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("CLOCK ACCURACY MONITOR")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .tracking(4)

                Text("HOW ACCURATE IS YOUR MAC'S CLOCK?")
                    .font(.system(size: 8, weight: .light, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(2)
            }

            Spacer()

            // Live timestamp
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                Text(context.date.formatted(.dateTime
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits)
                    .second(.twoDigits)
                ))
                .font(.system(size: 22, weight: .thin, design: .monospaced))
                .foregroundColor(.green.opacity(0.7))
                .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    // MARK: - Control bar

    @ViewBuilder
    private func controlBar() -> some View {
        HStack(spacing: 24) {
            controlGroup(label: "SMOOTHING") {
                HStack(spacing: 8) {
                    Text("LIVE")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Slider(value: Binding(
                        get: { Double(smoothingWindow) },
                        set: { smoothingWindow = max(1, Int($0)) }
                    ), in: 1...60, step: 1)
                    .tint(.green)
                    .frame(width: 100)
                    Text("\(smoothingWindow)s AVG")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 40, alignment: .leading)
                }
            }

            controlGroup(label: "HISTORY") {
                HStack(spacing: 8) {
                    ForEach([60, 300, 900, 3600], id: \.self) { seconds in
                        Button(action: { visibleSeconds = seconds }) {
                            Text(seconds < 60 ? "\(seconds)s"
                                 : seconds < 3600 ? "\(seconds/60)m"
                                 : "\(seconds/3600)h")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(visibleSeconds == seconds ? .green : .white.opacity(0.3))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(visibleSeconds == seconds
                                              ? Color.green.opacity(0.15)
                                              : Color.white.opacity(0.04))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Beat counter
            VStack(alignment: .trailing, spacing: 2) {
                Text("READINGS")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .tracking(2)
                Text("\(engine.store.orderedMachSamples.count) samples")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func controlGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
                .tracking(2)
            content()
        }
    }
}
