import SwiftUI
import NimbleViews

/// Shows what the app asks for and what the chosen certificate lets it keep.
struct EntitlementsReportView: View {
	let report: EntitlementsReport

	var body: some View {
		NBList(.localized("Entitlements")) {
			Section {
				Label {
					Text(_sourceText).font(.footnote)
				} icon: {
					Image(systemName: _sourceIcon)
				}
			}

			if !report.readApp {
				Section {
					Text(.localized("Couldn't read this app's entitlements.")).font(.footnote).foregroundStyle(.secondary)
				}
			} else if report.requested.isEmpty && report.notAllowed.isEmpty {
				Section {
					Text(.localized("This app doesn't ask for any special features, so nothing is lost when signing.")).font(.footnote).foregroundStyle(.secondary)
				}
			}

			_section(
				.localized("Not Allowed by This Certificate"),
				footer: .localized("Your entitlements file asks for these, but the certificate's profile doesn't include them. iOS may refuse to install the app."),
				items: report.notAllowed,
				icon: "exclamationmark.triangle.fill",
				color: .red
			)
			_section(
				.localized("Won't Work"),
				footer: .localized("The app asks for these, but they're removed when signing, so features that need them won't work."),
				items: report.dropped,
				icon: "xmark.circle.fill",
				color: .orange
			)
			_section(
				.localized("Will Be Kept"),
				footer: nil,
				items: report.kept,
				icon: "checkmark.circle.fill",
				color: .green
			)
			if report.source != .noCertificate {
				_section(
					.localized("Certificate Includes"),
					footer: .localized("Basics every signed app gets, like the app and team identifiers, aren't listed."),
					items: report.provided,
					icon: "key.fill",
					color: .secondary,
					emptyText: .localized("Nothing beyond the basics.")
				)
			}
		}
	}

	private var _sourceText: String {
		switch report.source {
		case .profile(let name):
			return String(format: .localized("Signing with %@ uses the entitlements in its provisioning profile."), name)
		case .appleID(let name):
			return String(format: .localized("%@ is a free Apple ID certificate. These don't include extra features like iCloud, push notifications or App Groups."), name)
		case .customFile(let name):
			return String(format: .localized("Signing uses your entitlements file %@ instead of the certificate's."), name)
		case .noCertificate:
			return .localized("No certificate is used, so this only lists what the app asks for.")
		}
	}

	private var _sourceIcon: String {
		switch report.source {
		case .profile: "checkmark.seal"
		case .appleID: "person.crop.circle"
		case .customFile: "doc.text"
		case .noCertificate: "questionmark.circle"
		}
	}

	@ViewBuilder
	private func _section(
		_ title: String,
		footer: String?,
		items: [EntitlementsReport.Item],
		icon: String,
		color: Color,
		emptyText: String? = nil
	) -> some View {
		if !items.isEmpty || emptyText != nil {
			Section {
				if items.isEmpty, let emptyText {
					Text(emptyText).font(.footnote).foregroundStyle(.secondary)
				}
				ForEach(items) { item in
					Label {
						VStack(alignment: .leading, spacing: 2) {
							Text(item.name)
							if item.name != item.key {
								Text(item.key)
									.font(.caption.monospaced())
									.foregroundStyle(.secondary)
									.lineLimit(1)
									.truncationMode(.middle)
							}
						}
					} icon: {
						Image(systemName: icon).foregroundStyle(color)
					}
					.textSelection(.enabled)
				}
			} header: {
				Text(title)
			} footer: {
				if let footer { Text(footer) }
			}
		}
	}
}
