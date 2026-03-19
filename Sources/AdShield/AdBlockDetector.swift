import Foundation

struct ProbeResult {
    let url: String
    let accessible: Bool
}

enum AdBlockDetector {
    private static let timeoutInterval: TimeInterval = 5
    private static let maxRetries = 3
    private static let maxConcurrency = 4

    static func detect(urls: [String]) async -> [ProbeResult] {
        guard !urls.isEmpty else { return [] }
        var results: [ProbeResult] = []
        await withTaskGroup(of: ProbeResult.self) { group in
            var index = 0
            let initialBatch = min(maxConcurrency, urls.count)
            for i in 0..<initialBatch {
                let urlString = urls[i]
                group.addTask {
                    let accessible = await probeWithRetry(urlString)
                    return ProbeResult(url: urlString, accessible: accessible)
                }
            }
            index = initialBatch
            for await result in group {
                results.append(result)
                if index < urls.count {
                    let urlString = urls[index]
                    index += 1
                    group.addTask {
                        let accessible = await probeWithRetry(urlString)
                        return ProbeResult(url: urlString, accessible: accessible)
                    }
                }
            }
        }
        return results
    }

    private static func probeWithRetry(_ urlString: String) async -> Bool {
        for attempt in 0..<maxRetries {
            if await probe(urlString) {
                return true
            }
            if attempt < maxRetries - 1 {
                try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
            }
        }
        return false
    }

    private static func probe(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = timeoutInterval
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...399).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
