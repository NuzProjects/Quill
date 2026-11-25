import SwiftUI
import UIKit
import NukeUI

struct TabbarView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@ObservedObject private var navigator = NavigatorPreferences.shared
	@State private var selected: TabEnum = NavigatorPreferences.shared.tabs.first ?? .settings
	@ObservedObject private var updater = QuillUpdater.shared
	@ObservedObject private var router = NotificationRouter.shared
	@ObservedObject private var sourceUpdates = UpdateManager.shared
	@ObservedObject private var githubUpdates = GitHubReleases.shared
	@State private var installingFromPrompt = false
	@State private var promptedRelease: GitHubRelease?
	@State private var acceptedPrompt = false
	@State private var showWhatsNew = false
	@State private var showOnboarding = false
	@ObservedObject private var githubSources = GitHubSources.shared
	@ObservedObject private var sourcesViewModel = SourcesViewModel.shared
	@State private var _sidebarExtra: SidebarItem?
	@State private var _isAddingSource = false
	@State private var _splitVisibility: NavigationSplitViewVisibility = .all
	@State private var _visitedTabs: Set<TabEnum> = []
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	/// What the iPad sidebar has selected: one of the main tabs, or a source row under Sources.
	enum SidebarItem: Hashable {
		case tab(TabEnum)
		case allSources
		case source(String)
		case github(String)
	}

	private var _sidebarSelection: Binding<SidebarItem> {
		Binding(
			get: { _sidebarExtra ?? .tab(selected) },
			set: { new in
				if new != (_sidebarExtra ?? .tab(selected)) { TabTransition.crossfade() }
				if case .tab(let tab) = new {
					_sidebarExtra = nil
					selected = tab
				} else {
					_sidebarExtra = new
				}
			}
		)
	}

	private var _selection: Binding<TabEnum> {
		Binding(
			get: { selected },
			set: { new in
				if new != selected { TabTransition.crossfade() }
				selected = new
			}
		)
	}

	private var _libraryUpdateCount: Int {
		Set(sourceUpdates.updates.keys).union(githubUpdates.updates.keys).count
	}

	/// iPad at full width shows the sidebar, so nothing sits along the bottom edge.
	private var _tabBarAtTop: Bool {
		UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
	}

	@ViewBuilder
	private var _classicTabView: some View {
		TabView(selection: _selection) {
			ForEach(navigator.tabs, id: \.self) { tab in
				TabEnum.view(for: tab)
					.environment(\.managedObjectContext, Storage.shared.context)
					.tabItem { Label(tab.title, systemImage: tab.icon) }
					.badge(tab == .library ? _libraryUpdateCount : 0)
					.tag(tab)
			}
		}
	}

	@ViewBuilder
	private var _tabView: some View {
		if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular {
			_splitView
		} else {
			_classicTabView
		}
	}

	var body: some View {
		_tabView
		.symbolVariant(.fill)
		.background(TabLabelApplier(tabs: navigator.tabs, showLabels: navigator.showLabels))
		.overlay(alignment: .bottom) {
			VStack(spacing: 0) {
				ActivityProgressPanel()
				ClipboardImportPill()
				OfflinePill()
			}
				.frame(maxWidth: _tabBarAtTop ? 480 : .infinity)
				.padding(.bottom, _tabBarAtTop ? 20 : 58)
				.background(alignment: .bottom) {
					if let update = updater.signedUpdate {
						InstallPreviewView(
							app: update.base,
							inBackground: true,
							onClose: { updater.signedUpdate = nil },
							onProgress: { label, fraction in
								updater.installLabel = label
								updater.installFraction = fraction
							}
						)
						.id(update.id)
					}
				}
		}
		.onChange(of: router.openLibrary) { open in
			guard open else { return }
			router.openLibrary = false
			_sidebarExtra = nil
			if navigator.tabs.contains(.library), selected != .library {
				TabTransition.crossfade()
				selected = .library
			}
		}
		.onChange(of: router.openApp?.id) { id in
			if id != nil { _sidebarExtra = nil }
			guard id != nil, navigator.tabs.contains(.library), selected != .library else { return }
			TabTransition.crossfade()
			selected = .library
		}
		.onChange(of: router.importIPA) { importing in
			guard importing else { return }
			_sidebarExtra = nil
			if navigator.tabs.contains(.library), selected != .library {
				TabTransition.crossfade()
				selected = .library
			}
		}
		.onChange(of: router.signApp?.id) { id in
			if id != nil { _sidebarExtra = nil }
			guard id != nil, navigator.tabs.contains(.library), selected != .library else { return }
			TabTransition.crossfade()
			selected = .library
		}
		.sheet(item: $router.certificate) { certificate in
			NavigationStack {
				CertificateOverviewDetailView(cert: certificate)
					.toolbar {
						ToolbarItem(placement: .confirmationAction) {
							Button(.localized("Done")) { router.certificate = nil }
						}
					}
			}
		}
		.onChange(of: navigator.tabs) { tabs in
			if !tabs.contains(selected) { selected = tabs.contains(.settings) ? .settings : (tabs.first ?? .settings) }
		}
		.task {
			if !UserDefaults.standard.bool(forKey: "Feather.serverMethodSemiLocal") {
				UserDefaults.standard.set(1, forKey: "Feather.serverMethod")
				UserDefaults.standard.set(true, forKey: "Feather.serverMethodSemiLocal")
			}
			SSLCertificateCheck.run()
			Storage.shared.checkAllRevocations()
			if Onboarding.shouldShow { showOnboarding = true; return }
			CertificateExpiry.refresh()
			if WhatsNew.shouldShow { showWhatsNew = true }
			else { await updater.checkOnLaunch() }
		}
		.fullScreenCover(isPresented: $showOnboarding, onDismiss: {
			Onboarding.markSeen()
			WhatsNew.markSeen()
			CertificateExpiry.refresh()
		}) {
			OnboardingView()
		}
		.sheet(isPresented: $showWhatsNew, onDismiss: { Task { await updater.checkOnLaunch() } }) {
			WhatsNewView()
				.presentationDetents([.medium, .large])
				.presentationDragIndicator(.visible)
		}
		.sheet(item: Binding(get: { updater.promptRelease }, set: { updater.promptRelease = $0 }), onDismiss: {
			if let release = promptedRelease, !acceptedPrompt { updater.skip(release) }
			if acceptedPrompt { _installPromptedUpdate() }
			promptedRelease = nil
			acceptedPrompt = false
		}) { release in
			UpdatePromptView(release: release, notes: updater.releaseNotes) {
				acceptedPrompt = true
				updater.promptRelease = nil
			} onLater: {
				updater.promptRelease = nil
			}
			.onAppear { promptedRelease = release }
			.presentationDetents([.medium, .large])
			.presentationDragIndicator(.visible)
		}
		.onChange(of: updater.phase) { phase in
			guard installingFromPrompt else { return }
			switch phase {
			case .failed(let message):
				installingFromPrompt = false
				UIAlertController.showAlertWithOk(title: "Update Failed", message: message)
			case .ready, .idle:
				installingFromPrompt = false
			default:
				break
			}
		}
	}
}

