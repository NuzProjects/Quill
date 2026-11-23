import Foundation

/// Compares what an app asks for (its entitlements) with what the chosen certificate can give it.
///
/// zsign signs with the provisioning profile's entitlements unless a custom entitlements file is set,
/// so anything the app asks for that the profile doesn't include is removed when signing.
struct EntitlementsReport: Equatable {
	enum Source: Equatable {
		case profile(String)
		case appleID(String)
		case customFile(String)
		case noCertificate
	}

	struct Item: Identifiable, Hashable {
		let key: String
		var id: String { key }
		var name: String { EntitlementsReport.friendlyName(for: key) }
	}

	/// What the gathering step needs from the main thread (Core Data objects stay there).
	struct Input: Equatable {
		var executable: URL?
		var provision: URL?
		var certificateName: String?
		var isAppleID: Bool
		var customFile: URL?
	}

	var source: Source
	/// Everything the app's main executable asks for, basics left out.
	var requested: [Item]
	/// Requested entitlements that survive signing.
	var kept: [Item]
	/// Requested entitlements that signing removes, so those features won't work.
	var dropped: [Item]
	/// Keys in the custom entitlements file that the profile doesn't allow. iOS may refuse to install.
	var notAllowed: [Item]
	/// What the certificate's profile includes, basics left out.
	var provided: [Item]
	/// False when the app's entitlements couldn't be read.
	var readApp: Bool

	/// Keys every signed app gets (or that Quill handles itself), so they aren't worth showing.
	static let basicKeys: Set<String> = [
		"application-identifier",
		"com.apple.developer.team-identifier",
		"keychain-access-groups",
		"get-task-allow",
		"beta-reports-active"
	]

	static func make(_ input: Input) -> EntitlementsReport {
		let appKeys = input.executable.flatMap(_entitlementKeys(ofBinary:))
		let requested = Set(appKeys ?? []).subtracting(basicKeys)

		var profileKeys: Set<String>?
		if let provision = input.provision, let decoded = CertificateReader(provision).decoded {
			profileKeys = Set(decoded.Entitlements?.keys.map { $0 } ?? [])
		}
		if input.isAppleID {
			// Free Apple ID profiles made by Quill don't enable any capabilities.
			profileKeys = (profileKeys ?? basicKeys).intersection(basicKeys)
		}
		let provided = (profileKeys ?? []).subtracting(basicKeys)

		let source: Source
		var effective: Set<String>?
		var notAllowed: Set<String> = []
		if let file = input.customFile {
			source = .customFile(file.lastPathComponent)
			let fileKeys = Set(_entitlementKeys(ofPlist: file) ?? []).subtracting(basicKeys)
			effective = fileKeys
			if let profileKeys { notAllowed = fileKeys.subtracting(profileKeys) }
		} else if let profileKeys {
			source = input.isAppleID
				? .appleID(input.certificateName ?? .localized("Apple ID"))
				: .profile(input.certificateName ?? .localized("Certificate"))
			effective = profileKeys
		} else {
			source = .noCertificate
		}

		let kept = effective.map { requested.intersection($0) } ?? requested
		let dropped = effective.map { requested.subtracting($0) } ?? []

		func items(_ keys: Set<String>) -> [Item] {
			keys.map(Item.init).sorted { ($0.name, $0.key) < ($1.name, $1.key) }
		}

		return EntitlementsReport(
			source: source,
			requested: items(requested),
			kept: items(kept),
			dropped: items(dropped),
			notAllowed: items(notAllowed),
			provided: items(provided),
			readApp: appKeys != nil
		)
	}

	/// Friendly names with duplicates removed (several iCloud keys all read "iCloud").
	static func names(_ items: [Item]) -> [String] {
		var seen = Set<String>()
		return items.map(\.name).filter { seen.insert($0).inserted }
	}

	// MARK: - Reading

	private static func _entitlementKeys(ofBinary url: URL) -> [String]? {
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		guard let data = LCGetMachOEntitlements(url.path) else { return [] }
		guard
			let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		else { return [] }
		return Array(plist.keys)
	}

