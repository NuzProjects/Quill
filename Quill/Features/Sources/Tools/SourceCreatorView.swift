import SwiftUI
import NimbleViews

/// "Make a Source": turns apps in the Library into an AltStore-style source file you can host anywhere.
struct SourceCreatorView: View {
	struct Entry: Identifiable {
		let id: String
		var include: Bool
		let name: String
		let bundleIdentifier: String
		let version: String
		let date: Date
		var downloadURL: String
		var iconURL: String
		var subtitle: String
	}

	@AppStorage("Quill.sourceCreator.name") private var _name = ""
	@AppStorage("Quill.sourceCreator.identifier") private var _identifier = ""
	@AppStorage("Quill.sourceCreator.subtitle") private var _subtitle = ""
	@AppStorage("Quill.sourceCreator.website") private var _website = ""
	@AppStorage("Quill.sourceCreator.iconURL") private var _iconURL = ""
	@AppStorage("Quill.sourceCreator.links") private var _savedLinksData = Data()

	@State private var _entries: [Entry] = []
	@State private var _didLoad = false

	private var _includedCount: Int { _entries.filter(\.include).count }
	private var _missingLinks: Int { _entries.filter { $0.include && URL(string: $0.downloadURL)?.scheme?.hasPrefix("http") != true }.count }

	var body: some View {
		Form {
			NBSection(.localized("Source")) {
				TextField(.localized("Name"), text: $_name)
				TextField(.localized("Identifier (e.g. com.you.source)"), text: $_identifier)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
				TextField(.localized("Subtitle"), text: $_subtitle)
				TextField(.localized("Website"), text: $_website)
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
				TextField(.localized("Icon Link"), text: $_iconURL)
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
			}

			NBSection(.localized("Apps"), secondary: "\(_includedCount)") {
				if _entries.isEmpty {
					Text(.localized("Add apps to your Library first."))
						.foregroundStyle(.secondary)
				}
				ForEach($_entries) { $entry in
					DisclosureGroup {
						TextField(.localized("IPA Download Link"), text: $entry.downloadURL)
							.keyboardType(.URL)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled()
						TextField(.localized("Icon Link (optional)"), text: $entry.iconURL)
							.keyboardType(.URL)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled()
						TextField(.localized("Subtitle (optional)"), text: $entry.subtitle)
					} label: {
						Toggle(isOn: $entry.include) {
							VStack(alignment: .leading, spacing: 2) {
								Text(entry.name)
								Text("\(entry.version) · \(entry.bundleIdentifier)")
									.font(.caption)
									.foregroundStyle(.secondary)
								if entry.include, URL(string: entry.downloadURL)?.scheme?.hasPrefix("http") != true {
									Text(.localized("Needs a download link"))
										.font(.caption)
										.foregroundStyle(.orange)
								}
							}
						}
					}
				}
			} footer: {
				Text(.localized("Each app needs a link to its IPA, like a GitHub release or your own server. Apps you downloaded from a link are filled in for you."))
			}

			Section {
				Button {
					_export()
				} label: {
					Label(.localized("Export Source File"), systemImage: "square.and.arrow.up")
				}
				.disabled(_name.trimmingCharacters(in: .whitespaces).isEmpty || _includedCount == 0)
			} footer: {
				if _missingLinks > 0 {
					Text(String(format: .localized("%d apps without a download link will be left out."), _missingLinks))
				} else {
					Text(.localized("Upload the file anywhere that gives you a direct link, then add that link as a source in Quill, AltStore or SideStore."))
				}
			}
		}
		.navigationTitle(.localized("Make a Source"))
		.navigationBarTitleDisplayMode(.inline)
		.onAppear(perform: _load)
		.onDisappear(perform: _saveLinks)
	}

