import SwiftUI
import UIKit
import NimbleExtensions

/// Offers to import an `.ipa` link the user copied before opening Quill.
///
/// Quill never reads the clipboard itself, because that shows iOS's "Allow Paste" prompt for every copied link.
/// It only asks iOS whether a web link is there (which doesn't prompt), then shows a pill with Apple's Paste
/// button. Tapping Paste hands Quill the link without a prompt, and only then is it checked for `.ipa`/`.tipa`.
@MainActor
final class ClipboardImport: ObservableObject {
	static let shared = ClipboardImport()
	static let enabledKey = "Quill.clipboardImport"
	private static let lastChangeKey = "Quill.clipboardLastChangeCount"

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

	/// Handles what the Paste button handed over.
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
				PasteButton(payloadType: String.self) { strings in
					Task { @MainActor in ClipboardImport.shared.paste(strings) }
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
