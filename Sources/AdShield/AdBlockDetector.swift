import Foundation

enum AdBlockDetector {

    private static let controlURL = URL(string: "https://www.google.com")!
    private static let adURL = URL(string: "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js")!
    private static let timeoutInterval: TimeInterval = 5

    /// Returns `true` if adblock detected, `false` if not, `nil` if network offline.
    @available(iOS 13.0, *)
    static func detect() async throws -> Bool? {
        let controlOk = await probe(controlURL)
        if !controlOk { return nil }
        let adOk = await probe(adURL)
        return !adOk
    }

    @available(iOS 13.0, *)
    private static func probe(_ url: URL) async -> Bool {
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

    static func detectLegacy(completion: @escaping (Bool?) -> Void) {
        probeLegacy(controlURL) { controlOk in
            if !controlOk {
                completion(nil)
                return
            }
            probeLegacy(adURL) { adOk in
                completion(!adOk)
            }
        }
    }

    private static func probeLegacy(_ url: URL, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeoutInterval
        URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil {
                completion(false)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(false)
                return
            }
            completion((200...399).contains(http.statusCode))
        }.resume()
    }
}
