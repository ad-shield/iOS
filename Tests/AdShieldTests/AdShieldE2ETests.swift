import XCTest
import CryptoKit
@testable import AdShield

// Mock URL Protocol to intercept all network requests
class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var recordedRequests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.lock.lock()
        MockURLProtocol.recordedRequests.append(request)
        MockURLProtocol.lock.unlock()

        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class AdShieldE2ETests: XCTestCase {

    // Helper: encrypt a config JSON into the format ConfigProvider expects
    private func encryptConfig(_ config: [String: Any]) throws -> String {
        let json = try JSONSerialization.data(withJSONObject: config)
        let keyHex = "a6be11212141a6ba6cd7b9213fc4d84c98db63c2574824d452dcf56ee8cd6e42"
        var keyBytes: [UInt8] = []
        for i in stride(from: 0, to: keyHex.count, by: 2) {
            let start = keyHex.index(keyHex.startIndex, offsetBy: i)
            let end = keyHex.index(start, offsetBy: 2)
            keyBytes.append(UInt8(keyHex[start..<end], radix: 16)!)
        }
        let key = SymmetricKey(data: keyBytes)
        let sealed = try AES.GCM.seal(json, using: key)
        return sealed.combined!.base64EncodedString()
    }

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.recordedRequests = []
        MockURLProtocol.requestHandler = nil
        // Reset AdShield state
        UserDefaults.standard.removeObject(forKey: "io.adshield.nextAllowedAt")
        UserDefaults.standard.removeObject(forKey: "io.adshield.deviceId")
        AdShield.configEndpoint = nil
        if #available(iOS 13.0, *) {
            AdShield._resetForTesting()
        }
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        UserDefaults.standard.removeObject(forKey: "io.adshield.nextAllowedAt")
        UserDefaults.standard.removeObject(forKey: "io.adshield.deviceId")
        super.tearDown()
    }

    // Helper to make an encrypted config with given parameters
    private func makeConfig(
        sampleRatio: Double? = 1.0,
        transmissionIntervalMs: Int = 60000,
        detectionUrls: [String] = ["https://probe1.test/ad.js", "https://probe2.test/ad.js"],
        reportEndpoints: [String] = ["https://report.test/event"]
    ) throws -> String {
        var config: [String: Any] = [
            "adblockDetectionUrls": detectionUrls,
            "reportEndpoints": reportEndpoints,
            "transmissionIntervalMs": transmissionIntervalMs
        ]
        if let ratio = sampleRatio {
            config["sampleRatio"] = ratio
        }
        return try encryptConfig(config)
    }

    // MARK: - Sample Rate Tests

    func testSampleRateZero_noTransmission() async throws {
        // With sampleRatio=0, detection and transmission should be skipped
        let encryptedConfig = try makeConfig(sampleRatio: 0.0)
        var reportReceived = false

        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("config.test") {
                // Serve config
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, encryptedConfig.data(using: .utf8)!)
            }
            if url.contains("report.test") {
                reportReceived = true
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        AdShield.configure(endpoint: "https://config.test/config")
        AdShield.measure()

        // Wait for async work
        try await Task.sleep(nanoseconds: 3_000_000_000)

        XCTAssertFalse(reportReceived, "No event should be sent when sampleRatio is 0")
        // Verify NO probe requests were made (sampling skips detection entirely)
        let probeRequests = MockURLProtocol.recordedRequests.filter { $0.url?.host?.contains("probe") == true }
        XCTAssertEqual(probeRequests.count, 0, "No probe requests when not sampled")
    }

    func testSampleRateOne_transmissionOccurs() async throws {
        // With sampleRatio=1.0, detection and transmission should always happen
        let encryptedConfig = try makeConfig(sampleRatio: 1.0)
        var reportReceived = false
        var reportBody: Data?

        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("config.test") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, encryptedConfig.data(using: .utf8)!)
            }
            if url.contains("report.test") {
                reportReceived = true
                // Read the body from the request
                if let stream = request.httpBodyStream {
                    stream.open()
                    var data = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    while stream.hasBytesAvailable {
                        let read = stream.read(buffer, maxLength: 4096)
                        if read > 0 { data.append(buffer, count: read) }
                    }
                    buffer.deallocate()
                    stream.close()
                    reportBody = data
                } else {
                    reportBody = request.httpBody
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        AdShield.configure(endpoint: "https://config.test/config")
        AdShield.measure()

        try await Task.sleep(nanoseconds: 3_000_000_000)

        XCTAssertTrue(reportReceived, "Event should be sent when sampleRatio is 1.0")
        XCTAssertNotNil(reportBody, "Report body should not be nil")
    }

    // MARK: - Transmission Interval Tests

    func testLowTransmissionInterval_allowsNextMeasureQuickly() async throws {
        let encryptedConfig = try makeConfig(transmissionIntervalMs: 1000) // 1 second

        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("config.test") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, encryptedConfig.data(using: .utf8)!)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        AdShield.configure(endpoint: "https://config.test/config")
        AdShield.measure()
        try await Task.sleep(nanoseconds: 3_000_000_000) // Wait for first measure

        // After 1 second interval, nextAllowed should have passed
        let nextAllowed = UserDefaults.standard.double(forKey: "io.adshield.nextAllowedAt")
        XCTAssertTrue(nextAllowed > 0, "nextAllowedAt should be set")
        XCTAssertTrue(Date().timeIntervalSince1970 >= nextAllowed, "With 1s interval, should already be allowed again")
    }

    func testHighTransmissionInterval_blocksNextMeasure() async throws {
        let encryptedConfig = try makeConfig(transmissionIntervalMs: 3_600_000) // 1 hour

        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("config.test") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, encryptedConfig.data(using: .utf8)!)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        AdShield.configure(endpoint: "https://config.test/config")
        AdShield.measure()
        try await Task.sleep(nanoseconds: 3_000_000_000) // Wait for first measure

        let nextAllowed = UserDefaults.standard.double(forKey: "io.adshield.nextAllowedAt")
        XCTAssertTrue(nextAllowed > 0, "nextAllowedAt should be set")
        XCTAssertTrue(Date().timeIntervalSince1970 < nextAllowed, "With 1hr interval, should still be throttled")
    }

    // MARK: - Detection URL Tests

    func testProbesConfiguredUrls() async throws {
        let detectionUrls = ["https://probe-a.test/ad.js", "https://probe-b.test/ad.js", "https://probe-c.test/tracker.js"]
        let encryptedConfig = try makeConfig(detectionUrls: detectionUrls)
        var probedHosts: [String] = []
        let probeLock = NSLock()

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.absoluteString.contains("config.test") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, encryptedConfig.data(using: .utf8)!)
            }
            if url.host?.contains("probe") == true {
                probeLock.lock()
                probedHosts.append(url.absoluteString)
                probeLock.unlock()
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        AdShield.configure(endpoint: "https://config.test/config")
        AdShield.measure()
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // All configured detection URLs should be probed
        for detectionUrl in detectionUrls {
            XCTAssertTrue(probedHosts.contains(detectionUrl), "Should probe configured URL: \(detectionUrl)")
        }
    }

    // MARK: - Event Endpoint Tests

    func testResultsSentToConfiguredEndpoints() async throws {
        let reportEndpoints = ["https://report-a.test/event", "https://report-b.test/event"]
        let encryptedConfig = try makeConfig(reportEndpoints: reportEndpoints)
        var reportHosts: [String] = []
        let reportLock = NSLock()

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.absoluteString.contains("config.test") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, encryptedConfig.data(using: .utf8)!)
            }
            if url.host?.contains("report") == true {
                reportLock.lock()
                reportHosts.append(url.absoluteString)
                reportLock.unlock()
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        AdShield.configure(endpoint: "https://config.test/config")
        AdShield.measure()
        try await Task.sleep(nanoseconds: 3_000_000_000)

        for endpoint in reportEndpoints {
            XCTAssertTrue(reportHosts.contains(endpoint), "Should send results to: \(endpoint)")
        }
    }

    func testEventPayloadContainsDetectionResults() async throws {
        let encryptedConfig = try makeConfig(
            detectionUrls: ["https://probe1.test/ad.js"],
            reportEndpoints: ["https://report.test/event"]
        )
        var reportBody: [String: Any]?

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.absoluteString.contains("config.test") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, encryptedConfig.data(using: .utf8)!)
            }
            if url.host?.contains("report") == true {
                if let stream = request.httpBodyStream {
                    stream.open()
                    var data = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    while stream.hasBytesAvailable {
                        let read = stream.read(buffer, maxLength: 4096)
                        if read > 0 { data.append(buffer, count: read) }
                    }
                    buffer.deallocate()
                    stream.close()
                    reportBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                } else if let body = request.httpBody {
                    reportBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                }
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        AdShield.configure(endpoint: "https://config.test/config")
        AdShield.measure()
        try await Task.sleep(nanoseconds: 3_000_000_000)

        XCTAssertNotNil(reportBody, "Report body should be valid JSON")
        XCTAssertEqual(reportBody?["platform"] as? String, "ios")
        XCTAssertNotNil(reportBody?["deviceId"])
        XCTAssertNotNil(reportBody?["results"])

        if let results = reportBody?["results"] as? [[String: Any]] {
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?["url"] as? String, "https://probe1.test/ad.js")
            XCTAssertNotNil(results.first?["accessible"])
        }
    }
}
