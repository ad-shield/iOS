import Foundation

enum EventLogger {

    @available(iOS 13.0, *)
    static func log(endpoint: String, package: String, platform: String, isAdBlockDetected: Bool) async throws {
        guard let url = URL(string: endpoint) else { return }
        let body = makeBody(package: package, platform: platform, isAdBlockDetected: isAdBlockDetected)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    static func logSync(endpoint: String, package: String, platform: String, isAdBlockDetected: Bool) {
        guard let url = URL(string: endpoint) else { return }
        let body = makeBody(package: package, platform: platform, isAdBlockDetected: isAdBlockDetected)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        request.httpBody = body
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            semaphore.signal()
        }.resume()
        semaphore.wait()
    }

    private static func makeBody(package: String, platform: String, isAdBlockDetected: Bool) -> Data {
        let eventId = UUID().uuidString
        let json = """
        {"table":"mobile_measure","data":[{"event_id":"\(eventId)","package":"\(package)","platform":"\(platform)","is_adblock_detected":\(isAdBlockDetected)}]}
        """
        return Data(json.utf8)
    }
}
