import SwiftUI
import NimbleViews

/// "Inspect App": everything inside an IPA, explained in plain words.
struct AppInspectorView: View {
	var app: AppInfoPresentable
	@State private var _inspection: AppInspection?

	private static let _palette: [Color] = [.accentColor, .orange, .purple, .green, .pink, .teal, .gray]

	var body: some View {
		List {
			if let inspection = _inspection {
				_sizeSection(inspection)
				_compatibilitySection(inspection)
				_permissionsSection(inspection)
				_partsSection(.localized("Frameworks"), parts: inspection.frameworks, systemImage: "shippingbox")
				_partsSection(.localized("Extensions"), parts: inspection.extensions + [inspection.watchApp].compactMap { $0 }, systemImage: "puzzlepiece.extension")
				_featuresSection(inspection)
			} else {
				HStack {
					Spacer()
					ProgressView()
					Spacer()
				}
				.listRowBackground(EmptyView())
			}
		}
		.navigationTitle(.localized("Inspect App"))
		.navigationBarTitleDisplayMode(.inline)
		.task {
			guard _inspection == nil, let bundle = Storage.shared.getAppDirectory(for: app) else { return }
			let result = await Task.detached(priority: .userInitiated) { AppInspector.inspect(bundle) }.value
			withAnimation(.smooth) { _inspection = result }
		}
	}

	private func _bytes(_ value: Int64) -> String {
		ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
	}

	@ViewBuilder
	private func _sizeSection(_ inspection: AppInspection) -> some View {
		NBSection(.localized("Size")) {
			VStack(alignment: .leading, spacing: 10) {
				Text(_bytes(inspection.totalBytes))
					.font(.title2.weight(.semibold))
				GeometryReader { proxy in
					HStack(spacing: 2) {
						ForEach(Array(inspection.sizeBreakdown.enumerated()), id: \.element.id) { index, slice in
							Rectangle()
								.fill(Self._palette[index % Self._palette.count])
								.frame(width: max(3, proxy.size.width * CGFloat(slice.bytes) / CGFloat(max(1, inspection.totalBytes))))
						}
					}
					.clipShape(Capsule())
				}
				.frame(height: 12)
			}
			.padding(.vertical, 4)

			ForEach(Array(inspection.sizeBreakdown.enumerated()), id: \.element.id) { index, slice in
				LabeledContent {
					Text(_bytes(slice.bytes))
				} label: {
					Label {
						Text(slice.label)
					} icon: {
						Image(systemName: slice.systemImage)
							.foregroundStyle(Self._palette[index % Self._palette.count])
					}
				}
			}
		} footer: {
			if inspection.watchApp != nil || inspection.languages.count > 3 {
				Text(.localized("You can make the app smaller by removing the Apple Watch app and unused languages in the signing options."))
			}
		}
	}

	@ViewBuilder
	private func _compatibilitySection(_ inspection: AppInspection) -> some View {
		NBSection(.localized("Compatibility")) {
			if let minimum = inspection.minimumOS {
				LabeledContent(.localized("Requires"), value: "iOS \(minimum)")
			}
			if !inspection.devices.isEmpty {
				LabeledContent(.localized("Made For"), value: ListFormatter.localizedString(byJoining: inspection.devices))
			}
			if !inspection.architectures.isEmpty {
				LabeledContent(.localized("Architectures"), value: inspection.architectures.joined(separator: ", "))
			}
			if let sdk = inspection.builtWithSDK {
				LabeledContent(.localized("Built For"), value: sdk)
			}
			if let xcode = inspection.builtWithXcode {
				LabeledContent(.localized("Built With"), value: xcode)
			}
			LabeledContent(.localized("App Store Encryption")) {
				if inspection.isEncrypted {
					Label(.localized("Encrypted"), systemImage: "lock.fill")
						.foregroundStyle(.red)
				} else {
					Label(.localized("Decrypted"), systemImage: "lock.open")
						.foregroundStyle(.green)
				}
			}
		} footer: {
			if inspection.isEncrypted {
				Text(.localized("Encrypted apps won't open after signing. Use a decrypted IPA instead."))
			}
		}
	}

	@ViewBuilder
	private func _permissionsSection(_ inspection: AppInspection) -> some View {
		NBSection(.localized("Permissions It Can Ask For")) {
			if inspection.permissions.isEmpty {
				Text(.localized("This app doesn't ask for any permissions."))
					.foregroundStyle(.secondary)
			} else {
				ForEach(inspection.permissions) { permission in
					VStack(alignment: .leading, spacing: 2) {
						Text(permission.name)
						if !permission.reason.isEmpty {
							Text(permission.reason)
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
					}
				}
			}
		}
	}

	@ViewBuilder
	private func _partsSection(_ title: String, parts: [AppInspection.Part], systemImage: String) -> some View {
		if !parts.isEmpty {
			NBSection(title) {
				ForEach(parts) { part in
					LabeledContent {
						Text(_bytes(part.bytes))
					} label: {
						VStack(alignment: .leading, spacing: 2) {
							Text(part.name)
							if let detail = part.detail {
								Text(detail)
									.font(.footnote)
									.foregroundStyle(.secondary)
							}
						}
					}
				}
			}
		}
	}

	@ViewBuilder
	private func _featuresSection(_ inspection: AppInspection) -> some View {
		NBSection(.localized("Features")) {
			LabeledContent(.localized("Entitlements"), value: "\(inspection.entitlementCount)")
			LabeledContent(.localized("Shows in Files"), value: inspection.supportsFiles ? String.localized("Yes") : String.localized("No"))
			if !inspection.backgroundModes.isEmpty {
				LabeledContent(.localized("Runs in Background For"), value: ListFormatter.localizedString(byJoining: inspection.backgroundModes))
			}
			if !inspection.urlSchemes.isEmpty {
				LabeledContent(.localized("Link Schemes"), value: inspection.urlSchemes.map { "\($0)://" }.joined(separator: ", "))
			}
			LabeledContent(.localized("Languages"), value: inspection.languages.isEmpty ? "—" : "\(inspection.languages.count)")
		} footer: {
			if !inspection.languages.isEmpty {
				Text(ListFormatter.localizedString(byJoining: inspection.languages))
			}
		}
	}
}