private extension TabbarView {
	func _installPromptedUpdate() {
		_sidebarExtra = nil
		if navigator.tabs.contains(.settings) {
			if selected != .settings { TabTransition.crossfade() }
			selected = .settings
			updater.openUpdatesPage = true
		} else {
			installingFromPrompt = true
		}
		updater.install()
	}
}

private extension TabbarView {
	/// iPad at full width: a sidebar that always stays open, like the original Feather one, plus Quill's
	/// GitHub sources, Library update badge and Navigator tabs.
	var _splitView: some View {
		NavigationSplitView(columnVisibility: $_splitVisibility) {
			List(selection: Binding<SidebarItem?>(
				get: { _sidebarSelection.wrappedValue },
				set: { if let new = $0 { _sidebarSelection.wrappedValue = new } }
			)) {
				Section {
					ForEach(navigator.tabs, id: \.self) { tab in
						Label(tab.title, systemImage: tab.icon)
							.badge(tab == .library ? _libraryUpdateCount : 0)
							.tag(SidebarItem.tab(tab))
					}
				}

				Section(String.localized("Sources")) {
					Label(String.localized("All Repositories"), systemImage: "globe.desk")
						.tag(SidebarItem.allSources)

					ForEach(githubSources.repositories) { repository in
						_sidebarLabel(repository.name, iconURL: repository.avatarURL, fallback: Image("GitHubMark").renderingMode(.template))
							.tag(SidebarItem.github(repository.slug))
							.swipeActions {
								Button(String.localized("Delete"), systemImage: "trash", role: .destructive) {
									if _sidebarExtra == .github(repository.slug) { _sidebarExtra = nil }
									githubSources.remove(repository)
								}
							}
					}

					ForEach(_sources, id: \.objectID) { source in
						_sidebarLabel(source.name ?? .localized("Unknown"), iconURL: source.iconURL, fallback: Image(systemName: "app.dashed"))
							.tag(SidebarItem.source(source.objectID.uriRepresentation().absoluteString))
							.swipeActions {
								Button(String.localized("Delete"), systemImage: "trash", role: .destructive) {
									_sidebarExtra = nil
									Storage.shared.deleteSource(for: source)
								}
							}
					}

					Button {
						_isAddingSource = true
					} label: {
						Label(String.localized("Add Source"), systemImage: "plus")
					}
				}
			}
			.listStyle(.sidebar)
			.symbolVariant(.none)
			.navigationTitle("Quill")
			.navigationBarTitleDisplayMode(.large)
			.modifier(HideSidebarToggle())
			.navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
		} detail: {
			_splitDetail
				.environment(\.managedObjectContext, Storage.shared.context)
		}
		.navigationSplitViewStyle(.balanced)
		.onChange(of: _splitVisibility) { visibility in
			if visibility != .all { _splitVisibility = .all }
		}
		.task(id: Array(_sources)) {
			await sourcesViewModel.fetchSources(_sources)
		}
		.task {
			await githubSources.refreshDates()
		}
		.sheet(isPresented: $_isAddingSource) {
			SourcesAddView()
				.presentationDetents([.medium])
		}
	}

