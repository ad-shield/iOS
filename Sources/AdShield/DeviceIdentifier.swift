import Foundation

enum DeviceIdentifier {
    private static let key = "io.adshield.deviceId"

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}
