import Foundation
import CryptoKit

struct AdShieldConfig: Decodable {
    let reportEndpoints: [String]
    let adblockDetectionUrls: [String]
    let transmissionIntervalMs: Int
    let sampleRatio: Double?
}

enum ConfigProvider {
    enum ConfigError: Error {
        case invalidURL
        case fetchFailed(Error)
        case decodeFailed(Error)
        case decryptionFailed
    }

    private static let aesKeyHex = "a6be11212141a6ba6cd7b9213fc4d84c98db63c2574824d452dcf56ee8cd6e42"

    private static func decrypt(_ base64String: String) throws -> Data {
        guard let raw = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ConfigError.decryptionFailed
        }
        guard raw.count > 12 else { throw ConfigError.decryptionFailed }

        let iv = raw.prefix(12)
        let ciphertextAndTag = raw.suffix(from: 12)

        var keyBytes: [UInt8] = []
        for i in stride(from: 0, to: aesKeyHex.count, by: 2) {
            let start = aesKeyHex.index(aesKeyHex.startIndex, offsetBy: i)
            let end = aesKeyHex.index(start, offsetBy: 2)
            guard let byte = UInt8(aesKeyHex[start..<end], radix: 16) else {
                throw ConfigError.decryptionFailed
            }
            keyBytes.append(byte)
        }
        let key = SymmetricKey(data: keyBytes)

        let sealedBox = try AES.GCM.SealedBox(combined: iv + ciphertextAndTag)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        return decrypted
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
            guard let base64String = String(data: data, encoding: .utf8) else {
                throw ConfigError.decryptionFailed
            }
            let decrypted = try decrypt(base64String)
            return try JSONDecoder().decode(AdShieldConfig.self, from: decrypted)
        } catch let error as ConfigError {
            throw error
        } catch let error as DecodingError {
            throw ConfigError.decodeFailed(error)
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
            guard let data = data,
                  let base64String = String(data: data, encoding: .utf8) else {
                completion(.failure(.fetchFailed(NSError(domain: "AdShield", code: -1))))
                return
            }
            do {
                let decrypted = try decrypt(base64String)
                let config = try JSONDecoder().decode(AdShieldConfig.self, from: decrypted)
                completion(.success(config))
            } catch let error as ConfigError {
                completion(.failure(error))
            } catch {
                completion(.failure(.decodeFailed(error)))
            }
        }.resume()
    }
}
