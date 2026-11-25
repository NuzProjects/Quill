import Foundation

/// Reads an app bundle and explains what's inside it: what it needs to run,
/// which permissions it asks for, what it's made of and where its size comes from.
struct AppInspection {
	struct Part: Identifiable {
		let id = UUID()
		let name: String
		let detail: String?
		let bytes: Int64
	}

	struct SizeSlice: Identifiable {
		var id: String { label }
		let label: String
		let systemImage: String
		let bytes: Int64
	}

	var totalBytes: Int64 = 0
	var sizeBreakdown: [SizeSlice] = []

	var minimumOS: String?
	var builtWithSDK: String?
	var builtWithXcode: String?
	var devices: [String] = []
	var architectures: [String] = []
	var isEncrypted = false

	var frameworks: [Part] = []
	var extensions: [Part] = []
	var watchApp: Part?

	struct Permission: Identifiable {
		var id: String { name }
		let name: String
		let reason: String
	}

	var permissions: [Permission] = []
	var urlSchemes: [String] = []
	var backgroundModes: [String] = []
	var languages: [String] = []
	var supportsFiles = false
	var entitlementCount = 0
}

enum AppInspector {
	static func inspect(_ bundle: URL) -> AppInspection {
		var result = AppInspection()
		let info = (NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist")) as? [String: Any]) ?? [:]

		result.minimumOS = info["MinimumOSVersion"] as? String
		result.builtWithSDK = (info["DTPlatformVersion"] as? String).map { "iOS \($0)" } ?? info["DTSDKName"] as? String
		result.builtWithXcode = (info["DTXcode"] as? String).map(_xcodeVersion)
		result.devices = ((info["UIDeviceFamily"] as? [Int]) ?? [1]).compactMap {
			switch $0 {
			case 1: "iPhone"
			case 2: "iPad"
			case 3: "Apple TV"
			case 4: "Apple Watch"
			case 6: "Mac"
			case 7: "Apple Vision Pro"
			default: nil
			}
		}

		if let executable = info["CFBundleExecutable"] as? String {
			let url = bundle.appendingPathComponent(executable)
			result.architectures = architectures(of: url)
			result.isEncrypted = AppCompatibility.isEncrypted(url)
			if let data = LCGetMachOEntitlements(url.path),
			   let entitlements = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
				result.entitlementCount = entitlements.count
			}
		}

		result.permissions = info.keys
			.filter { $0.hasSuffix("UsageDescription") }
			.sorted()
			.map { AppInspection.Permission(name: _permissionName($0), reason: (info[$0] as? String) ?? "") }
		result.urlSchemes = ((info["CFBundleURLTypes"] as? [[String: Any]]) ?? [])
			.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
		result.backgroundModes = ((info["UIBackgroundModes"] as? [String]) ?? []).map(_backgroundModeName)
		result.supportsFiles = (info["UIFileSharingEnabled"] as? Bool ?? false) || (info["LSSupportsOpeningDocumentsInPlace"] as? Bool ?? false)

		let fm = FileManager.default
		let top = (try? fm.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)) ?? []
		result.languages = top
			.filter { $0.pathExtension == "lproj" && $0.lastPathComponent != "Base.lproj" }
			.map { url in
				let code = url.deletingPathExtension().lastPathComponent
				return Locale.current.localizedString(forIdentifier: code) ?? code
			}
			.sorted()

		// Frameworks and dylibs
		let frameworksDir = bundle.appendingPathComponent("Frameworks")
		result.frameworks = ((try? fm.contentsOfDirectory(at: frameworksDir, includingPropertiesForKeys: nil)) ?? [])
			.map { url in
				let kind: String = switch url.pathExtension {
				case "framework": "Framework"
				case "dylib": "Library"
				default: url.pathExtension.uppercased()
				}
				return AppInspection.Part(name: url.deletingPathExtension().lastPathComponent, detail: kind, bytes: size(of: url))
			}
			.sorted { $0.bytes > $1.bytes }

