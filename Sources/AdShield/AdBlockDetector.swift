import Foundation

struct ProbeResult {
    let url: String
    let accessible: Bool
}

enum AdBlockDetector {
    private static let timeoutInterval: TimeInterval = 5
    private static let maxRetries = 3

    @available(iOS 13.0, *)
    static func detect(urls: [String]) async -> [ProbeResult] {
        await withTaskGroup(of: ProbeResult.self) { group in
            for urlString in urls {
                group.addTask {
                    let accessible = await probeWithRetry(urlString)
                    return ProbeResult(url: urlString, accessible: accessible)
                }
            }
            var results: [ProbeResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    @available(iOS 13.0, *)
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

    @available(iOS 13.0, *)
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

    static func detectLegacy(urls: [String], completion: @escaping ([ProbeResult]) -> Void) {
        let group = DispatchGroup()
        var results: [ProbeResult] = []
        let lock = NSLock()

        for urlString in urls {
            group.enter()
            probeWithRetryLegacy(urlString, attemptsLeft: maxRetries) { accessible in
                lock.lock()
                results.append(ProbeResult(url: urlString, accessible: accessible))
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .utility)) {
            completion(results)
        }
    }

    private static func probeWithRetryLegacy(_ urlString: String, attemptsLeft: Int, completion: @escaping (Bool) -> Void) {
        probeLegacy(urlString) { success in
            if success || attemptsLeft <= 1 {
                completion(success)
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    probeWithRetryLegacy(urlString, attemptsLeft: attemptsLeft - 1, completion: completion)
                }
            }
        }
    }

    private static func probeLegacy(_ urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeoutInterval
        URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil { completion(false); return }
            guard let http = response as? HTTPURLResponse else { completion(false); return }
            completion((200...399).contains(http.statusCode))
        }.resume()
    }
}
