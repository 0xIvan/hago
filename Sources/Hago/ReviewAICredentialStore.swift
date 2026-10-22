import Foundation
import HagoCore
import Security

struct ReviewAICredentialStore {
    private let service = "app.hago.review-ai"

    func save(_ key: String, for provider: ReviewAIHarnessKind) throws {
        guard provider.isDirectProvider else { throw ReviewAIDirectError.invalidConfiguration }
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty, data.count <= 4_096,
            !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw ReviewAIDirectError.missingCredential }
        let query = query(for: provider)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(attributes as CFDictionary, nil))
        } else {
            try check(update)
        }
    }

    func read(for provider: ReviewAIHarnessKind) throws -> String {
        var attributes = query(for: provider)
        attributes[kSecReturnData] = true
        attributes[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw ReviewAIDirectError.missingCredential }
        try check(status)
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw ReviewAIDirectError.missingCredential
        }
        return key
    }

    func remove(for provider: ReviewAIHarnessKind) throws {
        let status = SecItemDelete(query(for: provider) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func query(for provider: ReviewAIHarnessKind) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: provider.rawValue,
            kSecAttrSynchronizable: false,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw CredentialError.unavailable }
    }

    private enum CredentialError: Error, LocalizedError {
        case unavailable
        var errorDescription: String? {
            "Could not access the API key in macOS Keychain. Unlock your keychain and try again."
        }
    }
}
