import Foundation
import Network

// NTP uses its own epoch: January 1, 1900.
// Unix epoch is January 1, 1970.
// The gap is exactly 70 years = 2208988800 seconds.
private let ntpEpochOffset: TimeInterval = 2_208_988_800

/// Result of one NTP exchange. The offset is the signed difference
/// between the server's true time and our local clock, in seconds.
struct NTPResult {
    /// Signed offset: positive = our clock is behind, negative = ahead.
    let offset: TimeInterval
    /// Round-trip delay, useful for weighting this sample's quality.
    let roundTripDelay: TimeInterval
    /// Wall-clock moment when this measurement was completed.
    let timestamp: Date
}

/// Minimal SNTP client (RFC 4330) over UDP using Network.framework.
///
/// One request/response per call to `query(server:completion:)`.
/// Reuses no state — safe to call from any queue.
final class NTPClient: @unchecked Sendable {

    // MARK: - Public

    func query(server: String = "time.apple.com", completion: @escaping (Result<NTPResult, Error>) -> Void) {
        // Port 123 is the IANA-assigned NTP port and is always a valid port number,
        // but we avoid the force-unwrap to keep crash surface zero.
        guard let port = NWEndpoint.Port(rawValue: 123) else {
            completion(.failure(NTPError.internalError("invalid port")))
            return
        }

        let host = NWEndpoint.Host(server)
        let params = NWParameters.udp
        let connection = NWConnection(host: host, port: port, using: params)

        // Track whether we've already called completion so we never call it twice,
        // regardless of which error/timeout/success path fires first.
        let lock = NSLock()
        var completed = false
        let completionOnce: (Result<NTPResult, Error>) -> Void = { result in
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            completion(result)
        }

        // Timeout: cancel the connection after 5 s if we get no response.
        // Without this, a dropped UDP packet leaks the NWConnection and completion
        // closure indefinitely; repeated 30 s queries would pile up.
        let timeoutWork = DispatchWorkItem {
            completionOnce(.failure(NTPError.timeout))
            connection.cancel()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutWork)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.sendRequest(on: connection, timeout: timeoutWork, completion: completionOnce)
            case .failed(let error):
                timeoutWork.cancel()
                completionOnce(.failure(error))
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - Private

    private func sendRequest(
        on connection: NWConnection,
        timeout: DispatchWorkItem,
        completion: @escaping (Result<NTPResult, Error>) -> Void
    ) {
        var packet = [UInt8](repeating: 0, count: 48)

        // Byte 0 = LI (00) | VN (011 = v3) | Mode (011 = client) = 0b00_011_011 = 0x1B
        packet[0] = 0x1B

        // Record t1: the moment we transmit, in NTP seconds.
        let t1 = Date().timeIntervalSince1970 + ntpEpochOffset

        connection.send(content: Data(packet), completion: .contentProcessed { error in
            if let error = error {
                timeout.cancel()
                completion(.failure(error))
                connection.cancel()
                return
            }

            connection.receive(minimumIncompleteLength: 48, maximumLength: 1024) { content, _, _, error in
                // t4: wall-clock time we received the response.
                let t4 = Date().timeIntervalSince1970 + ntpEpochOffset
                timeout.cancel()

                if let error = error {
                    completion(.failure(error))
                    connection.cancel()
                    return
                }

                guard let bytes = content, bytes.count >= 48 else {
                    completion(.failure(NTPError.shortResponse))
                    connection.cancel()
                    return
                }

                // --- Validate the response packet (RFC 4330 §5) ---
                //
                // Several fields must be checked before trusting the timestamps.
                // An unvalidated NTP response could carry wildly wrong data —
                // either from a misconfigured server or a spoofed packet on the LAN.

                let byte0    = bytes[0]
                let leapIndicator = (byte0 >> 6) & 0x03
                let version       = (byte0 >> 3) & 0x07
                let mode          = byte0 & 0x07
                let stratum       = bytes[1]

                // LI=3 means the server's own clock is unsynchronized.
                if leapIndicator == 3 {
                    completion(.failure(NTPError.serverUnsynchronized))
                    connection.cancel()
                    return
                }

                // Mode must be 4 (server) or 5 (broadcast). Anything else
                // (e.g. 3=client, 6=control) is not a valid time response.
                guard mode == 4 || mode == 5 else {
                    completion(.failure(NTPError.invalidMode(mode)))
                    connection.cancel()
                    return
                }

                // Version must be 3 or 4.
                guard version == 3 || version == 4 else {
                    completion(.failure(NTPError.invalidVersion(version)))
                    connection.cancel()
                    return
                }

                // Stratum 0 = "Kiss-of-Death" (KoD) — server is telling us to stop.
                // Stratum 16+ = server is unsynchronized.
                // RFC 4330 §8: clients MUST NOT send to a server that sent KoD.
                // We treat KoD as a fatal error so the caller can back off.
                guard stratum >= 1 && stratum <= 15 else {
                    let code = stratum == 0 ? NTPError.kissOfDeath : NTPError.serverUnsynchronized
                    completion(.failure(code))
                    connection.cancel()
                    return
                }

                // --- Parse server timestamps ---
                //
                // NTP timestamps occupy 8 bytes each: 4 bytes of seconds + 4 bytes of
                // sub-second fraction (fixed-point, where the fraction denominator is 2^32).
                //
                // t2 lives at byte offset 32 (server receive timestamp).
                // t3 lives at byte offset 40 (server transmit timestamp).

                guard let t2 = Self.readNTPTimestamp(from: bytes, at: 32),
                      let t3 = Self.readNTPTimestamp(from: bytes, at: 40) else {
                    completion(.failure(NTPError.zeroTimestamp))
                    connection.cancel()
                    return
                }

                // --- Four-timestamp offset formula (RFC 5905 §8) ---
                //
                //  round-trip delay  δ = (t4 − t1) − (t3 − t2)
                //  clock offset      θ = ((t2 − t1) + (t3 − t4)) / 2
                //
                // A negative delay indicates the packet arrived before it was sent —
                // physically impossible, meaning the response is malformed or spoofed.

                let delay  = (t4 - t1) - (t3 - t2)
                let offset = ((t2 - t1) + (t3 - t4)) / 2

                guard delay >= 0 else {
                    completion(.failure(NTPError.negativeDelay))
                    connection.cancel()
                    return
                }

                let result = NTPResult(
                    offset: offset,
                    roundTripDelay: delay,
                    timestamp: Date()
                )
                completion(.success(result))
                connection.cancel()
            }
        })
    }

    /// Read a 64-bit NTP timestamp (seconds + fraction) from `data` at `byteOffset`.
    /// Returns nil if either the seconds or fraction fields are zero (zero timestamp =
    /// server has not set its clock) or if the offset would read out of bounds.
    private static func readNTPTimestamp(from data: Data, at byteOffset: Int) -> TimeInterval? {
        // Bounds check: we need 8 bytes starting at byteOffset.
        guard byteOffset >= 0, byteOffset + 8 <= data.count else { return nil }

        let seconds  = data.readUInt32BE(at: byteOffset)
        let fraction = data.readUInt32BE(at: byteOffset + 4)

        // A zero transmit timestamp means the server never set it — reject.
        guard seconds != 0 else { return nil }

        // Convert fixed-point fraction to fractional seconds.
        // The 32-bit fraction field represents (value / 2^32) seconds.
        let fractionalSeconds = Double(fraction) / 4_294_967_296.0

        return Double(seconds) + fractionalSeconds
    }
}

// MARK: - Errors

enum NTPError: Error, LocalizedError {
    case shortResponse
    case timeout
    case serverUnsynchronized
    case kissOfDeath
    case negativeDelay
    case zeroTimestamp
    case invalidMode(UInt8)
    case invalidVersion(UInt8)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .shortResponse:        return "NTP response too short"
        case .timeout:              return "NTP query timed out"
        case .serverUnsynchronized: return "NTP server is unsynchronized (LI=3 or stratum≥16)"
        case .kissOfDeath:          return "NTP server sent Kiss-of-Death (stratum=0)"
        case .negativeDelay:        return "NTP response has negative round-trip delay (malformed/spoofed)"
        case .zeroTimestamp:        return "NTP server returned zero transmit timestamp"
        case .invalidMode(let m):   return "NTP response has unexpected mode \(m) (expected 4 or 5)"
        case .invalidVersion(let v):return "NTP response has unexpected version \(v) (expected 3 or 4)"
        case .internalError(let s): return "NTP internal error: \(s)"
        }
    }
}

// MARK: - Data helpers

private extension Data {
    /// Read a big-endian UInt32 at a byte offset.
    /// Caller is responsible for ensuring `offset + 3 < count`.
    func readUInt32BE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}
