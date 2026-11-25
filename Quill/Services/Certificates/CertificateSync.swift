import Foundation
import Security
import CryptoKit
import UIKit

/// Keeps certificates the same on every device through iCloud Keychain.
///
/// Each certificate (its .p12, its profile and its password) is saved as one synchronizable keychain item.
/// iCloud Keychain copies it to the person's other devices, and Quill on those devices adds any it doesn't have yet.
/// Items are named by a hash of the .p12, so the same certificate is never added twice.
@MainActor
enum CertificateSync {
	nonisolated static let enabledKey = "Quill.iCloudCertificateSync"
	private nonisolated static let _service = "Quill.CertificateSync"
	private static let _lastSyncKey = "Quill.iCloudCertificateSync.lastSync"
	private nonisolated static let _removedKey = "Quill.iCloudCertificateSync.removed"
	private static var _isSyncing = false

	enum Outcome: Equatable {
		case synced(uploaded: Int, added: Int)
		case unavailable(String)
	}

	nonisolated static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
	static var lastSync: Date? { UserDefaults.standard.object(forKey: _lastSyncKey) as? Date }

	private struct _Payload: Codable {
		var p12: Data
		var provision: Data
		var password: String?
		var nickname: String?
		var date: Date?
	}

	/// Uploads local certificates and adds the ones other devices uploaded.
	@discardableResult
	static func sync() async -> Outcome {
		guard isEnabled, !_isSyncing else { return .synced(uploaded: 0, added: 0) }
		_isSyncing = true
		defer { _isSyncing = false }

		var removed = Set(UserDefaults.standard.stringArray(forKey: _removedKey) ?? [])
		var localHashes = Set<String>()
		var uploaded = 0

		for cert in _syncableCertificates() {
			guard
				let p12URL = Storage.shared.getFile(.certificate, from: cert),
				let provisionURL = Storage.shared.getFile(.provision, from: cert),
				let p12 = try? Data(contentsOf: p12URL),
				let provision = try? Data(contentsOf: provisionURL)
			else { continue }
			let hash = _hash(p12)
			localHashes.insert(hash)
			// It's on this device, so if it was removed from iCloud before, it was imported again since.
			removed.remove(hash)
			let payload = _Payload(p12: p12, provision: provision, password: cert.password, nickname: cert.nickname, date: cert.date)
			switch _save(payload, account: hash) {
			case errSecSuccess: uploaded += 1
			case errSecDuplicateItem: break
			case errSecMissingEntitlement, errSecNotAvailable, errSecInteractionNotAllowed:
				return .unavailable(.localized("iCloud Keychain isn't available to Quill on this device. Make sure iCloud Keychain is on in Settings → your name → iCloud → Passwords and Keychain."))
			default: break
			}
		}

		UserDefaults.standard.set(Array(removed), forKey: _removedKey)

		var added = 0
		for (account, payload) in _remoteItems() where !localHashes.contains(account) && !removed.contains(account) {
			if await _add(payload) { added += 1 }
		}

		UserDefaults.standard.set(Date(), forKey: _lastSyncKey)
		return .synced(uploaded: uploaded, added: added)
	}

	/// Call before a certificate's files are deleted, so other devices stop receiving it.
	nonisolated static func forget(_ cert: CertificatePair) {
		guard
			isEnabled,
			let url = Storage.shared.getFile(.certificate, from: cert),
			let p12 = try? Data(contentsOf: url)
		else { return }
		let hash = _hash(p12)
		SecItemDelete(_query(account: hash) as CFDictionary)
		var removed = UserDefaults.standard.stringArray(forKey: _removedKey) ?? []
		if !removed.contains(hash) { removed.append(hash) }
		UserDefaults.standard.set(removed, forKey: _removedKey)
	}

	/// Removes every synced certificate from iCloud Keychain. Certificates on this device stay.
	static func removeAllFromiCloud() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: _service,
			kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
			kSecUseDataProtectionKeychain as String: true
		]
		SecItemDelete(query as CFDictionary)
		UserDefaults.standard.removeObject(forKey: _lastSyncKey)
	}

	// MARK: Keychain

	private nonisolated static func _query(account: String) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: _service,
			kSecAttrAccount as String: account,
			kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
			kSecUseDataProtectionKeychain as String: true
		]
	}

	private static func _save(_ payload: _Payload, account: String) -> OSStatus {
		guard let data = try? JSONEncoder().encode(payload) else { return errSecParam }
		var add = _query(account: account)
		add[kSecValueData as String] = data
		add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
		add[kSecAttrLabel as String] = "Quill certificate" + (payload.nickname.map { " (\($0))" } ?? "")
		return SecItemAdd(add as CFDictionary, nil)
	}

	private static func _remoteItems() -> [(String, _Payload)] {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: _service,
			kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
			kSecUseDataProtectionKeychain as String: true,
			kSecMatchLimit as String: kSecMatchLimitAll,
			kSecReturnAttributes as String: true,
			kSecReturnData as String: true
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
		return items.compactMap { item in
			guard
				let account = item[kSecAttrAccount as String] as? String,
				let data = item[kSecValueData as String] as? Data,
				let payload = try? JSONDecoder().decode(_Payload.self, from: data)
			else { return nil }
			return (account, payload)
		}
	}

	// MARK: Certificates

	/// Apple ID certificates are made for one device, so they're never synced.
	private static func _syncableCertificates() -> [CertificatePair] {
		((try? Storage.shared.context.fetch(CertificatePair.fetchRequest())) ?? []).filter { !AppleIDAccount.isAppleID($0) }
	}

	private static func _add(_ payload: _Payload) async -> Bool {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CertificateSync-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		do {
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			let p12URL = folder.appendingPathComponent("certificate.p12")
			let provisionURL = folder.appendingPathComponent("profile.mobileprovision")
			try payload.p12.write(to: p12URL)
			try payload.provision.write(to: provisionURL)
			return await withCheckedContinuation { continuation in
				FR.handleCertificateFiles(
					p12URL: p12URL,
					provisionURL: provisionURL,
					p12Password: payload.password ?? "",
					certificateName: payload.nickname ?? ""
				) { error in
					continuation.resume(returning: error == nil)
				}
			}
		} catch {
			return false
		}
	}

	private nonisolated static func _hash(_ data: Data) -> String {
		SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}
