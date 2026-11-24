import SwiftUI
import NimbleViews

struct FRExpirationPillView: View {
	let title: String
	let revoked: Bool
	let expiration: Date.ExpirationInfo?

	var body: some View {
		let textLabel = revoked
			? .localized("Revoked")
			: expiration?.formatted ?? title

		let textForeground = (expiration == nil)
			? Color.accentColor
			: .white

		let textBackground = revoked
			? .red
			: expiration?.color.opacity(0.85) ?? Color(uiColor: .quaternarySystemFill)

		NBRollingText(textLabel)
			.lineLimit(1)
			.font(.headline.bold())
			.foregroundStyle(textForeground)
			.padding(.horizontal, 12)
			.padding(.vertical, 6)
			.background(textBackground)
			.clipShape(Capsule())
	}
}
