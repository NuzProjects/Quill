import Foundation
import UserNotifications

/// Turns a tapped notification into a place in the app.
@MainActor
final class NotificationRouter: ObservableObject {
	static let shared = NotificationRouter()

	/// The certificate whose apps should be shown (set by the expiry reminder).
	@Published var certificate: CertificatePair?
	/// Set when a notification wants the Library tab opened.
	@Published var openLibrary = false
	/// An app a Shortcut asked to sign; the Library opens its signing screen and clears this.
	@Published var signApp: AnyApp?
	/// An app picked from Spotlight; the Library shows its details and clears this.
	@Published var openApp: AnyApp?
	/// Set by the "Import IPA" control; the Library opens its file picker and clears this.
	@Published var importIPA = false

	private init() {}

	func handle(_ userInfo: [AnyHashable: Any]) {
		if let uuid = userInfo["certificateUUID"] as? String,
		   let match = Storage.shared.getAllCertificates().first(where: { $0.uuid == uuid }) {
			certificate = match
		} else if userInfo["appUUID"] != nil || userInfo["sourceUpdate"] != nil {
			openLibrary = true
		}
	}
}

/// Checks the user's sources for newer versions of Library apps on its own,
/// so the "Update available" badge shows up without pulling to refresh.
@MainActor
enum SourceUpdateChecker {
	private static let lastCheckKey = "Quill.lastSourceUpdateCheck"
	private static let notifiedKey = "Quill.notifiedSourceUpdates"
	private static let interval: TimeInterval = 3 * 60 * 60

	@discardableResult
	static func check(force: Bool = false) async -> Bool {
		let defaults = UserDefaults.standard
		if !force, let last = defaults.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < interval { return true }
		let sources = Storage.shared.getSources()
		guard !sources.isEmpty else { return true }
		let context = Storage.shared.context
		let signed = (try? context.fetch(Signed.fetchRequest())) ?? []
		let imported = (try? context.fetch(Imported.fetchRequest())) ?? []
		let apps = signed.map { $0 as AppInfoPresentable } + imported.map { $0 as AppInfoPresentable }
		guard !apps.isEmpty else { return true }
		await UpdateManager.shared.checkForUpdates(sources: sources, localApps: apps)
		defaults.set(Date(), forKey: lastCheckKey)
		await _notify(UpdateManager.shared.updates.values.sorted { $0.appName < $1.appName })
		return true
	}

	private static func _notify(_ updates: [AppUpdate]) async {
		var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? [])
		let fresh = updates.filter { !notified.contains("\($0.localUUID):\($0.remoteVersion)") }
		guard !fresh.isEmpty else { return }
		let center = UNUserNotificationCenter.current()
		let settings = await center.notificationSettings()
		guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
		let content = UNMutableNotificationContent()
		if fresh.count == 1, let update = fresh.first {
			content.title = "\(update.appName) has an update"
			content.body = "Version \(update.remoteVersion) is available from your sources. Tap to open your Library."
		} else {
			content.title = "\(fresh.count) app updates available"
			content.body = fresh.prefix(3).map(\.appName).joined(separator: ", ") + (fresh.count > 3 ? " and more" : "") + " have new versions in your sources."
		}
		content.sound = .default
		content.userInfo = ["sourceUpdate": true]
		do {
			try await center.add(UNNotificationRequest(identifier: "source-updates-\(UUID().uuidString)", content: content, trigger: nil))
			fresh.forEach { notified.insert("\($0.localUUID):\($0.remoteVersion)") }
			UserDefaults.standard.set(Array(notified), forKey: notifiedKey)
		} catch {}
	}
}
