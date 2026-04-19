import SwiftUI

// MARK: - PulseView

/// Scrolling oscilloscope — 60 fps via TimelineView.
///
/// The canvas draws the drift waveform as a path. Each sample maps to one horizontal
/// pixel column; the Y position is the drift value scaled to the view height.
/// A moving average pass (configurable 1–60 samples) can smooth the line before draw.
struct PulseView: View {

    @EnvironmentObject var engine: TimeEngine

    /// How many seconds of history to show in the visible window.
    var visibleSeconds: Int = 300

    /// Moving average window. 1 = raw, higher = smoother.
    @Binding var smoothingWindow: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
            Canvas { context, size in
                drawBackground(context: context, size: size)
                drawGridLines(context: context, size: size)
                drawWaveform(context: context, size: size)
                drawZeroLine(context: context, size: size)
                drawScanLine(context: context, size: size)
            }
        }
    }

    // MARK: - Draw: Background

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(red: 0.03, green: 0.03, blue: 0.03))
        )
    }

    // MARK: - Draw: Grid lines

    private func drawGridLines(context: GraphicsContext, size: CGSize) {
        let gridColor = Color.white.opacity(0.06)
        let horizontalDivisions = 8
        let verticalDivisions = 6

        var gridPath = Path()

        // Horizontal lines
        for i in 1..<horizontalDivisions {
            let y = size.height * CGFloat(i) / CGFloat(horizontalDivisions)
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
        }

        // Vertical time markers
        for i in 1..<verticalDivisions {
            let x = size.width * CGFloat(i) / CGFloat(verticalDivisions)
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
        }

        context.stroke(gridPath, with: .color(gridColor), lineWidth: 0.5)
    }

    // MARK: - Draw: Zero reference line

    private func drawZeroLine(context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2
        var zeroPath = Path()
        zeroPath.move(to: CGPoint(x: 0, y: midY))
        zeroPath.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(zeroPath, with: .color(.green.opacity(0.25)), lineWidth: 0.5)
    }

    // MARK: - Draw: Scan line (rightmost edge highlight)

    private func drawScanLine(context: GraphicsContext, size: CGSize) {
        var scanPath = Path()
        scanPath.move(to: CGPoint(x: size.width - 1, y: 0))
        scanPath.addLine(to: CGPoint(x: size.width - 1, y: size.height))
        context.stroke(scanPath, with: .color(.green.opacity(0.6)), lineWidth: 0.5)
    }

    // MARK: - Draw: Waveform

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let samples = engine.store.recentMachSamples(count: visibleSeconds)
        guard samples.count >= 2 else { return }

        let smoothed = engine.store.movingAverage(of: samples, window: smoothingWindow)

        // Determine display amplitude: use the 95th-percentile absolute value
        // so extreme spikes don't compress the rest of the waveform.
        let sortedAbs = smoothed.map { abs($0) }.sorted()
        let p95index = Int(Double(sortedAbs.count) * 0.95)
        let displayAmplitude = max(sortedAbs[safe: p95index] ?? 100.0, 10.0) * 1.2

        let midY = size.height / 2.0
        let xStep = size.width / CGFloat(smoothed.count - 1)

        // Primary waveform path
        var wavePath = Path()
        for (i, value) in smoothed.enumerated() {
            let x = CGFloat(i) * xStep
            // Scale value into [0, height], clamped so extreme spikes stay on-screen.
            let normalized = (value / displayAmplitude).clamped(to: -1.0...1.0)
            let y = midY - CGFloat(normalized) * midY * 0.85

            if i == 0 {
                wavePath.move(to: CGPoint(x: x, y: y))
            } else {
                wavePath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Phosphor glow: draw multiple passes with decreasing opacity
        let glowColor = Color(red: 0.1, green: 1.0, blue: 0.35)
        context.stroke(wavePath, with: .color(glowColor.opacity(0.08)), lineWidth: 4.0)
        context.stroke(wavePath, with: .color(glowColor.opacity(0.15)), lineWidth: 2.0)
        context.stroke(wavePath, with: .color(glowColor.opacity(0.85)), lineWidth: 0.5)

        // Amplitude scale label (top-right corner)
        drawAmplitudeLabel(context: context, size: size, amplitude: displayAmplitude)
    }

    private func drawAmplitudeLabel(context: GraphicsContext, size: CGSize, amplitude: Double) {
        let label = "scale: ±\(String(format: "%.1f", amplitude)) μs"
        context.draw(
            Text(label)
                .font(.system(size: 9, weight: .light, design: .monospaced))
                .foregroundColor(.white.opacity(0.3)),
            at: CGPoint(x: size.width - 6, y: 10),
            anchor: .topTrailing
        )
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
