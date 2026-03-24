import Foundation
import os.log

public enum AdShield {
    private static let logger = OSLog(subsystem: "io.adshield", category: "AdShield")
    private static let lock = NSLock()
    private static var isMeasuring = false
    internal static var configEndpoint: String?
    internal static var kv: [String: String] = [:]

    private static let nextAllowedKey = "io.adshield.nextAllowedAt"
    private static let errorCooldownMs = 86_400_000 // 24 hours

    public static func configure(endpoint: String, kv: [String: String] = [:]) {
        self.configEndpoint = endpoint
        self.kv = kv
    }

    public static func measure() {
        lock.lock()
        let alreadyMeasuring = isMeasuring
        if !alreadyMeasuring { isMeasuring = true }
        lock.unlock()

        if alreadyMeasuring {
            os_log("Skipping: measurement already in progress", log: logger, type: .debug)
            return
        }

        guard let configUrl = configEndpoint else {
            os_log("AdShield.configure(endpoint:) must be called before measure()", log: logger, type: .error)
            resetMeasuring()
            return
        }

        let nextAllowed = UserDefaults.standard.double(forKey: nextAllowedKey)
        if nextAllowed > 0 && Date().timeIntervalSince1970 < nextAllowed {
            let remainingSec = Int(nextAllowed - Date().timeIntervalSince1970)
            os_log("Skipping: throttled, next allowed in %d seconds", log: logger, type: .debug, remainingSec)
            resetMeasuring()
            return
        }

        Task { await measureAsync(configUrl: configUrl) }
    }

    private static func measureAsync(configUrl: String) async {
        defer { resetMeasuring() }
        do {
            let config = try await ConfigProvider.fetch(from: configUrl)

            let sampleRatio = config.sampleRatio ?? 1.0
            let sampled = Double.random(in: 0..<1) < sampleRatio

            if !sampled {
                os_log("Skipping transmission: not sampled (sampleRatio=%.3f)", log: logger, type: .debug, sampleRatio)
                scheduleNext(intervalMs: config.transmissionIntervalMs)
                return
            }

            let deviceId = DeviceIdentifier.id
            let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
            let results = await AdBlockDetector.detect(urls: config.adblockDetectionUrls)

            let accessibleCount = results.filter { $0.accessible }.count
            let blockedCount = results.count - accessibleCount
            os_log("Detection complete: %d accessible, %d blocked out of %d URLs", log: logger, type: .debug, accessibleCount, blockedCount, results.count)

            await EventLogger.log(
                endpoints: config.reportEndpoints,
                deviceId: deviceId,
                bundleId: bundleId,
                results: results,
                sampleRatio: sampleRatio,
                transmissionIntervalMs: config.transmissionIntervalMs,
                kv: kv
            )

            os_log("Event sent successfully to %d endpoint(s)", log: logger, type: .debug, config.reportEndpoints.count)
            scheduleNext(intervalMs: config.transmissionIntervalMs)
        } catch {
            scheduleNext(intervalMs: errorCooldownMs)
            os_log("measure failed: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
    }

    private static func scheduleNext(intervalMs: Int) {
        let nextAllowed = Date().timeIntervalSince1970 + Double(intervalMs) / 1000.0
        UserDefaults.standard.set(nextAllowed, forKey: nextAllowedKey)
        UserDefaults.standard.synchronize()
    }

    private static func resetMeasuring() {
        lock.lock()
        isMeasuring = false
        lock.unlock()
    }

    internal static func _resetForTesting() {
        lock.lock()
        isMeasuring = false
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: nextAllowedKey)
        kv = [:]
    }
}
