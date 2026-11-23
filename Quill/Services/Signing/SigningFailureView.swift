import SwiftUI

struct SigningFailure: Identifiable {
	let id = UUID()
	let appName: String
	let icon: UIImage?
	let error: String
}

/// Shown when a failed signing card is tapped: the full error, plus ways to copy or report it.
struct SigningFailureView: View {
	let failure: SigningFailure
	@Environment(\.dismiss) private var dismiss
	@State private var copied = false

	var body: some View {
		NavigationStack {
			List {
				Section {
					HStack(spacing: 12) {
						ProgressPanelIcon(image: failure.icon)
						VStack(alignment: .leading, spacing: 2) {
							Text(failure.appName).font(.headline).lineLimit(1)
							Text(.localized("Signing failed")).font(.subheadline).foregroundStyle(.red)
						}
					}
				}

				Section {
					Text(failure.error)
						.font(.callout.monospaced())
						.textSelection(.enabled)
				} header: {
					Text(.localized("Error"))
				}

				Section {
					Button {
						UIPasteboard.general.string = "\(failure.appName): \(failure.error)"
						UINotificationFeedbackGenerator().notificationOccurred(.success)
						withAnimation(.snappy) { copied = true }
					} label: {
						Label(copied ? String.localized("Copied") : String.localized("Copy Error"), systemImage: copied ? "checkmark" : "doc.on.doc")
					}
					Button {
						if let url = DevLog.shared.signingIssueURL(appName: failure.appName, error: failure.error) { UIApplication.shared.open(url) }
					} label: {
						Label(String.localized("Report on GitHub"), systemImage: "exclamationmark.bubble")
					}
					NavigationLink {
						DeveloperLogsView()
					} label: {
						Label(String.localized("View Full Log"), systemImage: "doc.text.magnifyingglass")
					}
				} footer: {
					Text(.localized("The report opens a new GitHub issue with this error, recent signing log lines, and your device and Quill version filled in. Nothing is sent until you submit it."))
				}
			}
			.navigationTitle(String.localized("Signing Failed"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button(.localized("Done")) { dismiss() }
				}
			}
		}
		.presentationDetents([.medium, .large])
		.presentationDragIndicator(.visible)
	}
}
