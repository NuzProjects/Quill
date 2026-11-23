import Foundation
import UIKit

/// Looks inside tweaks (.dylib and .deb) before they're injected and flags the ones that would
/// crash the app or do nothing: wrong architecture or platform, a newer iOS than this device,
/// libraries that only exist on a jailbroken device, or a filter for a different app.
enum TweakInspector {
	struct Finding: Identifiable, Hashable {
		enum Kind: Hashable {
			case wrongArchitecture
			case wrongPlatform
			case needsNewerIOS
			case missingLibrary
			case madeForOtherApp
			case nothingToInject
			case unreadable
		}

		let kind: Kind
		let file: String
		let message: String
		var id: String { "\(file)|\(message)" }
	}

	/// What the check needs about the app and device, gathered on the main thread.
	struct Context: Hashable, Sendable {
		var appIdentifiers: [String]
		/// Names in the app's Frameworks folder and root ("Foo.framework", "libbar.dylib").
		var appProvides: Set<String>
		var deviceVersion: String
	}

	/// Results per tweak file. Runs off the main thread and caches by file and context.
	static func inspect(_ files: [URL], context: Context) async -> [URL: [Finding]] {
		await Task.detached(priority: .userInitiated) {
			await _inspect(files, context: context)
		}.value
	}

	// MARK: - Cache

	private final class _Cache: @unchecked Sendable {
		private let lock = NSLock()
		private var storage: [String: [Finding]] = [:]

		subscript(key: String) -> [Finding]? {
			get { lock.lock(); defer { lock.unlock() }; return storage[key] }
			set { lock.lock(); storage[key] = newValue; lock.unlock() }
		}
	}

	private static let _cache = _Cache()

	/// Keyed by the whole set of files too, since one tweak can provide a library another needs.
	private static func _cacheKey(_ url: URL, _ context: Context, _ set: String) -> String {
		let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
		let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
		let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
		return "\(url.path)|\(size)|\(date)|\(context.hashValue)|\(set)"
	}

	// MARK: - Inspection

	/// One binary found in a tweak.
	private struct Binary {
		var displayName: String
		var url: URL
		/// The DynamicLibraries filter plist next to a dylib, if any.
		var filter: URL?
	}

