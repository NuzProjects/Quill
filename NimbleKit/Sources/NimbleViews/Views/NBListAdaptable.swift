import SwiftUI

public struct NBListAdaptable<Content>: View where Content: View {
	private var _content: Content

	public init(@ViewBuilder content: () -> Content) {
		self._content = content()
	}

	// Always plain rows, like iPhone, including on iPad. The compact size
	// class is passed down so cells use their row style, not cards.
	public var body: some View {
		List {
			_content
		}
		.listStyle(.plain)
		.environment(\.nbInlineSectionHeaders, true)
		.environment(\.horizontalSizeClass, .compact)
	}
}
