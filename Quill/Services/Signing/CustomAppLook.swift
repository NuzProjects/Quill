import UIKit

/// Remembers the icon and name someone picked for an app, by bundle ID,
/// so the next time they sign an update of the same app it looks the same.
enum CustomAppLook {
	private static let _namesKey = "Quill.customAppNames"

	private static var _folder: URL {
		let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Quill/CustomIcons", isDirectory: true)
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private static func _iconURL(_ bundleID: String) -> URL {
		let safe = bundleID.replacingOccurrences(of: "/", with: "_")
		return _folder.appendingPathComponent("\(safe).png")
	}

	static func icon(for bundleID: String?) -> UIImage? {
		guard let bundleID else { return nil }
		return UIImage(contentsOfFile: _iconURL(bundleID).path)
	}

	static func name(for bundleID: String?) -> String? {
		guard let bundleID else { return nil }
		return (UserDefaults.standard.dictionary(forKey: _namesKey) as? [String: String])?[bundleID]
	}

	static func hasSaved(for bundleID: String?) -> Bool {
		icon(for: bundleID) != nil || name(for: bundleID) != nil
	}

	/// Saves what's set. A nil icon or name clears that part.
	static func save(icon: UIImage?, name: String?, for bundleID: String?) {
		guard let bundleID else { return }
		let url = _iconURL(bundleID)
		if let data = icon?.pngData() {
			try? data.write(to: url, options: .atomic)
		} else {
			try? FileManager.default.removeItem(at: url)
		}
		var names = (UserDefaults.standard.dictionary(forKey: _namesKey) as? [String: String]) ?? [:]
		let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
		names[bundleID] = (trimmed?.isEmpty == false) ? trimmed : nil
		UserDefaults.standard.set(names, forKey: _namesKey)
	}

	static func forget(_ bundleID: String?) {
		save(icon: nil, name: nil, for: bundleID)
	}

	/// Downloads an image from a link and makes it square.
	static func downloadIcon(from link: String) async throws -> UIImage {
		let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
			throw URLError(.badURL)
		}
		let (data, response) = try await URLSession.shared.data(from: url)
		if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			throw URLError(.badServerResponse)
		}
		guard let image = UIImage(data: data)?.resizeToSquare() else {
			throw URLError(.cannotDecodeContentData)
		}
		return image
	}
}
