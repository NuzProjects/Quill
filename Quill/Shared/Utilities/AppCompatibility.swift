import Foundation
import UIKit

enum AppCompatibility {
	enum Issue: Equatable, Identifiable {
		case encrypted
		case needsNewerIOS(String)
		case iPadOnly
		case certificateExpired(String)
		case certificateRevoked(String)
		case certificateExpiresSoon(String, Date)
		case appIDLimitReached(nextSlot: Date)
		case appIDLimitClose(used: Int)
		case lowStorage(neededMB: Int, freeMB: Int)
		case entitlementsDropped([String])
		case entitlementsNotAllowed([String])
		case tweak(file: String, message: String)

		var id: String { message }

		/// Blocking issues stop signing; the rest can be signed anyway.
		var isBlocking: Bool {
			switch self {
			case .certificateExpired, .certificateRevoked, .appIDLimitReached, .lowStorage: true
			default: false
			}
		}

		/// Advisory issues are shown in the pre-sign check but don't ask "Sign Anyway?".
		var isAdvisory: Bool {
			if case .entitlementsDropped = self { return true }
			return false
		}

		var icon: String {
			switch self {
			case .encrypted: "lock.fill"
			case .needsNewerIOS, .iPadOnly: "iphone.slash"
			case .certificateExpired, .certificateRevoked, .certificateExpiresSoon: "checkmark.seal"
			case .appIDLimitReached, .appIDLimitClose: "number"
			case .lowStorage: "internaldrive"
			case .entitlementsDropped, .entitlementsNotAllowed: "key"
			case .tweak: "puzzlepiece.extension"
			}
		}

		var message: String {
			switch self {
			case .encrypted:
				return .localized("This app is still encrypted by the App Store, so it won't open after signing. Use a decrypted IPA instead.")
			case .needsNewerIOS(let minimum):
				return String(format: .localized("This app needs iOS %@ or later, but this device is on iOS %@, so it may not open."), minimum, UIDevice.current.systemVersion)
			case .iPadOnly:
				return .localized("This app is made for iPad only, so it may not open or may look wrong on iPhone.")
			case .certificateExpired(let name):
				return String(format: .localized("%@ has expired. Pick or import another certificate."), name)
			case .certificateRevoked(let name):
				return String(format: .localized("Apple revoked %@, so apps signed with it won't open. Pick or import another certificate."), name)
			case .certificateExpiresSoon(let name, let date):
				return String(format: .localized("%@ expires %@, so this app will stop opening soon after."), name, date.formatted(.relative(presentation: .named)))
			case .appIDLimitReached(let next):
				return String(format: .localized("This Apple ID has used all %ld new App IDs Apple allows per week. The next one frees up %@. Re-signing an app you already signed doesn't count."), AppIDUsage.weeklyLimit, next.formatted(.relative(presentation: .named)))
			case .appIDLimitClose(let used):
				return String(format: .localized("This Apple ID has used %ld of %ld new App IDs for this week. Signing this app uses one more."), used, AppIDUsage.weeklyLimit)
			case .lowStorage(let needed, let free):
				return String(format: .localized("Signing needs about %ld MB of free space, but only %ld MB is free. Free up some space first."), needed, free)
			case .entitlementsDropped(let names):
				return String(format: .localized("This certificate can't give the app %@, so those features won't work after signing."), ListFormatter.localizedString(byJoining: names))
			case .entitlementsNotAllowed(let names):
				return String(format: .localized("Your entitlements file asks for %@, which this certificate doesn't allow, so iOS may refuse to install the app."), ListFormatter.localizedString(byJoining: names))
			case .tweak(let file, let message):
				return "\(file): \(message)"
			}
		}
	}

	/// The checks that only need the app (used before the signing screen knows the certificate).
	static func issues(for app: AppInfoPresentable) -> [Issue] {
		issues(for: app, certificate: nil, identifier: nil, appMegabytes: nil)
	}

	/// Everything worth knowing before signing: the app, the device, the certificate and the Apple ID's App ID budget.
	static func issues(for app: AppInfoPresentable, certificate: CertificatePair?, identifier: String?, appMegabytes: Double?) -> [Issue] {
		var result: [Issue] = []
		let bundle = Storage.shared.getAppDirectory(for: app)
		if let bundle, let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist")) as? [String: Any] {
			if let executable = info["CFBundleExecutable"] as? String, isEncrypted(bundle.appendingPathComponent(executable)) {
				result.append(.encrypted)
			}
			if let minimum = info["MinimumOSVersion"] as? String, isVersion(minimum, newerThan: UIDevice.current.systemVersion) {
				result.append(.needsNewerIOS(minimum))
			}
			if UIDevice.current.userInterfaceIdiom == .phone, let families = info["UIDeviceFamily"] as? [Int], !families.isEmpty, !families.contains(1) {
				result.append(.iPadOnly)
			}
		}