	private static func _inspect(_ files: [URL], context: Context) async -> [URL: [Finding]] {
		var pending: [URL] = []
		var result: [URL: [Finding]] = [:]
		let set = files.map(\.path).sorted().joined(separator: ",")
		for file in files {
			if let cached = _cache[_cacheKey(file, context, set)] { result[file] = cached } else { pending.append(file) }
		}
		guard !pending.isEmpty else { return result }

		let temp = FileManager.default.temporaryDirectory.appendingPathComponent("QuillTweakCheck_\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: temp) }

		// Unpack everything first: a library one tweak needs may come from another file.
		var binaries: [URL: [Binary]] = [:]
		var failures: [URL: Finding] = [:]
		var provided = context.appProvides
		provided.insert("CydiaSubstrate.framework") // ElleKit is added automatically
		for file in pending {
			let name = file.lastPathComponent
			switch file.pathExtension.lowercased() {
			case "dylib":
				binaries[file] = [Binary(displayName: name, url: file, filter: nil)]
				provided.insert(name)
			case "deb":
				guard let found = await _unpackDeb(file, into: temp.appendingPathComponent(UUID().uuidString), provides: &provided) else {
					failures[file] = Finding(kind: .unreadable, file: name, message: .localized("Couldn't open this package, so it may be damaged."))
					continue
				}
				if found.isEmpty {
					failures[file] = Finding(kind: .nothingToInject, file: name, message: .localized("This package has no tweak inside that can be injected, so it won't do anything."))
				}
				binaries[file] = found
			default:
				continue
			}
		}

		// Install names (LC_ID_DYLIB) count as provided too.
		var parsed: [URL: MachO] = [:]
		for binary in binaries.values.flatMap({ $0 }) {
			guard let macho = MachO(url: binary.url) else { continue }
			parsed[binary.url] = macho
			if let id = macho.installName { provided.insert(_providedName(for: id)) }
		}

		for file in pending {
			var findings: [Finding] = []
			if let failure = failures[file] { findings.append(failure) }
			for binary in binaries[file] ?? [] {
				findings += _check(binary, macho: parsed[binary.url], provided: provided, context: context)
			}
			result[file] = findings
			_cache[_cacheKey(file, context, set)] = findings
		}
		return result
	}

	private static func _check(_ binary: Binary, macho: MachO?, provided: Set<String>, context: Context) -> [Finding] {
		let name = binary.displayName
		guard let macho else {
			return [Finding(kind: .unreadable, file: name, message: .localized("This isn't a library iOS can load."))]
		}

		guard let slice = macho.arm64 else {
			let found = macho.architectures.isEmpty ? String.localized("an unknown architecture") : macho.architectures.joined(separator: ", ")
			return [Finding(kind: .wrongArchitecture, file: name, message: String(format: .localized("Built for %@, not iPhone (arm64), so the app will crash on launch."), found))]
		}

		var findings: [Finding] = []
		if let platform = slice.platform, platform != 2 {
			findings.append(Finding(kind: .wrongPlatform, file: name, message: String(format: .localized("Built for %@, not iOS, so the app will crash on launch."), _platformName(platform))))
		}
		if let minimum = slice.minimumOS, AppCompatibility.isVersion(minimum, newerThan: context.deviceVersion) {
			findings.append(Finding(kind: .needsNewerIOS, file: name, message: String(format: .localized("Needs iOS %@ or later, but this device is on iOS %@, so the app will crash on launch."), minimum, context.deviceVersion)))
		}

		let missing = slice.dependencies.filter { !_isAvailable($0, provided: provided) }
		if !missing.isEmpty {
			let names = missing.map { ($0 as NSString).lastPathComponent }
			findings.append(Finding(kind: .missingLibrary, file: name, message: String(format: .localized("Needs %@, which only exists on a jailbroken device or isn't included, so the app will crash on launch. Add the missing library as another tweak if you have it."), names.joined(separator: ", "))))
		}

		if let filter = binary.filter, let bundles = _filterBundles(filter), !bundles.isEmpty {
			let general: Set<String> = ["com.apple.UIKit", "com.apple.Foundation", "com.apple.CoreFoundation", "com.apple.WebKit"]
			let targets = Set(bundles)
			if targets.isDisjoint(with: general), targets.isDisjoint(with: context.appIdentifiers) {
				let shown = bundles.prefix(3).joined(separator: ", ")
				findings.append(Finding(kind: .madeForOtherApp, file: name, message: String(format: .localized("Made for %@, not this app, so it probably won't do anything."), shown)))
			}
		}
		return findings
	}

	// MARK: - Libraries

	private static let _jailbreakLibraries = [
		"libsubstrate", "libsubstitute", "libhooker", "libblackjack", "libellekit",
		"libcephei", "librocketbootstrap", "libactivator", "libcolorpicker", "libapplist",
		"libsparkapplist", "libsparkcolourpicker", "libgcuniversal", "libmryipc", "libroot",
		"libkrw", "libjailbreak", "libundirect", "libpddokdo", "libSandy"
	]

	private static func _isAvailable(_ path: String, provided: Set<String>) -> Bool {
		if path == "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" { return true } // rewritten to @rpath
		if path.hasPrefix("@") { return provided.contains(_providedName(for: path)) }
		if path.hasPrefix("/var/jb/") || path.hasPrefix("/Library/") || path.hasPrefix("/usr/local/") || path.hasPrefix("/private/var/") { return false }
		if path.hasPrefix("/usr/lib/") {
			let file = (path as NSString).lastPathComponent
			if _jailbreakLibraries.contains(where: { file.hasPrefix($0) }) { return false }
		}
		return true
	}

	/// The name to look for: the ".framework" folder for a framework, else the file name.
	private static func _providedName(for path: String) -> String {
		let parts = path.split(separator: "/")
		if let framework = parts.last(where: { $0.hasSuffix(".framework") }) { return String(framework) }
		return String(parts.last ?? Substring(path))
	}

	private static func _platformName(_ platform: UInt32) -> String {
		switch platform {
		case 1: "macOS"
		case 3: "tvOS"
		case 4: "watchOS"
		case 6: "Mac Catalyst"
		case 7: String.localized("the iOS Simulator")
		case 8: String.localized("the tvOS Simulator")
		case 9: String.localized("the watchOS Simulator")
		case 11: "visionOS"
		case 12: String.localized("the visionOS Simulator")
		default: String(format: String.localized("platform %ld"), Int(platform))
		}
	}

	private static func _filterBundles(_ url: URL) -> [String]? {
		guard
			let data = try? Data(contentsOf: url),
			let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
			let filter = plist["Filter"] as? [String: Any]
		else { return nil }
		return filter["Bundles"] as? [String]
	}

	// MARK: - Debs

	/// Unpacks a .deb the same way TweakHandler does and returns the binaries it would inject.
	private static func _unpackDeb(_ url: URL, into directory: URL, provides: inout Set<String>) async -> [Binary]? {
		let fileManager = FileManager.default
		guard (try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }

		var roots: [URL] = []
		do {
			let files = try await AR(with: url).extract()
			for file in files where file.name.hasPrefix("data.tar") {
				var output = directory.appendingPathComponent(file.name)
				try file.content.write(to: output)
				try extractFile(at: &output)
				try extractFile(at: &output)
				roots.append(output)
			}
		} catch {
			return nil
		}
		guard !roots.isEmpty else { return nil }

		var binaries: [Binary] = []
		for root in roots {
			for prefix in ["", "var/jb/"] {
				let dynamic = root.appendingPathComponent(prefix + "Library/MobileSubstrate/DynamicLibraries")
				for item in (try? fileManager.contentsOfDirectory(at: dynamic, includingPropertiesForKeys: nil)) ?? [] where item.pathExtension.lowercased() == "dylib" {
					let filter = item.deletingPathExtension().appendingPathExtension("plist")
					binaries.append(Binary(displayName: item.lastPathComponent, url: item, filter: fileManager.fileExists(atPath: filter.path) ? filter : nil))
					provides.insert(item.lastPathComponent)
				}

				let frameworks = root.appendingPathComponent(prefix + "Library/Frameworks")
				for item in (try? fileManager.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [] where item.pathExtension.lowercased() == "framework" {
					provides.insert(item.lastPathComponent)
					if let executable = Bundle(url: item)?.executableURL ?? _guessExecutable(item) {
						binaries.append(Binary(displayName: item.lastPathComponent, url: executable, filter: nil))
					}
				}
			}
		}
		return binaries
	}

	private static func _guessExecutable(_ framework: URL) -> URL? {
		let candidate = framework.appendingPathComponent(framework.deletingPathExtension().lastPathComponent)
		return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
	}
}

// MARK: - Mach-O

/// Just enough Mach-O parsing for the checks above.
private struct MachO {
	struct Slice {
		var cpuType: UInt32
		var platform: UInt32?
		var minimumOS: String?
		var dependencies: [String] = []
		var installName: String?
	}

	var slices: [Slice]

	var arm64: Slice? { slices.first { $0.cpuType == 0x0100000C } }
	var installName: String? { arm64?.installName ?? slices.first?.installName }
	var architectures: [String] { slices.map { MachO.name(ofCPU: $0.cpuType) } }

	init?(url: URL) {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 8 else { return nil }
		let bytes = [UInt8](data)
		let magic = MachO.be32(bytes, 0)

		var offsets: [Int] = [0]
		if magic == 0xCAFEBABE || magic == 0xCAFEBABF {
			let is64 = magic == 0xCAFEBABF
			let count = Int(MachO.be32(bytes, 4))
			let entry = is64 ? 32 : 20
			guard count > 0, count < 32, 8 + count * entry <= bytes.count else { return nil }
			offsets = (0..<count).map { index in
				let base = 8 + index * entry
				return is64 ? Int(MachO.be64(bytes, base + 8)) : Int(MachO.be32(bytes, base + 8))
			}
		}

		slices = offsets.compactMap { MachO.parseSlice(bytes, at: $0) }
		guard !slices.isEmpty else { return nil }
	}

	private static func parseSlice(_ b: [UInt8], at base: Int) -> Slice? {
		guard base >= 0, base + 28 <= b.count else { return nil }
		let magic = le32(b, base)
		guard magic == 0xFEEDFACF || magic == 0xFEEDFACE else { return nil }
		var slice = Slice(cpuType: le32(b, base + 4))
		let commandCount = Int(le32(b, base + 16))
		var cursor = base + (magic == 0xFEEDFACF ? 32 : 28)

		for _ in 0..<min(commandCount, 4096) {
			guard cursor + 8 <= b.count else { break }
			let command = le32(b, cursor)
			let size = Int(le32(b, cursor + 4))
			guard size >= 8, cursor + size <= b.count else { break }

			switch command {
			case 0x32 where size >= 16: // LC_BUILD_VERSION
				slice.platform = le32(b, cursor + 8)
				slice.minimumOS = version(le32(b, cursor + 12))
			case 0x25 where size >= 16: // LC_VERSION_MIN_IPHONEOS
				slice.platform = slice.platform ?? 2
				slice.minimumOS = slice.minimumOS ?? version(le32(b, cursor + 8))
			case 0x24: slice.platform = slice.platform ?? 1 // LC_VERSION_MIN_MACOSX
			case 0x2F: slice.platform = slice.platform ?? 3 // LC_VERSION_MIN_TVOS
			case 0x30: slice.platform = slice.platform ?? 4 // LC_VERSION_MIN_WATCHOS
			case 0xC, 0x8000001F, 0x80000023: // LC_LOAD_DYLIB, LC_REEXPORT_DYLIB, LC_LOAD_UPWARD_DYLIB
				if let name = string(b, cursor, size) { slice.dependencies.append(name) }
			case 0xD: // LC_ID_DYLIB
				slice.installName = string(b, cursor, size)
			default:
				break
			}
			cursor += size
		}
		return slice
	}

	private static func string(_ b: [UInt8], _ command: Int, _ size: Int) -> String? {
		guard size >= 12 else { return nil }
		let offset = Int(le32(b, command + 8))
		guard offset < size else { return nil }
		let start = command + offset
		let end = command + size
		let bytes = b[start..<end].prefix { $0 != 0 }
		return String(decoding: bytes, as: UTF8.self)
	}

	private static func version(_ raw: UInt32) -> String {
		let major = raw >> 16, minor = (raw >> 8) & 0xFF, patch = raw & 0xFF
		return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
	}

	static func name(ofCPU type: UInt32) -> String {
		switch type {
		case 0x0100000C: "arm64"
		case 0x0200000C: "arm64_32"
		case 12: "armv7"
		case 0x01000007: "x86_64"
		case 7: "i386"
		default: String(format: "CPU 0x%X", type)
		}
	}

	private static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
		guard o + 4 <= b.count else { return 0 }
		return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
	}

	static func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
		guard o + 4 <= b.count else { return 0 }
		return UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
	}

	static func be64(_ b: [UInt8], _ o: Int) -> UInt64 {
		UInt64(be32(b, o)) << 32 | UInt64(be32(b, o + 4))
	}
}

extension TweakInspector.Context {
	/// Collects what the check needs on the main thread, where Core Data objects live.
	@MainActor
	static func make(app: AppInfoPresentable?, identifier: String?) -> Self {
		var provides: Set<String> = []
		if let app, let bundle = Storage.shared.getAppDirectory(for: app) {
			let fileManager = FileManager.default
			for folder in [bundle, bundle.appendingPathComponent("Frameworks")] {
				for item in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] {
					let ext = (item as NSString).pathExtension.lowercased()
					if ext == "framework" || ext == "dylib" { provides.insert(item) }
				}
			}
		}
		let identifiers = [app?.identifier, identifier].compactMap { $0 }.filter { !$0.isEmpty }
		return Self(
			appIdentifiers: Array(Set(identifiers)).sorted(),
			appProvides: provides,
			deviceVersion: UIDevice.current.systemVersion
		)
	}
}
