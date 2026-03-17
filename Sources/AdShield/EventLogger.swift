import Foundation

enum EventLogger {
    static let sdkVersion = "2.0.0"

    @available(iOS 13.0, *)
    static func log(endpoints: [String], deviceId: String, bundleId: String, results: [ProbeResult], sampleRatio: Double, transmissionIntervalMs: Int) async {
        let body = makeBody(deviceId: deviceId, bundleId: bundleId, results: results, sampleRatio: sampleRatio, transmissionIntervalMs: transmissionIntervalMs)
        await withTaskGroup(of: Void.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await send(to: endpoint, body: body)
                }
            }
        }
    }

    @available(iOS 13.0, *)
    private static func send(to endpoint: String, body: Data) async {
        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    static func logLegacy(endpoints: [String], deviceId: String, bundleId: String, results: [ProbeResult], sampleRatio: Double, transmissionIntervalMs: Int) {
        let body = makeBody(deviceId: deviceId, bundleId: bundleId, results: results, sampleRatio: sampleRatio, transmissionIntervalMs: transmissionIntervalMs)
        let group = DispatchGroup()
        for endpoint in endpoints {
            group.enter()
            sendLegacy(to: endpoint, body: body) { group.leave() }
        }
        group.wait()
    }

    private static func sendLegacy(to endpoint: String, body: Data, completion: @escaping () -> Void) {
        guard let url = URL(string: endpoint) else { completion(); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, _, _ in completion() }.resume()
    }

    private static func makeBody(deviceId: String, bundleId: String, results: [ProbeResult], sampleRatio: Double, transmissionIntervalMs: Int) -> Data {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let locale = Locale.current.identifier

        let resultsArray = results.map { r in
            ["url": r.url, "accessible": r.accessible] as [String: Any]
        }

        let payload: [String: Any] = [
            "deviceId": deviceId,
            "bundleId": bundleId,
            "platform": "ios",
            "sdkVersion": sdkVersion,
            "osVersion": osVersion,
            "locale": locale,
            "event_sample_rate": sampleRatio,
            "transmissionIntervalMs": transmissionIntervalMs,
            "results": resultsArray
        ]

        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}
