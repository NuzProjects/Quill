import SwiftUI
import WidgetKit
import AppIntents

// Control Center, Lock Screen and Action button controls (iOS 18 and later).
// Each control opens Quill at the right place through its feather:// link.

@available(iOS 18.0, *)
struct OpenQuillLinkIntent: AppIntent {
	static var title: LocalizedStringResource = "Open Quill"
	static var isDiscoverable = false

	@Parameter(title: "Link")
	var link: String

	init() {}
	init(_ link: String) { self.link = link }

	func perform() async throws -> some IntentResult & OpensIntent {
		guard let url = URL(string: link) else { throw $link.needsValueError() }
		return .result(opensIntent: OpenURLIntent(url))
	}
}

@available(iOS 18.0, *)
struct ImportIPAControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "QuillImportIPAControl") {
			ControlWidgetButton(action: OpenQuillLinkIntent("feather://import")) {
				Label("Import IPA", systemImage: "square.and.arrow.down")
			}
		}
		.displayName("Import IPA")
		.description("Pick an IPA from Files and add it to your Library.")
	}
}

@available(iOS 18.0, *)
struct PasteLinkControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "QuillPasteLinkControl") {
			ControlWidgetButton(action: OpenQuillLinkIntent("feather://paste")) {
				Label("Download Copied Link", systemImage: "link.badge.plus")
			}
		}
		.displayName("Download Copied Link")
		.description("Download the IPA link you copied.")
	}
}

@available(iOS 18.0, *)
struct SignLatestControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "QuillSignLatestControl") {
			ControlWidgetButton(action: OpenQuillLinkIntent("feather://sign-latest")) {
				Label("Sign Latest IPA", systemImage: "signature")
			}
		}
		.displayName("Sign Latest IPA")
		.description("Open the signing screen for the IPA you added last.")
	}
}

@available(iOS 18.0, *)
struct CertificateStatusProvider: ControlValueProvider {
	struct Value {
		var title: String
		var systemImage: String
	}

	var previewValue: Value { Value(title: "214 days left", systemImage: "checkmark.seal.fill") }

	func currentValue() async throws -> Value {
		guard let certificate = WidgetSnapshotStore.read()?.certificate else {
			return Value(title: "No Certificate", systemImage: "seal")
		}
		if certificate.revoked { return Value(title: "Revoked", systemImage: "xmark.seal.fill") }
		guard let expiration = certificate.expiration else { return Value(title: certificate.name, systemImage: "checkmark.seal.fill") }
		let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: expiration)).day ?? 0
		if days < 0 { return Value(title: "Expired", systemImage: "exclamationmark.triangle.fill") }
		return Value(title: days == 1 ? "1 day left" : "\(days) days left", systemImage: days <= 7 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
	}
}

@available(iOS 18.0, *)
struct CertificateStatusControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "QuillCertificateControl", provider: CertificateStatusProvider()) { value in
			ControlWidgetButton(action: OpenQuillLinkIntent("feather://certificates")) {
				Label(value.title, systemImage: value.systemImage)
			}
		}
		.displayName("Certificate")
		.description("Days left on your certificate. Tap to open your certificates.")
	}
}
