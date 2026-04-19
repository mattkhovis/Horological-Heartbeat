import Foundation
import Darwin
import Combine

// MARK: - Sample

/// One timestamped drift measurement in microseconds.
struct DriftSample: Identifiable {
    let id = UUID()
    /// Wall-clock moment of this sample (for the time axis).
    let timestamp: Date
    /// Signed drift in microseconds: positive = CPU running fast, negative = slow.
    let driftMicroseconds: Double
    /// NTP round-trip delay (seconds) for this sample; nil if mach-only.
    let ntpDelay: TimeInterval?
}

// MARK: - TimeEngine

/// Drives all time measurement on a background queue.
///
/// Two complementary techniques run in parallel:
///
///   1. High-frequency mach drift (every ~1 s)
///      Compares mach_absolute_time() — the CPU's raw oscillator, never adjusted —
///      against Date(), which macOS continuously nudges toward NTP truth via timed(8).
///      Their difference reveals the *net correction* the OS is applying.
///
///   2. Low-frequency NTP queries (every ~30 s)
///      Measures our true NTP offset so we can distinguish "OS is correcting" from
///      "OS has already corrected and this is residual noise."
@MainActor
final class TimeEngine: ObservableObject {

    // MARK: - Published state

    @Published var store = DriftStore()
    @Published var latestNTPOffset: Double = 0      // μs
    @Published var latestMachDrift: Double = 0      // μs
    @Published var isNTPConnected: Bool = false

    // MARK: - Private

    private nonisolated let ntpClient = NTPClient()

    /// Set to true if the server returns a Kiss-of-Death packet.
    /// RFC 4330 §8: the client MUST stop sending to that server.
    private var ntpKissOfDeath = false

    /// mach_timebase_info converts raw CPU ticks to nanoseconds via:
    ///   nanoseconds = ticks * numer / denom
    private var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Calibration anchor: we record matching (mach, wall) timestamps at startup
    /// so all future delta calculations have a stable reference point.
    private var calibrationMach: UInt64 = 0
    private var calibrationWall: Date = .distantPast

    private var machTimer: Timer?
    private var ntpTimer: Timer?
    private let backgroundQueue = DispatchQueue(label: "com.horologicalheartbeat.engine", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        captureCalibrationAnchor()

        // Sample every 1 second — fast enough to see micro-fluctuations,
        // cheap enough to run indefinitely.
        machTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.takeMachSample() }
        }

        // NTP query every 30 s — respectful of public time servers.
        ntpTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.takeNTPSample() }
        }

        // First NTP query immediately.
        takeNTPSample()
    }

    func stop() {
        machTimer?.invalidate()
        ntpTimer?.invalidate()
    }

    // MARK: - Calibration

    /// Snapshot both clocks simultaneously so all future diffs use the same origin.
    /// Called once at startup.
    private func captureCalibrationAnchor() {
        // Read both clocks as close together as possible to minimize the
        // uncertainty introduced by the gap between the two reads.
        calibrationMach = mach_absolute_time()
        calibrationWall = Date()
    }

    // MARK: - Mach drift measurement

    /// Compute how much the CPU oscillator has drifted from the wall clock
    /// since calibration, expressed in microseconds.
    ///
    /// Math:
    ///   machElapsed_ns   = (machNow − machBase) × (numer / denom)
    ///   wallElapsed_ns   = (wallNow − wallBase) × 1,000,000,000
    ///   drift_μs         = (machElapsed_ns − wallElapsed_ns) / 1,000
    ///
    /// A positive value means the CPU oscillator advanced *faster* than wall time.
    private func takeMachSample() {
        let machNow = mach_absolute_time()
        let wallNow = Date()

        // Ticks elapsed since calibration.
        let machTicks: UInt64 = machNow > calibrationMach
            ? machNow - calibrationMach
            : 0  // guard against unlikely wrap or backward clock

        // Convert ticks → nanoseconds using the CPU-specific timebase ratio.
        let machElapsed_ns = Double(machTicks) * Double(timebase.numer) / Double(timebase.denom)

        // Wall clock elapsed in nanoseconds.
        let wallElapsed_ns = wallNow.timeIntervalSince(calibrationWall) * 1_000_000_000.0

        // Net drift in microseconds.
        let drift_μs = (machElapsed_ns - wallElapsed_ns) / 1_000.0

        let sample = DriftSample(
            timestamp: wallNow,
            driftMicroseconds: drift_μs,
            ntpDelay: nil
        )

        store.append(sample)
        latestMachDrift = drift_μs
    }

    // MARK: - NTP measurement

    private func takeNTPSample() {
        // Honour Kiss-of-Death: RFC 4330 §8 requires we stop sending to this server.
        guard !ntpKissOfDeath else { return }

        let client = ntpClient
        backgroundQueue.async {
            client.query { result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(let ntp):
                        let offset_μs = ntp.offset * 1_000_000.0
                        self.latestNTPOffset = offset_μs
                        self.isNTPConnected = true
                        let sample = DriftSample(
                            timestamp: ntp.timestamp,
                            driftMicroseconds: offset_μs,
                            ntpDelay: ntp.roundTripDelay
                        )
                        self.store.appendNTP(sample)
                    case .failure(let error):
                        self.isNTPConnected = false
                        if case NTPError.kissOfDeath = error {
                            self.ntpKissOfDeath = true
                        }
                    }
                }
            }
        }
    }
}
