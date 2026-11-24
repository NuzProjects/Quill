import SwiftUI

/// GitHub release notes laid out like the update pop-up: a heading per group
/// ("**New:**"), then one row per change with an icon. Used by the pop-up and
/// by Settings > Updates so both look the same.
struct ReleaseNotesView: View {
	struct Group: Identifiable {
		let title: String?
		var items: [String]
		var id: String { (title ?? "") + items.joined() }
	}

	let groups: [Group]
	var spacing: CGFloat = 26

	init(markdown: String, spacing: CGFloat = 26) {
		self.groups = Self.parse(markdown)
		self.spacing = spacing
	}

	var body: some View {
		VStack(alignment: .leading, spacing: spacing) {
			ForEach(groups) { group in
				VStack(alignment: .leading, spacing: 12) {
					if let title = group.title {
						Text(verbatim: title)
							.font(.headline)
							.foregroundStyle(.primary)
					}
					ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
						HStack(alignment: .firstTextBaseline, spacing: 10) {
							Image(systemName: Self.icon(for: group.title))
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(Color.accentColor)
								.frame(width: 20)
							Text(LocalizedStringKey(item))
								.font(.subheadline)
								.foregroundStyle(Color(uiColor: .secondaryLabel))
								.fixedSize(horizontal: false, vertical: true)
								.frame(maxWidth: .infinity, alignment: .leading)
						}
					}
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	static func icon(for title: String?) -> String {
		let name = (title ?? "").lowercased()
		if name.contains("secur") { return "lock.shield" }
		if name.contains("fix") || name.contains("bug") { return "wrench.and.screwdriver" }
		if name.contains("feature") || name.contains("new") { return "sparkles" }
		return "checkmark.circle"
	}

	/// Turns "**New:**" / "### New" headings and "* " / "- " / "• " bullets into groups.
	/// Plain lines that aren't bullets become their own rows.
	static func parse(_ markdown: String) -> [Group] {
		var groups: [Group] = []
		for raw in markdown.components(separatedBy: .newlines) {
			let line = raw.trimmingCharacters(in: .whitespaces)
			guard !line.isEmpty else { continue }
			if let heading = _heading(line) {
				groups.append(Group(title: heading, items: []))
				continue
			}
			var item = line
			for prefix in ["* ", "- ", "• "] where item.hasPrefix(prefix) {
				item = String(item.dropFirst(prefix.count))
			}
			if groups.isEmpty { groups.append(Group(title: nil, items: [])) }
			groups[groups.count - 1].items.append(item)
		}
		return groups.filter { !$0.items.isEmpty }
	}

	private static func _heading(_ line: String) -> String? {
		if line.hasPrefix("#") {
			let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
			return text.isEmpty ? nil : text
		}
		// A line that is only bold text, like "**New:**".
		if line.hasPrefix("**"), line.hasSuffix("**") || line.hasSuffix("**:") {
			var text = line.replacingOccurrences(of: "**", with: "")
			if text.hasSuffix(":") { text.removeLast() }
			text = text.trimmingCharacters(in: .whitespaces)
			return text.isEmpty ? nil : text
		}
		return nil
	}
}
