import UIKit
import NimbleExtensions

/// Offers to import an `.ipa` link the user copied before opening Quill.
@MainActor
enum ClipboardImport {
	static let enabledKey = "Quill.clipboardImport"
	private static let lastChangeKey = "Quill.clipboardLastChangeCount"
	private static let lastURLKey = "Quill.clipboardLastURL"
	private static var _isChecking = false

	static var isEnabled: Bool {
		UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
	}

	/// Called when Quill comes to the foreground. Only looks at the clipboard when it changed since the last check
	/// and iOS says it holds a web link, so Quill doesn't read (or trigger the paste prompt for) anything else.
	static func check() {
		guard isEnabled, !_isChecking else { return }
		let pasteboard = UIPasteboard.general
		let changeCount = pasteboard.changeCount
		guard changeCount != UserDefaults.standard.integer(forKey: lastChangeKey), pasteboard.hasURLs || pasteboard.hasStrings else { return }

		_isChecking = true
		pasteboard.detectPatterns(for: [.probableWebURL]) { result in
			Task { @MainActor in
				defer { _isChecking = false }
				guard case .success(let patterns) = result, patterns.contains(.probableWebURL) else {
					UserDefaults.standard.set(changeCount, forKey: lastChangeKey)
					return
				}
				UserDefaults.standard.set(changeCount, forKey: lastChangeKey)
				guard let url = ipaURL(from: .general), url.absoluteString != UserDefaults.standard.string(forKey: lastURLKey) else { return }
				UserDefaults.standard.set(url.absoluteString, forKey: lastURLKey)
				_offer(url)
			}
		}
	}

	/// The copied link, if it points at an `.ipa` or `.tipa` file.
	static func ipaURL(from pasteboard: UIPasteboard) -> URL? {
		let candidate = pasteboard.url ?? pasteboard.string
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.flatMap(URL.init(string:))
		guard
			let url = candidate,
			let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
			["ipa", "tipa"].contains(url.pathExtension.lowercased())
		else { return nil }
		return url
	}

	private static func _offer(_ url: URL) {
		let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
		let host = url.host ?? ""
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
			UIAlertController.showAlertWithCancel(
				title: .localized("Import This App?"),
				message: String(format: .localized("You copied a link to %@ from %@. Download it to your Library?"), name, host),
				actions: [
					UIAlertAction(title: .localized("Import"), style: .default) { _ in
						UINotificationFeedbackGenerator().notificationOccurred(.success)
						_ = DownloadManager.shared.startDownload(from: url, id: "QuillManualDownload_\(UUID().uuidString)")
					}
				]
			)
		}
	}
}