		// App extensions (widgets, share sheets, keyboards…)
		for folder in ["PlugIns", "Extensions"] {
			let dir = bundle.appendingPathComponent(folder)
			for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "appex" {
				let extInfo = (NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any]) ?? [:]
				let name = (extInfo["CFBundleDisplayName"] as? String) ?? (extInfo["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
				let point = ((extInfo["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String)
					?? ((extInfo["EXAppExtensionAttributes"] as? [String: Any])?["EXExtensionPointIdentifier"] as? String)
				result.extensions.append(.init(name: name, detail: point.map(_extensionKind), bytes: size(of: url)))
			}
		}
		result.extensions.sort { $0.bytes > $1.bytes }

		let watchDir = bundle.appendingPathComponent("Watch")
		if fm.fileExists(atPath: watchDir.path) {
			let watchBytes = size(of: watchDir)
			if watchBytes > 0 { result.watchApp = .init(name: "Apple Watch app", detail: nil, bytes: watchBytes) }
		}

		// Where the size comes from
		let total = size(of: bundle)
		result.totalBytes = total
		let executableBytes = (info["CFBundleExecutable"] as? String).map { size(of: bundle.appendingPathComponent($0)) } ?? 0
		let frameworkBytes = size(of: frameworksDir)
		let extensionBytes = result.extensions.reduce(0) { $0 + $1.bytes }
		let watchBytes = result.watchApp?.bytes ?? 0
		let languageBytes = top.filter { $0.pathExtension == "lproj" }.reduce(Int64(0)) { $0 + size(of: $1) }
		let assetBytes = size(of: bundle.appendingPathComponent("Assets.car"))
		let other = max(0, total - executableBytes - frameworkBytes - extensionBytes - watchBytes - languageBytes - assetBytes)
		result.sizeBreakdown = [
			.init(label: .localized("App Code"), systemImage: "chevron.left.forwardslash.chevron.right", bytes: executableBytes),
			.init(label: .localized("Frameworks"), systemImage: "shippingbox", bytes: frameworkBytes),
			.init(label: .localized("Extensions"), systemImage: "puzzlepiece.extension", bytes: extensionBytes),
			.init(label: .localized("Apple Watch App"), systemImage: "applewatch", bytes: watchBytes),
			.init(label: .localized("Images and Icons"), systemImage: "photo.on.rectangle", bytes: assetBytes),
			.init(label: .localized("Languages"), systemImage: "globe", bytes: languageBytes),
			.init(label: .localized("Other Files"), systemImage: "doc", bytes: other)
		]
		.filter { $0.bytes > 0 }
		.sorted { $0.bytes > $1.bytes }

		return result
	}

	/// Total size of a file or folder on disk.
	static func size(of url: URL) -> Int64 {
		let fm = FileManager.default
		var isDirectory: ObjCBool = false
		guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
		let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
		if !isDirectory.boolValue {
			return Int64((try? url.resourceValues(forKeys: Set(keys)).fileSize) ?? 0)
		}
		var total: Int64 = 0
		if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
			for case let file as URL in enumerator {
				guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
				total += Int64(values.fileSize ?? 0)
			}
		}
		return total
	}

	/// CPU architectures in a Mach-O file, e.g. ["arm64", "arm64e"].
	static func architectures(of url: URL) -> [String] {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
		defer { try? handle.close() }
		guard let head = try? handle.read(upToCount: 4096), head.count >= 8 else { return [] }
		let bytes = [UInt8](head)
		func be32(_ i: Int) -> UInt32 { i + 4 <= bytes.count ? (UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])) : 0 }
		func le32(_ i: Int) -> UInt32 { i + 4 <= bytes.count ? (UInt32(bytes[i + 3]) << 24 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i])) : 0 }

		let magic = be32(0)
		if magic == 0xCAFEBABE || magic == 0xCAFEBABF {
			let count = Int(be32(4))
			let entrySize = magic == 0xCAFEBABF ? 32 : 20
			guard count > 0, count < 32 else { return [] }
			return (0..<count).compactMap { index in
				let base = 8 + index * entrySize
				return _archName(cpu: be32(base), subtype: be32(base + 4))
			}
		}
		let thin = le32(0)
		if thin == 0xFEEDFACF || thin == 0xFEEDFACE, let name = _archName(cpu: le32(4), subtype: le32(8)) {
			return [name]
		}
		return []
	}

	private static func _archName(cpu: UInt32, subtype: UInt32) -> String? {
		let sub = subtype & 0x00FF_FFFF
		switch cpu {
		case 0x0100_000C: return sub == 2 ? "arm64e" : "arm64"
		case 0x0200_000C: return "arm64_32"
		case 0x0000_000C: return sub == 11 ? "armv7s" : (sub == 9 ? "armv7" : "arm")
		case 0x0100_0007: return "x86_64"
		case 0x0000_0007: return "i386"
		default: return nil
		}
	}

	private static func _xcodeVersion(_ raw: String) -> String {
		// DTXcode is like "1620" for Xcode 16.2
		guard let number = Int(raw) else { return raw }
		let major = number / 100
		let minor = (number % 100) / 10
		let patch = number % 10
		return patch == 0 ? "Xcode \(major).\(minor)" : "Xcode \(major).\(minor).\(patch)"
	}

	private static func _permissionName(_ key: String) -> String {
		let known: [String: String] = [
			"NSCameraUsageDescription": "Camera",
			"NSMicrophoneUsageDescription": "Microphone",
			"NSPhotoLibraryUsageDescription": "Photos",
			"NSPhotoLibraryAddUsageDescription": "Add to Photos",
			"NSLocationWhenInUseUsageDescription": "Location While Using",
			"NSLocationAlwaysAndWhenInUseUsageDescription": "Location Always",
			"NSLocationAlwaysUsageDescription": "Location Always",
			"NSContactsUsageDescription": "Contacts",
			"NSCalendarsUsageDescription": "Calendars",
			"NSCalendarsFullAccessUsageDescription": "Calendars",
			"NSRemindersUsageDescription": "Reminders",
			"NSRemindersFullAccessUsageDescription": "Reminders",
			"NSBluetoothAlwaysUsageDescription": "Bluetooth",
			"NSBluetoothPeripheralUsageDescription": "Bluetooth",
			"NSLocalNetworkUsageDescription": "Local Network",
			"NSFaceIDUsageDescription": "Face ID",
			"NSMotionUsageDescription": "Motion & Fitness",
			"NSHealthShareUsageDescription": "Health (Read)",
			"NSHealthUpdateUsageDescription": "Health (Write)",
			"NSSpeechRecognitionUsageDescription": "Speech Recognition",
			"NSAppleMusicUsageDescription": "Media & Apple Music",
			"NSUserTrackingUsageDescription": "Tracking",
			"NSHomeKitUsageDescription": "Home",
			"NSSiriUsageDescription": "Siri",
			"NFCReaderUsageDescription": "NFC"
		]
		if let name = known[key] { return name }
		// NSFooBarUsageDescription → "Foo Bar"
		var core = key.replacingOccurrences(of: "UsageDescription", with: "")
		if core.hasPrefix("NS") { core.removeFirst(2) }
		return core.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
	}

	private static func _backgroundModeName(_ mode: String) -> String {
		switch mode {
		case "audio": "Audio"
		case "location": "Location"
		case "voip": "Calls"
		case "fetch": "Background Fetch"
		case "remote-notification": "Push Notifications"
		case "processing": "Background Processing"
		case "bluetooth-central", "bluetooth-peripheral": "Bluetooth"
		case "external-accessory": "Accessories"
		case "nearby-interaction": "Nearby Interaction"
		default: mode
		}
	}

	private static func _extensionKind(_ point: String) -> String {
		switch point {
		case "com.apple.widgetkit-extension": "Widget"
		case "com.apple.share-services": "Share Extension"
		case "com.apple.ui-services": "Action Extension"
		case "com.apple.keyboard-service": "Keyboard"
		case "com.apple.usernotifications.service": "Notification Service"
		case "com.apple.usernotifications.content-extension": "Notification Content"
		case "com.apple.intents-service", "com.apple.intents-ui-service": "Siri Intents"
		case "com.apple.appintents-extension": "App Intents"
		case "com.apple.photo-editing": "Photo Editing"
		case "com.apple.fileprovider-nonui", "com.apple.fileprovider-ui": "Files Provider"
		case "com.apple.Safari.web-extension", "com.apple.Safari.extension": "Safari Extension"
		case "com.apple.Safari.content-blocker": "Content Blocker"
		case "com.apple.broadcast-services-upload", "com.apple.broadcast-services-setupui": "Screen Broadcast"
		case "com.apple.message-payload-provider": "iMessage App"
		case "com.apple.networkextension.packet-tunnel": "VPN"
		case "com.apple.authentication-services-credential-provider-ui": "Password AutoFill"
		default: point.components(separatedBy: ".").last ?? point
		}
	}
}
