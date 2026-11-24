import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NimbleExtensions

/// Offers to import an `.ipa` link the user copied before opening Quill.
///
/// Quill never reads the clipboard itself, because that shows iOS's "Allow Paste" prompt for every copied link.
/// It only asks iOS whether a web link is there (which doesn't prompt), then shows a pill with Apple's Paste
/// button. Tapping Paste hands Quill the link without a prompt, and only then is it checked for `.ipa`/`.tipa`.
@MainActor
final class ClipboardImport: ObservableObject {
	static let shared = ClipboardImport()
	nonisolated static let enabledKey = "Quill.clipboardImport"
	private nonisolated static let lastChangeKey = "Quill.clipboardLastChangeCount"

	enum State: Equatable {
		case hidden
		case offering
		case notAnIPA
	}

	@Published private(set) var state: State = .hidden
	private var _isChecking = false
	private var _hideTask: Task<Void, Never>?

	static var isEnabled: Bool {
		UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
	}

	/// Called when Quill comes to the foreground. Shows the pill when the clipboard changed since the last
	/// check and iOS says it holds a web link.
	static func check() { shared._check() }

	private func _check() {
		guard Self.isEnabled, !_isChecking else { return }
		let pasteboard = UIPasteboard.general
		let changeCount = pasteboard.changeCount
		guard changeCount != UserDefaults.standard.integer(forKey: Self.lastChangeKey), pasteboard.hasURLs || pasteboard.hasStrings else { return }

		_isChecking = true
		pasteboard.detectPatterns(for: [.probableWebURL]) { result in
			Task { @MainActor in
				self._isChecking = false
				UserDefaults.standard.set(changeCount, forKey: Self.lastChangeKey)
				guard case .success(let patterns) = result, patterns.contains(.probableWebURL) else { return }
				self._show(.offering, for: 10)
			}
		}
	}

	/// Call right after Quill itself copies something, so the pill doesn't offer Quill's own link back.
	nonisolated static func markOwnCopy() {
		UserDefaults.standard.set(UIPasteboard.general.changeCount, forKey: lastChangeKey)
	}

	/// Handles what the Paste button handed over. Links copied as a URL and links copied as text both work.
	func paste(_ providers: [NSItemProvider]) {
		Task { @MainActor in
			var strings: [String] = []
			for provider in providers {
				if let text = await Self._text(from: provider) { strings.append(text) }
			}
			self.paste(strings)
		}
	}

	private static func _text(from provider: NSItemProvider) async -> String? {
		if provider.canLoadObject(ofClass: NSURL.self), let url = await _load(NSURL.self, from: provider) {
			return url.absoluteString
		}
		if provider.canLoadObject(ofClass: NSString.self), let text = await _load(NSString.self, from: provider) {
			return text as String
		}
		return nil
	}

	private static func _load<T: NSItemProviderReading>(_ type: T.Type, from provider: NSItemProvider) async -> T? {
		await withCheckedContinuation { continuation in
			_ = provider.loadObject(ofClass: type) { object, _ in
				continuation.resume(returning: object as? T)
			}
		}
	}

	/// Checks the pasted text for an `.ipa`/`.tipa` link and downloads it.
	func paste(_ strings: [String]) {
		guard let url = strings.lazy.compactMap(Self.ipaURL(from:)).first else {
			UINotificationFeedbackGenerator().notificationOccurred(.warning)
			_show(.notAnIPA, for: 3)
			return
		}
		dismiss()
		UINotificationFeedbackGenerator().notificationOccurred(.success)
		_ = DownloadManager.shared.startDownload(from: url, id: "QuillManualDownload_\(UUID().uuidString)")
	}

	func dismiss() {
		_hideTask?.cancel()
		state = .hidden
	}

	private func _show(_ state: State, for seconds: Double) {
		_hideTask?.cancel()
		self.state = state
		_hideTask = Task { @MainActor [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
			guard !Task.isCancelled else { return }
			self?.state = .hidden
		}
	}

	/// The link, if it points at an `.ipa` or `.tipa` file.
	static func ipaURL(from text: String) -> URL? {
		guard
			let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
			let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
			["ipa", "tipa"].contains(url.pathExtension.lowercased())
		else { return nil }
		return url
	}
}

/// The pill above the tab bar that offers to import a copied link.
struct ClipboardImportPill: View {
	@ObservedObject private var _clipboard = ClipboardImport.shared
	@Environment(\.accessibilityReduceMotion) private var _reduceMotion

	var body: some View {
		ZStack {
			if _clipboard.state != .hidden {
				_pill
					.padding(.top, 8)
					.transition(
						_reduceMotion
							? .opacity
							: .opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)).combined(with: .offset(y: 8))
					)
			}
		}
		.animation(.spring(response: 0.45, dampingFraction: 0.82), value: _clipboard.state)
	}

	private var _pill: some View {
		HStack(spacing: 10) {
			if _clipboard.state == .notAnIPA {
				Label(.localized("That link isn't an IPA file"), systemImage: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
			} else {
				Label(.localized("Import copied link?"), systemImage: "doc.on.clipboard")
				PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
					Task { @MainActor in ClipboardImport.shared.paste(providers) }
				}
				.labelStyle(.titleOnly)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
				Button {
					_clipboard.dismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.footnote.weight(.bold))
						.foregroundStyle(.secondary)
				}
				.accessibilityLabel(Text(.localized("Dismiss")))
			}
		}
		.font(.callout.weight(.semibold))
		.padding(.leading, 15)
		.padding(.trailing, _clipboard.state == .notAnIPA ? 15 : 10)
		.padding(.vertical, 8)
		.modifier(ClipboardGlassCapsule())
	}
}

private struct ClipboardGlassCapsule: ViewModifier {
	func body(content: Content) -> some View {
		if #available(iOS 26, *) {
			content.glassEffect(.regular.interactive(), in: Capsule())
		} else {
			content
				.background(.regularMaterial, in: Capsule())
				.overlay(Capsule().stroke(Color.primary.opacity(0.08)))
				.shadow(color: .black.opacity(0.08), radius: 8, y: 3)
		}
	}
}
