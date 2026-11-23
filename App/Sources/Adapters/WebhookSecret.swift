import Foundation
import Security

/// The webhook auth header's value, in the login keychain rather than UserDefaults' readable plist.
enum WebhookSecret {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "me.alexandrejoly.carbon.webhook",
            kSecAttrAccount as String: "authHeaderValue",
        ]
    }

    static func read() -> String {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// An empty value deletes the item.
    static func write(_ value: String) {
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            DiagnosticLog.shared.write("The webhook header value wasn't saved to the Keychain: OSStatus \(status)")
        }
    }
}
