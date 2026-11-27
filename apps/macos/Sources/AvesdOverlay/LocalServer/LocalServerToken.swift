import AvesdEnvironment
import Foundation
import Security

struct LocalServerToken {
    let service: String

    private var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "api-token"]
    }

    func value(reset: Bool) throws -> String {
        var query = item
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess && !reset {
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
                throw keychainError(errSecDecode)
            }
            return value
        }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw keychainError(randomStatus) }
        let value = Data(bytes).base64EncodedString()
        let update = [kSecValueData as String: Data(value.utf8)]
        let saved: OSStatus
        if status == errSecItemNotFound {
            saved = SecItemAdd(item.merging(update) { _, new in new } as CFDictionary, nil)
            if saved == errSecDuplicateItem && !reset { return try self.value(reset: false) }
        } else {
            saved = SecItemUpdate(item as CFDictionary, update as CFDictionary)
        }
        guard saved == errSecSuccess else { throw keychainError(saved) }
        return value
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String?
            ?? SettingsText.serverKeychainError(Int(status)).string
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