	/// The tabs stay alive once visited, so switching in the sidebar keeps each tab's
	/// navigation stack, scroll position and search, like the iPhone tab bar does.
	var _splitDetail: some View {
		let extra = _sidebarExtraView
		let showsTab = extra == nil
		return ZStack {
			ForEach(navigator.tabs.filter { _visitedTabs.contains($0) || $0 == selected }, id: \.self) { tab in
				let isShown = showsTab && tab == selected
				TabEnum.view(for: tab)
					.opacity(isShown ? 1 : 0)
					.allowsHitTesting(isShown)
					.accessibilityHidden(!isShown)
			}
			if let extra {
				extra
			}
		}
		.onAppear { _ = _visitedTabs.insert(selected) }
		.onChange(of: selected) { _ = _visitedTabs.insert($0) }
	}

	/// The view for a source picked under Sources, or `nil` when a main tab is picked
	/// (or the picked source was removed).
	var _sidebarExtraView: AnyView? {
		switch _sidebarExtra {
		case .none, .tab:
			return nil
		case .allSources:
			return AnyView(NavigationStack {
				SourceAppsView(object: Array(_sources), viewModel: sourcesViewModel)
			})
		case .github(let slug):
			guard let repository = githubSources.repositories.first(where: { $0.slug == slug }) else { return nil }
			return AnyView(NavigationStack {
				GitHubImportView(repository: repository)
			}
			.id(slug))
		case .source(let id):
			guard let source = _sources.first(where: { $0.objectID.uriRepresentation().absoluteString == id }) else { return nil }
			return AnyView(NavigationStack {
				SourceAppsView(object: [source], viewModel: sourcesViewModel)
			}
			.id(id))
		}
	}

	func _sidebarLabel(_ title: String, iconURL: URL?, fallback: Image) -> some View {
		Label {
			Text(title)
		} icon: {
			Group {
				if let iconURL {
					LazyImage(url: iconURL) { state in
						if let image = state.image {
							image.resizable().scaledToFill()
						} else {
							fallback.resizable().scaledToFit().padding(3).foregroundStyle(.secondary)
						}
					}
				} else {
					fallback.resizable().scaledToFit().padding(3).foregroundStyle(.secondary)
				}
			}
			.frame(width: 24, height: 24)
			.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
		}
	}
}

/// Removes the button that would hide the sidebar, so it stays open (iOS 17 and later).
private struct HideSidebarToggle: ViewModifier {
	func body(content: Content) -> some View {
		if #available(iOS 17, *) {
			content.toolbar(removing: .sidebarToggle)
		} else {
			content
		}
	}
}

private struct TabLabelApplier: UIViewControllerRepresentable {
	let tabs: [TabEnum]
	let showLabels: Bool
	func makeUIViewController(context: Context) -> Applier { Applier() }
	func updateUIViewController(_ controller: Applier, context: Context) {
		controller.tabs = tabs
		controller.showLabels = showLabels
		controller.apply()
		DispatchQueue.main.async { controller.apply() }
	}
	final class Applier: UIViewController {
		var tabs: [TabEnum] = []
		var showLabels = true
		private var appliedLabels: Bool?
		override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
		func apply() {
			guard let window = view.window, let bar = window.firstTabBar, let items = bar.items, items.count == tabs.count else { return }
			let showLabels = showLabels
			let update = {
				for (item, tab) in zip(items, self.tabs) {
					item.title = showLabels ? tab.title : nil
					item.accessibilityLabel = tab.title
					item.imageInsets = showLabels ? .zero : UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
				}
				bar.setNeedsLayout()
				bar.layoutIfNeeded()
			}
			if let appliedLabels, appliedLabels != showLabels, !UIAccessibility.isReduceMotionEnabled {
				UIView.transition(with: bar, duration: 0.32, options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState], animations: update)
			} else {
				update()
			}
			appliedLabels = showLabels
		}
	}
}

private extension UIView {
	var firstTabBar: UITabBar? {
		if let bar = self as? UITabBar { return bar }
		for sub in subviews { if let bar = sub.firstTabBar { return bar } }
		return nil
	}
}

enum TabTransition {
	@MainActor static func crossfade() {
		guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow),
			  let bar = window.firstTabBar else { return }
		let barFrame = bar.convert(bar.bounds, to: window)
		let barAtBottom = !bar.isHidden && barFrame.minY > window.bounds.midY
		let frame = barAtBottom ? CGRect(x: 0, y: 0, width: window.bounds.width, height: barFrame.minY) : window.bounds
		guard frame.height > 0, let snapshot = window.resizableSnapshotView(from: frame, afterScreenUpdates: false, withCapInsets: .zero) else { return }
		snapshot.isUserInteractionEnabled = false
		window.addSubview(snapshot)
		UIView.animate(withDuration: 0.28, delay: 0.04, options: [.curveEaseInOut, .allowUserInteraction]) {
			snapshot.alpha = 0
		} completion: { _ in
			snapshot.removeFromSuperview()
		}
	}
}
