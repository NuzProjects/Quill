import SwiftUI

struct UpdatePromptView: View {
	let release: GitHubRelease
	let notes: String?
	let onUpdate: () -> Void
	let onLater: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			ScrollView {
				VStack(spacing: 26) {
					_header()
					if let notes {
						ReleaseNotesView(markdown: notes)
							.padding(.horizontal, 4)
					}
				}
				.frame(maxWidth: .infinity)
				.padding(.horizontal, 20)
				.padding(.bottom, 24)
			}

			VStack(spacing: 8) {
				Button(action: onUpdate) {
					Text("Update")
						.font(.headline)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 6)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)

				Button(action: onLater) {
					Text("Later")
						.font(.headline)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 6)
				}
				.buttonStyle(.borderless)
				.controlSize(.large)
			}
			.padding(.horizontal, 20)
			.padding(.bottom, 20)
		}
	}

	private func _header() -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("Update Available")
				.font(.largeTitle.bold())
			Text(verbatim: "Quill \(QuillUpdater.displayName(release))")
				.font(.title3)
				.foregroundStyle(Color(uiColor: .secondaryLabel))
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 4)
		.padding(.top, 36)
	}
}
