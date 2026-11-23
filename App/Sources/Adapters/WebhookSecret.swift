import Foundation
import Security

/// The webhook auth header, one `Name: value` line, in the login keychain rather than UserDefaults' readable plist.
enum WebhookSecret {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "me.alexandrejoly.carbon.webhook",
            kSecAttrAccount as String: "authHeaderValue",
        ]
    }

    /// "" when there is none; nil when the Keychain couldn't be read, such as while it is locked.
    static func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data else {
            DiagnosticLog.shared.write("The webhook header value couldn't be read from the Keychain: OSStatus \(status)")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// An empty value deletes the item. Updated in place, so a failed write never loses the old value.
    static func write(_ value: String) {
        let status: OSStatus
        if value.isEmpty {
            status = SecItemDelete(query as CFDictionary)
        } else {
            let data = Data(value.utf8)
            let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updated == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                status = SecItemAdd(item as CFDictionary, nil)
            } else {
                status = updated
            }
        }
        if status != errSecSuccess, status != errSecItemNotFound {
            DiagnosticLog.shared.write("The webhook header value wasn't saved to the Keychain: OSStatus \(status)")
        }
    }
}
