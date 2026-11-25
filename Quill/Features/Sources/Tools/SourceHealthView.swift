import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

/// "Check Sources": fetches every source and says which ones are broken, slow or haven't been updated in a while.
struct SourceHealthView: View {
	struct Result: Identifiable {
		enum Status: Sendable {
			case working
			case stale
			case slow
			case broken
		}

		var id: NSManagedObjectID { source.objectID }
		let source: AltSource
		let status: Status
		let detail: String
	}

	/// What one check found, without the Core Data object, so it can come back from a background task.
	private struct _Finding: Sendable {
		let status: Result.Status
		let detail: String
	}

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>

	@State private var _results: [Result] = []
	@State private var _checked = 0
	@State private var _isChecking = false

	private static let _staleAfterDays = 180

	var body: some View {
		List {
			if _isChecking {
				Section {
					ProgressView(value: Double(_checked), total: Double(max(1, _sources.count))) {
						Text(String(format: .localized("Checked %d of %d"), _checked, _sources.count))
							.font(.footnote)
					}
				}
			}

			if !_isChecking, !_results.isEmpty {
				Section {
					_summaryRow(.localized("Working"), count: _results.filter { $0.status == .working }.count, color: .green)
					_summaryRow(.localized("Slow"), count: _results.filter { $0.status == .slow }.count, color: .yellow)
					_summaryRow(.localized("Not Updated Lately"), count: _results.filter { $0.status == .stale }.count, color: .orange)
					_summaryRow(.localized("Broken"), count: _results.filter { $0.status == .broken }.count, color: .red)
				}
			}

			let problems = _results.filter { $0.status != .working }
			if !problems.isEmpty {
				NBSection(.localized("Needs Attention")) {
					ForEach(problems) { _row($0) }
				} footer: {
					Text(.localized("Swipe left on a broken source to remove it."))
				}
			}

			let working = _results.filter { $0.status == .working }
			if !working.isEmpty {
				NBSection(.localized("Working")) {
					ForEach(working) { _row($0) }
				}
			}
		}
		.navigationTitle(.localized("Check Sources"))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Check Again")) { Task { await _check() } }
					.disabled(_isChecking)
			}
		}
		.overlay {
			if _sources.isEmpty {
				Text(.localized("You haven't added any sources yet."))
					.foregroundStyle(.secondary)
			}
		}
		.task { if _results.isEmpty { await _check() } }
	}

	private func _summaryRow(_ title: String, count: Int, color: Color) -> some View {
		LabeledContent {
			Text("\(count)")
		} label: {
			Label {
				Text(title)
			} icon: {
				Image(systemName: "circle.fill")
					.foregroundStyle(color)
					.font(.caption)
			}
		}
	}

	private func _row(_ result: Result) -> some View {
		HStack(spacing: 12) {
			Image(systemName: _icon(result.status))
				.foregroundStyle(_color(result.status))
				.font(.title3)
				.frame(width: 28)
			VStack(alignment: .leading, spacing: 2) {
				Text(result.source.name ?? result.source.sourceURL?.host ?? .localized("Unknown"))
					.font(.body.weight(.medium))
				Text(result.detail)
					.font(.footnote)
					.foregroundStyle(.secondary)
				if let url = result.source.sourceURL?.absoluteString {
					Text(url)
						.font(.caption2)
						.foregroundStyle(.tertiary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
		}
		.swipeActions {
			Button(.localized("Remove"), role: .destructive) {
				Storage.shared.deleteSource(for: result.source)
				_results.removeAll { $0.id == result.id }
			}
		}
		.contextMenu {
			if let url = result.source.sourceURL?.absoluteString {
				Button(.localized("Copy Link"), systemImage: "doc.on.doc") {
					UIPasteboard.general.string = url
					ClipboardImport.markOwnCopy()
				}
			}
		}
	}

	private func _icon(_ status: Result.Status) -> String {
		switch status {
		case .working: "checkmark.circle.fill"
		case .slow: "tortoise.fill"
		case .stale: "clock.badge.exclamationmark.fill"
		case .broken: "xmark.octagon.fill"
		}
	}

	private func _color(_ status: Result.Status) -> Color {
		switch status {
		case .working: .green
		case .slow: .yellow
		case .stale: .orange
		case .broken: .red
		}
	}

	@MainActor
	private func _check() async {
		_isChecking = true
		_checked = 0
		_results = []
		let sources = Array(_sources)
		var results: [Result] = []

		await withTaskGroup(of: (Int, _Finding).self) { group in
			for (index, source) in sources.enumerated() {
				let url = source.sourceURL
				group.addTask { (index, await Self._check(url)) }
			}
			for await (index, finding) in group {
				results.append(Result(source: sources[index], status: finding.status, detail: finding.detail))
				_checked += 1
			}
		}

		let order: [Result.Status] = [.broken, .stale, .slow, .working]
		withAnimation(.smooth) {
			_results = results.sorted {
				let a = order.firstIndex(of: $0.status) ?? 0, b = order.firstIndex(of: $1.status) ?? 0
				return a != b ? a < b : ($0.source.name ?? "") < ($1.source.name ?? "")
			}
			_isChecking = false
		}
	}

	private static func _check(_ url: URL?) async -> _Finding {
		guard let url else {
			return _Finding(status: .broken, detail: .localized("This source has no link."))
		}
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
		request.httpMethod = "GET"
		let start = Date()
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			let seconds = Date().timeIntervalSince(start)
			if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
				return _Finding(status: .broken, detail: String(format: .localized("The server answered with error %d."), http.statusCode))
			}
			let repository: ASRepository
			do {
				repository = try JSONDecoder().decode(ASRepository.self, from: data)
			} catch {
				return _Finding(status: .broken, detail: .localized("The link works, but it isn't a valid source file."))
			}
			let newest = repository.apps.compactMap { $0.currentDate?.date }.max()
			let count = repository.apps.count
			let appsText = count == 1 ? String.localized("1 app") : String(format: .localized("%d apps"), count)
			if let newest, let days = Calendar.current.dateComponents([.day], from: newest, to: Date()).day, days > _staleAfterDays {
				let ago = RelativeDateTimeFormatter().localizedString(for: newest, relativeTo: Date())
				return _Finding(status: .stale, detail: "\(appsText) · " + String(format: .localized("last updated %@"), ago))
			}
			if seconds > 8 {
				return _Finding(status: .slow, detail: "\(appsText) · " + String(format: .localized("took %.0f seconds to load"), seconds))
			}
			var detail = appsText
			if let newest {
				detail += " · " + String(format: .localized("updated %@"), RelativeDateTimeFormatter().localizedString(for: newest, relativeTo: Date()))
			}
			return _Finding(status: .working, detail: detail)
		} catch {
			let seconds = Date().timeIntervalSince(start)
			let message: String
			switch (error as? URLError)?.code {
			case .timedOut: message = .localized("The server didn't answer in time.")
			case .cannotFindHost, .dnsLookupFailed: message = .localized("This website doesn't exist anymore.")
			case .notConnectedToInternet: message = .localized("You're offline.")
			case .serverCertificateUntrusted, .secureConnectionFailed: message = .localized("The website's security certificate isn't valid.")
			default: message = error.localizedDescription
			}
			return _Finding(status: .broken, detail: message)
		}
	}
}
