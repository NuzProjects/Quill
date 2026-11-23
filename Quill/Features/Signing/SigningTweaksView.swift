import SwiftUI
import NimbleViews

struct SigningTweaksView: View {
	@State private var _isAddingPresenting = false

	@Binding var options: Options
	/// The app being signed, so tweaks can be checked against it.
	var app: AppInfoPresentable?
	@Binding var findings: [URL: [TweakInspector.Finding]]

	init(
		options: Binding<Options>,
		app: AppInfoPresentable? = nil,
		findings: Binding<[URL: [TweakInspector.Finding]]> = .constant([:])
	) {
		self._options = options
		self.app = app
		self._findings = findings
	}

	var body: some View {
		NBList(.localized("Tweaks")) {
			NBSection(.localized("Injection")) {
				SigningOptionsView.picker(
					.localized("Injection Path"),
					systemImage: "doc.badge.gearshape",
					selection: $options.injectPath,
					values: Options.InjectPath.allCases
				)
				SigningOptionsView.picker(
					.localized("Injection Folder"),
					systemImage: "folder.badge.gearshape",
					selection: $options.injectFolder,
					values: Options.InjectFolder.allCases
				)

				Toggle(isOn: $options.injectIntoExtensions) {
					Label(.localized("Inject into Extensions"), systemImage: "syringe")
				}
			}

			NBSection(.localized("Tweaks")) {
				if !options.injectionFiles.isEmpty {
					ForEach(options.injectionFiles, id: \.absoluteString) { tweak in
						_file(tweak: tweak)
					}
				} else {
					Text(verbatim: .localized("No files chosen."))
						.font(.footnote)
						.foregroundColor(.disabled())
				}
			} footer: {
				if !options.injectionFiles.isEmpty {
					Text(.localized("Each tweak is checked for the right architecture, iOS version and libraries before it's injected."))
				}
			}
		}
		.task(id: options.injectionFiles) {
			let files = options.injectionFiles
			guard !files.isEmpty else { return }
			let context = TweakInspector.Context.make(app: app, identifier: options.appIdentifier)
			let result = await TweakInspector.inspect(files, context: context)
			guard !Task.isCancelled else { return }
			withAnimation(.snappy) {
				for (url, list) in result { findings[url] = list }
			}
		}
		.toolbar {
			NBToolbarButton(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing
			) {
				_isAddingPresenting = true
			}
		}
		.sheet(isPresented: $_isAddingPresenting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.dylib, .deb],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in
					guard !urls.isEmpty else { return }

					for url in urls {
						FileManager.default.moveAndStore(url, with: "QuillTweak") { url in
							options.injectionFiles.append(url)
						}
					}
				}
			)
			.ignoresSafeArea()
		}
		.animation(.smooth, value: options.injectionFiles)
	}
}

extension SigningTweaksView {
	@ViewBuilder
	private func _file(tweak: URL) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Label(tweak.lastPathComponent, systemImage: tweak.pathExtension.lowercased() == "deb" ? "shippingbox.fill" : "puzzlepiece.extension.fill")
				.lineLimit(2)
			_status(for: tweak)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			_fileActions(tweak: tweak)
		}
		.contextMenu {
			_fileActions(tweak: tweak)
		}
	}

	@ViewBuilder
	private func _fileActions(tweak: URL) -> some View {
		Button(role: .destructive) {
			FileManager.default.deleteStored(tweak) { url in
				if let index = options.injectionFiles.firstIndex(where: { $0 == url }) {
					options.injectionFiles.remove(at: index)
				}
			}
		} label: {
			Label(.localized("Delete"), systemImage: "trash")
		}
	}

	@ViewBuilder
	private func _status(for tweak: URL) -> some View {
		if let list = findings[tweak] {
			if list.isEmpty {
				Label(String.localized("Ready"), systemImage: "checkmark.circle.fill")
					.font(.footnote)
					.foregroundStyle(.green)
			} else {
				ForEach(list) { finding in
					Label {
						Text(_text(for: finding, in: tweak)).font(.footnote)
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
					}
				}
			}
		} else if app != nil {
			HStack(spacing: 6) {
				ProgressView().controlSize(.small)
				Text(.localized("Checking…")).font(.footnote).foregroundStyle(.secondary)
			}
		}
	}

	/// For a .deb, name the library inside it; for a .dylib the row already names it.
	private func _text(for finding: TweakInspector.Finding, in tweak: URL) -> String {
		finding.file == tweak.lastPathComponent ? finding.message : "\(finding.file): \(finding.message)"
	}
}
