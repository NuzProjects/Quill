import SwiftUI

/// Text whose digits roll like an odometer: old digits slide up and out,
/// new ones slide up from below. On first appear the digits roll up from 0.
public struct NBRollingText: View {
	@Environment(\.accessibilityReduceMotion) private var _reduceMotion
	@State private var _shown: String

	public var text: String

	public init(_ text: String) {
		self.text = text
		self.__shown = State(initialValue: Self._zeroed(text))
	}

	public var body: some View {
		Text(verbatim: _reduceMotion ? text : _shown)
			.monospacedDigit()
			.contentTransition(.numericText(countsDown: false))
			.onAppear { _roll(to: text) }
			.onChange(of: text) { _roll(to: $0) }
	}

	private func _roll(to value: String) {
		guard _shown != value else { return }
		withAnimation(.snappy(duration: 0.55)) { _shown = value }
	}

	private static func _zeroed(_ value: String) -> String {
		String(value.map { $0.isNumber ? "0" : $0 })
	}
}