	private func _load() {
		guard !_didLoad else { return }
		_didLoad = true
		let saved = (try? JSONDecoder().decode([String: [String: String]].self, from: _savedLinksData)) ?? [:]
		let context = Storage.shared.context
		let apps = ((try? context.fetch(Imported.fetchRequest())) ?? []).map { $0 as AppInfoPresentable }
			+ ((try? context.fetch(Signed.fetchRequest())) ?? []).map { $0 as AppInfoPresentable }

		var newest: [String: AppInfoPresentable] = [:]
		for app in apps {
			guard let identifier = app.identifier else { continue }
			if let existing = newest[identifier], (existing.date ?? .distantPast) >= (app.date ?? .distantPast) { continue }
			newest[identifier] = app
		}

		_entries = newest.values
			.map { app in
				let identifier = app.identifier ?? ""
				let remembered = saved[identifier] ?? [:]
				let downloaded = app.source.flatMap { $0.scheme?.hasPrefix("http") == true ? $0.absoluteString : nil }
				return Entry(
					id: identifier,
					include: remembered["include"].map { $0 == "1" } ?? true,
					name: app.name ?? identifier,
					bundleIdentifier: identifier,
					version: app.version ?? "1.0",
					date: app.date ?? Date(),
					downloadURL: remembered["download"] ?? downloaded ?? "",
					iconURL: remembered["icon"] ?? "",
					subtitle: remembered["subtitle"] ?? ""
				)
			}
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		if _identifier.isEmpty {
			_identifier = "dev.quill.source.\(UUID().uuidString.prefix(8).lowercased())"
		}
	}

	private func _saveLinks() {
		var saved: [String: [String: String]] = [:]
		for entry in _entries {
			saved[entry.id] = [
				"include": entry.include ? "1" : "0",
				"download": entry.downloadURL,
				"icon": entry.iconURL,
				"subtitle": entry.subtitle
			]
		}
		if let data = try? JSONEncoder().encode(saved) { _savedLinksData = data }
	}

	private func _export() {
		_saveLinks()
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withFullDate]

		func clean(_ value: String) -> String? {
			let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmed.isEmpty ? nil : trimmed
		}

		let apps: [[String: Any]] = _entries
			.filter { $0.include && URL(string: $0.downloadURL)?.scheme?.hasPrefix("http") == true }
			.map { entry in
				let date = dateFormatter.string(from: entry.date)
				let version: [String: Any] = [
					"version": entry.version,
					"date": date,
					"downloadURL": entry.downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
				]
				var app: [String: Any] = [
					"name": entry.name,
					"bundleIdentifier": entry.bundleIdentifier,
					"developerName": clean(_name) ?? "Quill",
					"localizedDescription": clean(entry.subtitle) ?? entry.name,
					"versions": [version],
					// Older AltStore versions read these instead of "versions"
					"version": entry.version,
					"versionDate": date,
					"downloadURL": version["downloadURL"] as Any
				]
				if let subtitle = clean(entry.subtitle) { app["subtitle"] = subtitle }
				if let icon = clean(entry.iconURL) { app["iconURL"] = icon }
				return app
			}

		var source: [String: Any] = [
			"name": _name.trimmingCharacters(in: .whitespacesAndNewlines),
			"identifier": clean(_identifier) ?? "dev.quill.source",
			"apps": apps,
			"news": [] as [Any]
		]
		if let subtitle = clean(_subtitle) { source["subtitle"] = subtitle }
		if let website = clean(_website) { source["website"] = website }
		if let icon = clean(_iconURL) { source["iconURL"] = icon }

		guard
			!apps.isEmpty,
			let data = try? JSONSerialization.data(withJSONObject: source, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
		else {
			UIAlertController.showAlertWithOk(title: .localized("Nothing to Export"), message: .localized("Add a download link to at least one app."))
			return
		}

		let fileName = _name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-").lowercased()
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName.isEmpty ? "source" : fileName).json")
		do {
			try data.write(to: url, options: .atomic)
			UIActivityViewController.show(activityItems: [url])
		} catch {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
		}
	}
}
