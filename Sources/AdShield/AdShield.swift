import Foundation
import os.log

public enum AdShield {
    private static let logger = OSLog(subsystem: "io.adshield", category: "AdShield")
    private static let lock = NSLock()
    private static var isMeasuring = false
    internal static var configEndpoint: String?

    private static let nextAllowedKey = "io.adshield.nextAllowedAt"
    private static let errorCooldownMs = 86_400_000 // 24 hours

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

        let nextAllowed = UserDefaults.standard.double(forKey: nextAllowedKey)
        if nextAllowed > 0 && Date().timeIntervalSince1970 < nextAllowed {
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

            if !sampled {
                scheduleNext(intervalMs: config.transmissionIntervalMs)
                return
            }

            let deviceId = DeviceIdentifier.id
            let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
            let results = await AdBlockDetector.detect(urls: config.adblockDetectionUrls)

            await EventLogger.log(
                endpoints: config.reportEndpoints,
                deviceId: deviceId,
                bundleId: bundleId,
                results: results,
                sampleRatio: sampleRatio,
                transmissionIntervalMs: config.transmissionIntervalMs
            )

            scheduleNext(intervalMs: config.transmissionIntervalMs)
        } catch {
            scheduleNext(intervalMs: errorCooldownMs)
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
            scheduleNext(intervalMs: errorCooldownMs)
            return
        }

        let sampleRatio = config.sampleRatio ?? 1.0
        let sampled = Double.random(in: 0..<1) < sampleRatio

        if !sampled {
            scheduleNext(intervalMs: config.transmissionIntervalMs)
            return
        }

        let deviceId = DeviceIdentifier.id
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        let sem2 = DispatchSemaphore(value: 0)
        var results: [ProbeResult] = []
        AdBlockDetector.detectLegacy(urls: config.adblockDetectionUrls) { r in
            results = r
            sem2.signal()
        }
        sem2.wait()

        EventLogger.logLegacy(
            endpoints: config.reportEndpoints,
            deviceId: deviceId,
            bundleId: bundleId,
            results: results,
            sampleRatio: sampleRatio,
            transmissionIntervalMs: config.transmissionIntervalMs
        )

        scheduleNext(intervalMs: config.transmissionIntervalMs)
    }

    private static func scheduleNext(intervalMs: Int) {
        let nextAllowed = Date().timeIntervalSince1970 + Double(intervalMs) / 1000.0
        UserDefaults.standard.set(nextAllowed, forKey: nextAllowedKey)
    }

    private static func resetMeasuring() {
        lock.lock()
        isMeasuring = false
        lock.unlock()
    }
}
