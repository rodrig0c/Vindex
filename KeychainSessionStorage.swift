import Foundation
import Supabase

// ATUALIZADO: O protocolo agora se chama 'AuthLocalStorage'
final class KeychainSessionStorage: AuthLocalStorage {
  private let service: String

  init(service: String = "supabase.gotrue.swift") {
    self.service = service
  }

  // A assinatura desta função mudou para corresponder ao novo protocolo
  func store(key: String, value: Data) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: key,
      kSecValueData: value,
    ]

    let status = SecItemAdd(query as CFDictionary, nil)

    if status == errSecDuplicateItem {
      let updateQuery: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: key,
      ]
      let attributes: [CFString: Any] = [
        kSecValueData: value,
      ]
      SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
    } else if status != errSecSuccess {
        print("Keychain write error: \(status)")
    }
  }
  
  // A assinatura desta função mudou
  func retrieve(key: String) throws -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: key,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecReturnData: true,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
      if status != errSecItemNotFound {
        print("Keychain read error: \(status)")
      }
      return nil
    }
    return data
  }

  // A assinatura desta função mudou
  func remove(key: String) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: key,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
