import Foundation
import os.log

public enum AdShield {
    private static let logger = OSLog(subsystem: "io.adshield", category: "AdShield")
    private static let lock = NSLock()
    private static var isMeasuring = false
    internal static var configEndpoint: String?

    private static let lastMeasuredKey = "io.adshield.lastMeasuredAt"
    private static let ttlKey = "io.adshield.ttlMs"
    private static let defaultTtlMs = 3_600_000 // 1 hour

    public static func configure(endpoint: String) {
        self.configEndpoint = endpoint
    }

    public static func measure() {
        lock.lock()
        let alreadyMeasuring = isMeasuring
        if !alreadyMeasuring { isMeasuring = true }
        lock.unlock()

        if alreadyMeasuring { return }

        guard let configUrl = configEndpoint else {
            os_log("AdShield.configure(endpoint:) must be called before measure()", log: logger, type: .error)
            resetMeasuring()
            return
        }

        let savedTtl = UserDefaults.standard.integer(forKey: ttlKey)
        let ttl = savedTtl > 0 ? savedTtl : defaultTtlMs
        if isTtlActive(ttlMs: ttl) {
            os_log("TTL active, skipping measurement", log: logger, type: .debug)
            resetMeasuring()
            return
        }

        if #available(iOS 13.0, *) {
            Task { await measureAsync(configUrl: configUrl) }
        } else {
            DispatchQueue.global(qos: .utility).async { measureLegacy(configUrl: configUrl) }
        }
    }

    @available(iOS 13.0, *)
    private static func measureAsync(configUrl: String) async {
        defer { resetMeasuring() }
        do {
            let config = try await ConfigProvider.fetch(from: configUrl)

            let sampleRatio = config.sampleRatio ?? 1.0
            let sampled = Double.random(in: 0..<1) < sampleRatio

            let deviceId = DeviceIdentifier.id
            let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
            let results = await AdBlockDetector.detect(urls: config.adblockDetectionUrls)

            os_log("Probed %d URLs, sampled: %{public}@", log: logger, type: .debug, results.count, String(describing: sampled))

            if sampled {
                await EventLogger.log(
                    endpoints: config.reportEndpoints,
                    deviceId: deviceId,
                    bundleId: bundleId,
                    results: results,
                    sampleRatio: sampleRatio,
                    transmissionIntervalMs: config.transmissionIntervalMs
                )
                os_log("Measurement complete, reported to %d endpoints", log: logger, type: .debug, config.reportEndpoints.count)
            }

            markMeasured(ttlMs: config.transmissionIntervalMs)
        } catch {
            markMeasured(ttlMs: defaultTtlMs)
            os_log("measure failed: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
    }

    private static func measureLegacy(configUrl: String) {
        defer { resetMeasuring() }
        let semaphore = DispatchSemaphore(value: 0)
        var fetchedConfig: AdShieldConfig?

        ConfigProvider.fetchLegacy(from: configUrl) { result in
            if case .success(let config) = result { fetchedConfig = config }
            semaphore.signal()
        }
        semaphore.wait()

        guard let config = fetchedConfig else {
            os_log("Config fetch failed", log: logger, type: .error)
            markMeasured(ttlMs: defaultTtlMs)
            return
        }

        let sampleRatio = config.sampleRatio ?? 1.0
        let sampled = Double.random(in: 0..<1) < sampleRatio

        let deviceId = DeviceIdentifier.id
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        let sem2 = DispatchSemaphore(value: 0)
        var results: [ProbeResult] = []
        AdBlockDetector.detectLegacy(urls: config.adblockDetectionUrls) { r in
            results = r
            sem2.signal()
        }
        sem2.wait()

        if sampled {
            EventLogger.logLegacy(
                endpoints: config.reportEndpoints,
                deviceId: deviceId,
                bundleId: bundleId,
                results: results,
                sampleRatio: sampleRatio,
                transmissionIntervalMs: config.transmissionIntervalMs
            )
        }

        markMeasured(ttlMs: config.transmissionIntervalMs)
    }

    private static func isTtlActive(ttlMs: Int) -> Bool {
        let lastMeasured = UserDefaults.standard.double(forKey: lastMeasuredKey)
        guard lastMeasured > 0 else { return false }
        let elapsed = Date().timeIntervalSince1970 - lastMeasured
        return elapsed < Double(ttlMs) / 1000.0
    }

    private static func markMeasured(ttlMs: Int) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastMeasuredKey)
        UserDefaults.standard.set(ttlMs, forKey: ttlKey)
    }

    private static func resetMeasuring() {
        lock.lock()
        isMeasuring = false
        lock.unlock()
    }
}
