import Foundation
import os.log

public enum AdShield {

    private static let logger = OSLog(subsystem: "io.adshield", category: "AdShield")
    private static var measured = false
    private static let lock = NSLock()
    internal static var endpoint: String?

    public static func configure(endpoint: String) {
        self.endpoint = "https://\(endpoint)/bq/event"
    }

    public static func measure() {
        lock.lock()
        let alreadyMeasured = measured
        if !alreadyMeasured { measured = true }
        lock.unlock()

        if alreadyMeasured { return }

        guard let ep = endpoint else {
            os_log("AdShield.configure(endpoint:) must be called before measure()", log: logger, type: .error)
            return
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        if #available(iOS 13.0, *) {
            Task {
                do {
                    let result = try await AdBlockDetector.detect()
                    guard let isBlocked = result else {
                        os_log("Network offline, skipping", log: logger, type: .debug)
                        return
                    }
                    os_log("Adblock detected: %{public}@", log: logger, type: .debug, String(describing: isBlocked))
                    try await EventLogger.log(
                        endpoint: ep,
                        package: bundleId,
                        platform: "ios",
                        isAdBlockDetected: isBlocked
                    )
                } catch {
                    os_log("measure failed: %{public}@", log: logger, type: .error, error.localizedDescription)
                }
            }
        } else {
            DispatchQueue.global(qos: .utility).async {
                let semaphore = DispatchSemaphore(value: 0)
                var detectionResult: Bool?

                AdBlockDetector.detectLegacy { result in
                    detectionResult = result
                    semaphore.signal()
                }
                semaphore.wait()

                guard let isBlocked = detectionResult else {
                    os_log("Network offline, skipping", log: logger, type: .debug)
                    return
                }
                os_log("Adblock detected: %{public}@", log: logger, type: .debug, String(describing: isBlocked))
                EventLogger.logSync(
                    endpoint: ep,
                    package: bundleId,
                    platform: "ios",
                    isAdBlockDetected: isBlocked
                )
            }
        }
    }
}
