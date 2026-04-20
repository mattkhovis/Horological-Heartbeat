import AppKit
import Combine

// MARK: - MenuBarController

/// Drives a live ECG waveform rendered into the macOS menu bar status item.
///
/// Architecture:
///   - A 15 fps render timer calls tick() each frame.
///   - Each new mach sample from TimeEngine → a new Beat event with amplitude
///     scaled to abs(drift).
///   - renderFrame() walks x across the icon width and sums the QRS contribution
///     from every visible beat at that x, producing a smooth continuous path.
///   - The image is marked isTemplate so AppKit recolors it for dark/light menu bars.
@MainActor
final class MenuBarController: NSObject, ObservableObject {

    // MARK: - Types

    /// One heartbeat event: when it happened and how tall to draw the spike.
    private struct Beat {
        let time: CFAbsoluteTime
        /// 0.0 = minimum visible spike, 1.0 = maximum spike.
        let amplitude: Double
    }

    // MARK: - State

    private var statusItem: NSStatusItem?
    private var renderTimer: Timer?
    private weak var engine: TimeEngine?

    private var beats: [Beat] = []
    private var lastSampleCount: Int = 0

    // MARK: - Icon geometry (logical points)

    /// Visible history in seconds. ECG scrolls one full width in this time.
    private let visibleSeconds: Double = 3.3

    /// Width of the status item in points. Enough for ~3 s of ECG.
    private let iconWidth:  Double = 46
    private let iconHeight: Double = 18

    /// Derived: how many points the waveform scrolls per second.
    private var pxPerSecond: Double { iconWidth / visibleSeconds }

    // MARK: - Lifecycle

    func start(engine: TimeEngine) {
        guard statusItem == nil else { return }
        self.engine = engine

        statusItem = NSStatusBar.system.statusItem(withLength: iconWidth)
        statusItem?.button?.action = #selector(handleClick)
        statusItem?.button?.target = self

        // Pre-populate synthetic beats so the icon isn't blank for the first few seconds.
        let now = CFAbsoluteTimeGetCurrent()
        let spacing = visibleSeconds / 4.0
        for i in 1...4 {
            beats.append(Beat(time: now - Double(i) * spacing, amplitude: 0.25))
        }

        // 15 fps is more than sufficient for a 46×18 pt menu bar icon.
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        tick()
    }

    func stop() {
        renderTimer?.invalidate()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Tick

    private func tick() {
        guard let engine else { return }
        let now = CFAbsoluteTimeGetCurrent()

        // One beat per new mach sample (≈ 1 Hz).
        let currentCount = engine.store.orderedMachSamples.count
        if currentCount > lastSampleCount {
            lastSampleCount = currentCount

            // Map drift magnitude to spike amplitude.
            // 0 μs → 0.2 (always has a visible blip), 500 μs → 1.0.
            let driftAbs = abs(engine.latestMachDrift)
            let amplitude = (0.2 + min(driftAbs / 500.0, 0.8)).clamped(to: 0.2...1.0)
            beats.append(Beat(time: now, amplitude: amplitude))
        }

        // Drop beats that have scrolled completely off the left edge.
        let maxAge = visibleSeconds + 1.5
        beats.removeAll { now - $0.time > maxAge }

        statusItem?.button?.image = renderFrame(now: now)
    }

    // MARK: - Render

    /// Produces one NSImage frame of the ECG at the current moment.
    /// isTemplate = true so AppKit inverts it for dark/light menu bar automatically.
    private func renderFrame(now: CFAbsoluteTime) -> NSImage {
        let w = iconWidth
        let h = iconHeight

        let image = NSImage(size: NSSize(width: w, height: h), flipped: false) { [self] _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(0.9)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)

            let midY = h / 2.0
            // Sample at 2 sub-points per logical pixel for a smooth path.
            let steps  = Int(w) * 2
            let xStep  = w / Double(steps)
            let path   = CGMutablePath()

            for i in 0...steps {
                let x = Double(i) * xStep

                // Sum QRS contributions from every visible beat.
                var displacement = 0.0
                for beat in beats {
                    // beatX: the x-coordinate where this beat's R peak sits right now.
                    let beatX = w - (now - beat.time) * pxPerSecond
                    displacement += qrsShape(dx: x - beatX, amplitude: beat.amplitude)
                }

                // Upward displacement = lower y in AppKit coordinates (origin bottom-left).
                let y = (midY - displacement).clamped(to: 1.5...(h - 1.5))

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            ctx.addPath(path)
            ctx.strokePath()
            return true
        }

        // Template mode: AppKit uses the alpha channel as a mask and fills with
        // the correct tint color for the current menu bar appearance.
        image.isTemplate = true
        return image
    }

    // MARK: - QRS shape

    /// Vertical displacement in logical points for position `dx` relative to the R peak.
    ///
    /// The shape is a simplified cardiac cycle:
    ///   P wave → PR segment → Q deflection → R spike → S deflection → ST → T wave
    ///
    /// `amplitude` (0–1) scales the peak height between 1.5 pt (min) and 7.5 pt (max).
    private func qrsShape(dx: Double, amplitude: Double) -> Double {
        let peak = 1.5 + amplitude * 6.0    // spike peak in logical points

        switch dx {
        case -7.0 ..< -5.0:                 // P wave: small positive bump
            return peak * 0.12 * sin((dx + 7.0) / 2.0 * .pi)

        case -5.0 ..< -2.5:                 // PR isoelectric segment
            return 0.0

        case -2.5 ..< -1.5:                 // Q: small downward dip
            return peak * -0.22 * sin((dx + 2.5) / 1.0 * .pi)

        case -1.5 ..< 0.0:                  // R upstroke: rapid rise to peak
            return peak * sin((dx + 1.5) / 1.5 * .pi / 2.0)

        case 0.0 ..< 0.6:                   // R → S: sharp fall past baseline
            return peak * (1.0 - (dx / 0.6) * 1.7)

        case 0.6 ..< 1.4:                   // S trough → return to baseline
            return peak * (-0.7 + (dx - 0.6) / 0.8 * 0.7)

        case 1.4 ..< 2.2:                   // ST isoelectric segment
            return 0.0

        case 2.2 ..< 5.5:                   // T wave: gentle positive hump
            return peak * 0.30 * sin((dx - 2.2) / 3.3 * .pi)

        default:
            return 0.0
        }
    }

    // MARK: - Click

    @objc private func handleClick() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Window was destroyed by SwiftUI; request a new one.
            if #available(macOS 13.0, *) {
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
            }
        }
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
