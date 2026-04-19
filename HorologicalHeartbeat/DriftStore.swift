import Foundation

// MARK: - DriftStore

/// Thread-safe circular buffer holding up to 24 hours of drift samples.
///
/// Why a circular buffer?
///   At 1 sample/second, 24 hours = 86,400 samples.
///   A circular buffer pre-allocates that space once and never deallocates,
///   avoiding heap churn that would show up as GC pauses in the waveform.
///
/// The buffer is implemented as a fixed-size array with a write-head index.
/// When the buffer is full, new writes overwrite the oldest entry.
struct DriftStore {

    // 24 hours × 3600 s/hr = 86,400 mach samples + 2,880 NTP samples (30 s interval)
    static let machCapacity = 86_400
    static let ntpCapacity  = 2_880

    // MARK: - Storage

    private(set) var machSamples: [DriftSample] = []
    private(set) var ntpSamples:  [DriftSample] = []

    private var machHead: Int = 0
    private var ntpHead:  Int = 0
    private var machFull: Bool = false
    private var ntpFull:  Bool = false

    // MARK: - Write

    mutating func append(_ sample: DriftSample) {
        if machSamples.count < Self.machCapacity {
            machSamples.append(sample)
        } else {
            machFull = true
            machSamples[machHead] = sample
            machHead = (machHead + 1) % Self.machCapacity
        }
    }

    mutating func appendNTP(_ sample: DriftSample) {
        if ntpSamples.count < Self.ntpCapacity {
            ntpSamples.append(sample)
        } else {
            ntpFull = true
            ntpSamples[ntpHead] = sample
            ntpHead = (ntpHead + 1) % Self.ntpCapacity
        }
    }

    // MARK: - Read (chronological order)

    /// Returns mach samples in chronological order, newest last.
    var orderedMachSamples: [DriftSample] {
        guard machFull else { return machSamples }
        // When full the buffer has wrapped; the oldest entry is at `machHead`.
        return Array(machSamples[machHead...]) + Array(machSamples[..<machHead])
    }

    /// Last `count` mach samples in chronological order.
    func recentMachSamples(count: Int) -> [DriftSample] {
        let all = orderedMachSamples
        guard all.count > count else { return all }
        return Array(all.suffix(count))
    }

    // MARK: - Statistics

    /// Rolling statistics over the last N samples.
    struct Stats {
        let mean: Double          // μs
        let stdDev: Double        // μs
        let min: Double           // μs
        let max: Double           // μs
        /// Projected drift if the current rate continued for 24 hours, in seconds.
        let projectedDailyDrift: Double
        let sampleCount: Int
    }

    func stats(over windowSize: Int = 3600) -> Stats {
        let samples = recentMachSamples(count: windowSize).map(\.driftMicroseconds)
        guard !samples.isEmpty else {
            return Stats(mean: 0, stdDev: 0, min: 0, max: 0, projectedDailyDrift: 0, sampleCount: 0)
        }

        let n = Double(samples.count)
        let mean = samples.reduce(0, +) / n
        let variance = samples.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
        let stdDev = variance.squareRoot()
        // min()/max() are safe here because the guard above ensures samples is non-empty,
        // but we avoid force-unwrap in case this logic is ever refactored.
        guard let minVal = samples.min(), let maxVal = samples.max() else {
            return Stats(mean: 0, stdDev: 0, min: 0, max: 0, projectedDailyDrift: 0, sampleCount: 0)
        }

        // Projected daily drift:
        // The drift we've measured is cumulative since calibration.
        // Rate = latestDrift_μs / elapsed_seconds.
        // Daily = rate * 86400 / 1_000_000 (convert μs → s).
        let latestDrift = samples.last ?? 0
        let elapsedSeconds = Double(samples.count)   // ~1 sample/s
        let dailyDrift_s = elapsedSeconds > 0
            ? (latestDrift / elapsedSeconds) * 86_400.0 / 1_000_000.0
            : 0

        return Stats(
            mean: mean,
            stdDev: stdDev,
            min: minVal,
            max: maxVal,
            projectedDailyDrift: dailyDrift_s,
            sampleCount: samples.count
        )
    }

    // MARK: - Moving average

    /// Apply a simple moving average to reduce high-frequency noise for display.
    /// Window size controls smoothing: larger = smoother waveform.
    func movingAverage(of samples: [DriftSample], window: Int) -> [Double] {
        guard window > 1 else { return samples.map(\.driftMicroseconds) }

        var result = [Double](repeating: 0, count: samples.count)
        var runningSum = 0.0

        for i in 0..<samples.count {
            runningSum += samples[i].driftMicroseconds
            if i >= window {
                runningSum -= samples[i - window].driftMicroseconds
            }
            let count = min(i + 1, window)
            result[i] = runningSum / Double(count)
        }

        return result
    }
}
