import CoreSpotlight
import UIKit
import UniformTypeIdentifiers

/// Keeps Spotlight in step with the Library, so searching an app's name
/// shows it and tapping the result opens it in Quill.
@MainActor
enum SpotlightIndexer {
	private static let domain = "dev.madebynuz.quill.library"
	private static let indexedKey = "Quill.spotlightIndexed"
	private static var iconCache: [String: Data] = [:]

	/// Indexes apps that are new or changed and removes ones that were deleted.
	static func update() {
		guard CSSearchableIndex.isIndexingAvailable() else { return }
		let apps = GitHubReleases.shared.allApps()
		var current: [String: String] = [:]
		var items: [CSSearchableItem] = []

		for app in apps {
			guard let uuid = app.uuid else { continue }
			let signature = [app.name, app.version, app.identifier, app.isSigned ? "s" : "i"].map { $0 ?? "" }.joined(separator: "|")
			current[uuid] = signature
			if _indexed[uuid] == signature { continue }

			let attributes = CSSearchableItemAttributeSet(contentType: .application)
			attributes.title = app.name ?? "App"
			attributes.displayName = app.name
			let kind = app.isSigned ? String.localized("Signed") : String.localized("Imported")
			attributes.contentDescription = [app.version.map { "v\($0)" }, kind, app.identifier].compactMap { $0 }.joined(separator: " · ")
			attributes.keywords = [app.name, app.identifier, "Quill"].compactMap { $0 }
			attributes.thumbnailData = _icon(for: app, uuid: uuid)
			items.append(CSSearchableItem(uniqueIdentifier: uuid, domainIdentifier: domain, attributeSet: attributes))
		}

		let removed = Set(_indexed.keys).subtracting(current.keys)
		let index = CSSearchableIndex.default()
		if !items.isEmpty { index.indexSearchableItems(items) }
		if !removed.isEmpty {
			index.deleteSearchableItems(withIdentifiers: Array(removed))
			removed.forEach { iconCache.removeValue(forKey: $0) }
		}
		if !items.isEmpty || !removed.isEmpty { _indexed = current }
	}

	/// Returns the Library app a Spotlight result points at.
	static func app(for activity: NSUserActivity) -> AppInfoPresentable? {
		guard let uuid = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
		return GitHubReleases.shared.allApps().first { $0.uuid == uuid }
	}

	private static var _indexed: [String: String] {
		get { UserDefaults.standard.dictionary(forKey: indexedKey) as? [String: String] ?? [:] }
		set { UserDefaults.standard.set(newValue, forKey: indexedKey) }
	}

	private static func _icon(for app: AppInfoPresentable, uuid: String) -> Data? {
		if let cached = iconCache[uuid] { return cached }
		guard
			let directory = Storage.shared.getAppDirectory(for: app),
			let image = iconTest(directory)
		else { return nil }
		let size = CGSize(width: 120, height: 120)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let data = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			image.draw(in: CGRect(origin: .zero, size: size))
		}.pngData()
		iconCache[uuid] = data
		return data
	}
}
