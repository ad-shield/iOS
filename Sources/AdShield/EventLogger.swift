import Foundation

enum EventLogger {
    static let sdkVersion = "0.0.7"

    static func log(endpoints: [String], deviceId: String, bundleId: String, results: [ProbeResult], sampleRatio: Double, transmissionIntervalMs: Int, kv: [String: String]) async {
        let body = makeBody(deviceId: deviceId, bundleId: bundleId, results: results, sampleRatio: sampleRatio, transmissionIntervalMs: transmissionIntervalMs, kv: kv)
        await withTaskGroup(of: Void.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await send(to: endpoint, body: body)
                }
            }
        }
    }

    private static func send(to endpoint: String, body: Data) async {
        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func makeBody(deviceId: String, bundleId: String, results: [ProbeResult], sampleRatio: Double, transmissionIntervalMs: Int, kv: [String: String]) -> Data {
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
            "sampleRatio": sampleRatio,
            "transmissionIntervalMs": transmissionIntervalMs,
            "results": resultsArray,
            "kv": kv
        ]

        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}
