import AppIntents
import CoreData
import Foundation

/// Opens Quill on the signing screen for the most recently imported app.
struct SignLatestImportIntent: AppIntent {
	static let title: LocalizedStringResource = "Sign Latest Import"
	static let description = IntentDescription("Opens Quill and starts signing the app you imported most recently.")
	static let openAppWhenRun = true

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let request = Imported.fetchRequest()
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		guard let latest = (try? Storage.shared.context.fetch(request))?.first else {
			return .result(dialog: "You haven't imported any apps into Quill yet.")
		}
		NotificationRouter.shared.signApp = AnyApp(base: latest)
		return .result(dialog: "Opening \(latest.name ?? "your latest import") for signing.")
	}
}

/// Checks sources and tracked GitHub releases for newer versions of Library apps.
struct CheckForAppUpdatesIntent: AppIntent {
	static let title: LocalizedStringResource = "Check for App Updates"
	static let description = IntentDescription("Checks your sources and tracked GitHub releases for newer versions of the apps in your Library, and returns how many have updates.")

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
		await SourceUpdateChecker.check(force: true)
		await GitHubReleases.shared.check(force: true)

		var names: [String: String] = [:]
		for (uuid, update) in UpdateManager.shared.updates { names[uuid] = update.appName }
		let githubUUIDs = GitHubReleases.shared.updates.keys.filter { names[$0] == nil }
		if !githubUUIDs.isEmpty {
			let context = Storage.shared.context
			let signed = (try? context.fetch(Signed.fetchRequest())) ?? []
			let imported = (try? context.fetch(Imported.fetchRequest())) ?? []
			let apps = signed.map { $0 as AppInfoPresentable } + imported.map { $0 as AppInfoPresentable }
			for uuid in githubUUIDs {
				names[uuid] = apps.first(where: { $0.uuid == uuid })?.name ?? "An app"
			}
		}

		let sorted = Array(Set(names.values)).sorted()
		let count = names.count
		switch count {
		case 0:
			return .result(value: 0, dialog: "All your apps are up to date.")
		case 1:
			return .result(value: 1, dialog: "\(sorted[0]) has an update.")
		default:
			let listed = sorted.prefix(3).joined(separator: ", ")
			let more = sorted.count > 3 ? " and \(sorted.count - 3) more" : ""
			return .result(value: count, dialog: "\(count) apps have updates: \(listed)\(more).")
		}
	}
}

/// Days until the selected signing certificate expires.
struct CertificateDaysLeftIntent: AppIntent {
	static let title: LocalizedStringResource = "Days Left on Certificate"
	static let description = IntentDescription("Returns how many days are left before the certificate Quill signs with expires.")

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
		guard let certificate = CertificateExpiry.selected, let expiration = certificate.expiration else {
			return .result(value: 0, dialog: "You don't have a certificate selected in Quill.")
		}
		let name = certificate.nickname ?? "Your certificate"
		guard expiration > Date() else {
			return .result(value: 0, dialog: "\(name) has expired. Import a new certificate to keep signing.")
		}
		let calendar = Calendar.current
		let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: expiration)).day ?? 0)
		let date = expiration.formatted(date: .abbreviated, time: .omitted)
		switch days {
		case 0: return .result(value: 0, dialog: "\(name) expires today.")
		case 1: return .result(value: 1, dialog: "\(name) expires tomorrow, \(date).")
		default: return .result(value: days, dialog: "\(name) has \(days) days left. It expires \(date).")
		}
	}
}

struct QuillShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: SignLatestImportIntent(),
			phrases: [
				"Sign my latest import in \(.applicationName)",
				"Sign latest app with \(.applicationName)"
			]
		)
		AppShortcut(
			intent: CheckForAppUpdatesIntent(),
			phrases: [
				"Check for app updates in \(.applicationName)",
				"Are there updates in \(.applicationName)"
			]
		)
		AppShortcut(
			intent: CertificateDaysLeftIntent(),
			phrases: [
				"How many days are left on my \(.applicationName) certificate",
				"When does my \(.applicationName) certificate expire"
			]
		)
	}
}
