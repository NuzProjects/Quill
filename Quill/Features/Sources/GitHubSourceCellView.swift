import SwiftUI
import NimbleViews

struct GitHubSourceCellView: View {
	@ObservedObject private var githubSources = GitHubSources.shared

	var repository: GitHubRepository

	private static let relativeFormatter = RelativeDateTimeFormatter()

	private var subtitle: String {
		let link = "github.com/\(repository.slug)"
		guard let updated = githubSources.lastUpdated[repository.slug] else { return link }
		return "Updated \(Self.relativeFormatter.localizedString(for: updated, relativeTo: Date()))\n\(link)"
	}

	var body: some View {
		FRIconCellView(
			title: repository.name,
			subtitle: subtitle,
			iconUrl: repository.avatarURL
		)
		.swipeActions {
			_actions()
			_contextActions()
		}
		.contextMenu {
			_contextActions()
			Divider()
			_actions()
		}
	}

	@ViewBuilder
	private func _actions() -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			githubSources.remove(repository)
		}
	}

	@ViewBuilder
	private func _contextActions() -> some View {
		Button(.localized("Copy"), systemImage: "doc.on.clipboard") {
			UIPasteboard.general.string = repository.webURL.absoluteString
		}
		Button(.localized("Open in GitHub"), systemImage: "safari") {
			UIApplication.shared.open(repository.webURL)
		}
	}
}