	private static func _entitlementKeys(ofPlist url: URL) -> [String]? {
		guard
			let data = try? Data(contentsOf: url),
			let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		else { return nil }
		return Array(plist.keys)
	}

	// MARK: - Names

	static func friendlyName(for key: String) -> String {
		let developer = "com.apple.developer."
		if key == "aps-environment" || key == "com.apple.developer.aps-environment" { return .localized("Push Notifications") }
		if key == "com.apple.security.application-groups" { return .localized("App Groups") }
		if key == "inter-app-audio" { return .localized("Inter-App Audio") }
		if key == "com.apple.external-accessory.wireless-configuration" { return .localized("Wireless Accessory Setup") }
		guard key.hasPrefix(developer) else { return key }
		let name = String(key.dropFirst(developer.count))

		if name.hasPrefix("icloud") || name.hasPrefix("ubiquity") { return .localized("iCloud") }
		if name.hasPrefix("healthkit") { return .localized("HealthKit") }
		if name.hasPrefix("carplay") { return .localized("CarPlay") }
		if name.hasPrefix("networking.networkextension") { return .localized("Network Extensions (VPN, Filters)") }
		if name.hasPrefix("nfc") { return .localized("NFC Tag Reading") }
		if name.hasPrefix("devicecheck") { return .localized("App Attest") }

		switch name {
		case "associated-domains": return .localized("Associated Domains (Universal Links)")
		case "homekit": return .localized("HomeKit")
		case "applesignin": return .localized("Sign in with Apple")
		case "in-app-payments": return .localized("Apple Pay")
		case "siri": return .localized("Siri")
		case "networking.vpn.api": return .localized("Personal VPN")
		case "networking.wifi-info": return .localized("Wi-Fi Info")
		case "networking.multicast": return .localized("Local Network Multicast")
		case "game-center": return .localized("Game Center")
		case "usernotifications.time-sensitive": return .localized("Time-Sensitive Notifications")
		case "usernotifications.communication": return .localized("Communication Notifications")
		case "usernotifications.critical-alerts": return .localized("Critical Alerts")
		case "kernel.increased-memory-limit": return .localized("Increased Memory Limit")
		case "kernel.extended-virtual-addressing": return .localized("Extended Virtual Addressing")
		case "pass-type-identifiers": return .localized("Wallet Passes")
		case "default-data-protection": return .localized("Data Protection")
		case "associated-appclip-app-identifiers": return .localized("App Clips")
		case "family-controls": return .localized("Screen Time")
		case "weatherkit": return .localized("WeatherKit")
		case "ClassKit-environment": return .localized("ClassKit")
		case "authentication-services.autofill-credential-provider": return .localized("Password AutoFill")
		case "user-fonts": return .localized("Custom Fonts")
		case "contacts.notes": return .localized("Contact Notes")
		case "shared-with-you": return .localized("Shared with You")
		case "group-session": return .localized("SharePlay")
		case "media-device-discovery-extension": return .localized("Media Device Discovery")
		case "coremedia.hls.low-latency": return .localized("Low-Latency HLS")
		case "push-to-talk": return .localized("Push to Talk")
		case "sustained-execution": return .localized("Sustained Execution")
		default: return key
		}
	}
}

extension EntitlementsReport.Input {
	/// Collects paths on the main thread, where Core Data objects live.
	@MainActor
	static func make(app: AppInfoPresentable, certificate: CertificatePair?, customFile: URL?) -> Self {
		var executable: URL?
		if
			let bundle = Storage.shared.getAppDirectory(for: app),
			let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist")) as? [String: Any],
			let name = info["CFBundleExecutable"] as? String
		{
			executable = bundle.appendingPathComponent(name)
		}
		return Self(
			executable: executable,
			provision: certificate.flatMap { Storage.shared.getFile(.provision, from: $0) },
			certificateName: certificate?.nickname,
			isAppleID: certificate.map { AppleIDAccount.marker(for: $0) != nil } ?? false,
			customFile: customFile
		)
	}
}