		if let certificate {
			let name = certificate.nickname ?? .localized("This certificate")
			if certificate.revoked {
				result.append(.certificateRevoked(name))
			} else if let expiration = certificate.expiration {
				if expiration <= Date() { result.append(.certificateExpired(name)) }
				else if expiration.timeIntervalSinceNow < 2 * 86400 { result.append(.certificateExpiresSoon(name, expiration)) }
			}
			if let marker = AppleIDAccount.marker(for: certificate), let identifier, !identifier.isEmpty {
				let suffix = "." + marker.teamID
				let full = identifier.hasSuffix(suffix) ? identifier : identifier + suffix
				if !AppIDUsage.isKnown(full, teamID: marker.teamID) {
					let recent = AppIDUsage.recent(teamID: marker.teamID)
					if recent.count >= AppIDUsage.weeklyLimit, let oldest = recent.first {
						result.append(.appIDLimitReached(nextSlot: oldest.addingTimeInterval(7 * 86400)))
					} else if recent.count >= AppIDUsage.weeklyLimit - 3 {
						result.append(.appIDLimitClose(used: recent.count))
					}
				}
			}
		}

		if let appMB = appMegabytes ?? bundle.map(SigningProgress.megabytes) {
			let neededMB = Int(appMB * 2.2) + 50
			let home = URL(fileURLWithPath: NSHomeDirectory())
			if let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
				let freeMB = Int(free / 1_048_576)
				if freeMB < neededMB { result.append(.lowStorage(neededMB: neededMB, freeMB: freeMB)) }
			}
		}
		return result
	}

	static func isVersion(_ version: String, newerThan other: String) -> Bool {
		let lhs = version.split(separator: ".").map { Int($0) ?? 0 }
		let rhs = other.split(separator: ".").map { Int($0) ?? 0 }
		for index in 0..<max(lhs.count, rhs.count) {
			let a = index < lhs.count ? lhs[index] : 0
			let b = index < rhs.count ? rhs[index] : 0
			if a != b { return a > b }
		}
		return false
	}

	static func isEncrypted(_ url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
		defer { try? handle.close() }

		func read(_ offset: UInt64, _ count: Int) -> [UInt8]? {
			guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.read(upToCount: count), data.count == count else { return nil }
			return [UInt8](data)
		}

		guard let head = read(0, 8) else { return false }
		let magic = _be32(head, 0)
		var slices: [UInt64] = [0]
		if magic == 0xCAFEBABE || magic == 0xCAFEBABF {
			let is64 = magic == 0xCAFEBABF
			let count = Int(_be32(head, 4))
			let entrySize = is64 ? 32 : 20
			guard count > 0, count < 32, let table = read(8, count * entrySize) else { return false }
			slices = (0..<count).map { index in
				let base = index * entrySize
				return is64 ? _be64(table, base + 8) : UInt64(_be32(table, base + 8))
			}
		}
		return slices.contains { _sliceIsEncrypted(read, at: $0) }
	}

	private static func _sliceIsEncrypted(_ read: (UInt64, Int) -> [UInt8]?, at offset: UInt64) -> Bool {
		guard let header = read(offset, 28) else { return false }
		let magic = _le32(header, 0)
		let headerSize: UInt64
		switch magic {
		case 0xFEEDFACF: headerSize = 32
		case 0xFEEDFACE: headerSize = 28
		default: return false
		}
		let commandCount = Int(_le32(header, 16))
		let commandsSize = Int(_le32(header, 20))
		guard commandsSize > 0, commandsSize < 4_000_000, let commands = read(offset + headerSize, commandsSize) else { return false }

		var position = 0
		for _ in 0..<commandCount {
			guard position + 20 <= commands.count else { break }
			let command = _le32(commands, position)
			let size = Int(_le32(commands, position + 4))
			if command == 0x21 || command == 0x2C, _le32(commands, position + 16) != 0 {
				return true
			}
			guard size > 0 else { break }
			position += size
		}
		return false
	}

	private static func _le32(_ bytes: [UInt8], _ i: Int) -> UInt32 {
		UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
	}

	private static func _be32(_ bytes: [UInt8], _ i: Int) -> UInt32 {
		UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
	}

	private static func _be64(_ bytes: [UInt8], _ i: Int) -> UInt64 {
		UInt64(_be32(bytes, i)) << 32 | UInt64(_be32(bytes, i + 4))
	}
}

extension AppCompatibility {
	/// Warnings from the entitlement report.
	static func issues(for report: EntitlementsReport?) -> [Issue] {
		guard let report else { return [] }
		var result: [Issue] = []
		if !report.notAllowed.isEmpty { result.append(.entitlementsNotAllowed(EntitlementsReport.names(report.notAllowed))) }
		if !report.dropped.isEmpty { result.append(.entitlementsDropped(EntitlementsReport.names(report.dropped))) }
		return result
	}

	/// Warnings from the tweak checker, in the order the tweaks were added.
	static func issues(for findings: [URL: [TweakInspector.Finding]], order: [URL]) -> [Issue] {
		order.flatMap { findings[$0] ?? [] }.map { .tweak(file: $0.file, message: $0.message) }
	}
}
