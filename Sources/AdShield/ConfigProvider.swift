import Foundation

struct AdShieldConfig: Decodable {
    let reportEndpoints: [String]
    let adblockDetectionUrls: [String]
    let transmissionIntervalMs: Int
}

enum ConfigProvider {
    enum ConfigError: Error {
        case invalidURL
        case fetchFailed(Error)
        case decodeFailed(Error)
    }

    @available(iOS 13.0, *)
    static func fetch(from endpoint: String) async throws -> AdShieldConfig {
        guard let url = URL(string: endpoint) else {
            throw ConfigError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(AdShieldConfig.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.decodeFailed(error)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.fetchFailed(error)
        }
    }

    static func fetchLegacy(from endpoint: String, completion: @escaping (Result<AdShieldConfig, ConfigError>) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(.fetchFailed(error)))
                return
            }
            guard let data = data else {
                completion(.failure(.fetchFailed(NSError(domain: "AdShield", code: -1))))
                return
            }
            do {
                let config = try JSONDecoder().decode(AdShieldConfig.self, from: data)
                completion(.success(config))
            } catch {
                completion(.failure(.decodeFailed(error)))
            }
        }.resume()
    }
}
