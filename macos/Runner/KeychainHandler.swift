import FlutterMacOS
import Foundation
import Security

/// Stores the user's own Anthropic API key in the login Keychain.
///
/// Split out the same way as `FolderPickerHandler`: decode arguments, shape
/// replies, nothing more. The key never touches the settings JSON, a log or a
/// file the app writes — only this Keychain item, which is
/// ThisDeviceOnly so it does not sync to iCloud. Dart reads it at the start of
/// a dictation and hands it to the backend on 127.0.0.1 for that session.
class KeychainHandler {

    private static let service = "com.ultrawhisper.anthropic-api-key"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAnthropicKey":
            result(read())

        case "setAnthropicKey":
            guard let key = call.arguments as? String, !key.isEmpty else {
                result(FlutterError(code: "BAD_ARGS", message: "Expected a non-empty key", details: nil))
                return
            }
            result(write(key))

        case "deleteAnthropicKey":
            let status = SecItemDelete(baseQuery as CFDictionary)
            result(status == errSecSuccess || status == errSecItemNotFound)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "UltraWhisper — Anthropic API key"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
