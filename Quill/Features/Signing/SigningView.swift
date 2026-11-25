import SwiftUI
import PhotosUI
import NimbleViews

struct SigningView: View {
	@Environment(\.dismiss) var dismiss
	@StateObject private var _optionsManager = OptionsManager.shared

	@State private var _temporaryOptions: Options = OptionsManager.shared.options
	@State private var _temporaryCertificate: Int
	@State private var _isAltPickerPresenting = false
	@State private var _isFilePickerPresenting = false
	@State private var _isImagePickerPresenting = false
	@State private var _isSigning = false
	@State private var _checkIssues: [AppCompatibility.Issue]?
	@State private var _appMegabytes: Double?
	@State private var _entitlements: EntitlementsReport?
	@State private var _tweakFindings: [URL: [TweakInspector.Finding]] = [:]

	@State private var _selectedPhoto: PhotosPickerItem? = nil
	@State private var _isIconLinkPresenting = false
	@State private var _iconLink = ""
	@State private var _isDownloadingIcon = false
	@State private var _rememberLook = false
	@State var appIcon: UIImage?

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var certificates: FetchedResults<CertificatePair>

	private func _selectedCert() -> CertificatePair? {
		guard certificates.indices.contains(_temporaryCertificate) else { return nil }
		return certificates[_temporaryCertificate]
	}

	var app: AppInfoPresentable
	var replacementUUID: String?
	var preferredIdentifier: String?

	init(app: AppInfoPresentable, replacementUUID: String? = nil, preferredIdentifier: String? = nil) {
		self.replacementUUID = replacementUUID
		self.preferredIdentifier = preferredIdentifier
		self.app = app
		let storedCert = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		__temporaryCertificate = State(initialValue: storedCert)
	}

	var body: some View {
		NBNavigationView("", displayMode: .inline) {
			Form {
				_customizationOptions(for: app)
				_cert()
				_preSignCheck()
				_customizationProperties(for: app)

				Rectangle()
					.foregroundStyle(.clear)
					.frame(height: 30)
					.listRowBackground(EmptyView())
			}
			.disabled(_isSigning)
			.overlay {
				VStack(spacing: 0) {
					Spacer()
					NBVariableBlurView()
						.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 60 : 80)
						.rotationEffect(.degrees(180))
						.overlay {
							Button {
								_start()
							} label: {
								NBSheetButton(title: .localized("Start Signing"), style: .prominent)
									.padding()
							}
							.buttonStyle(.plain)
							.disabled(_isSigning)
							.offset(y: UIDevice.current.userInterfaceIdiom == .pad ? -20 : -40)
						}
				}
				.ignoresSafeArea(edges: .bottom)
			}

			.toolbar {
				NBToolbarButton(role: .dismiss)
				ToolbarItem(placement: .principal) {
					Image("Glyph")
						.resizable()
						.scaledToFit()
						.frame(height: 38)
				}
				NBToolbarButton(
					.localized("Reset"),
					style: .text,
					placement: .topBarTrailing
				) {
					_temporaryOptions = OptionsManager.shared.options
					appIcon = nil
				_applyReplacement()
				}
			}
			.sheet(isPresented: $_isAltPickerPresenting) { SigningAlternativeIconView(app: app, appIcon: $appIcon, isModifing: .constant(true)) }
			.sheet(isPresented: $_isFilePickerPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes:  [.image],
					onDocumentsPicked: { urls in
						guard let selectedFileURL = urls.first else { return }
						self.appIcon = UIImage.fromFile(selectedFileURL)?.resizeToSquare()
					}
				)
				.ignoresSafeArea()
			}
			.photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
			.onChange(of: _selectedPhoto) { newValue in
				guard let newValue else { return }

				Task {
					if let data = try? await newValue.loadTransferable(type: Data.self),
					   let image = UIImage(data: data)?.resizeToSquare() {
						appIcon = image
					}
				}
			}

			.animation(.smooth, value: _isSigning)
		}
		.task(id: _checkKey) { await _runCheck() }
		.onAppear {
			if
				_optionsManager.options.ppqProtection,
				let identifier = app.identifier,
				let cert = _selectedCert(),
				cert.ppQCheck
			{
				_temporaryOptions.appIdentifier = "\(identifier).\(_optionsManager.options.ppqString)"
			}

			if
				let currentBundleId = app.identifier,
				let newBundleId = _temporaryOptions.identifiers[currentBundleId]
			{
				_temporaryOptions.appIdentifier = newBundleId
			}

			if
				let currentName = app.name,
				let newName = _temporaryOptions.displayNames[currentName]
			{
				_temporaryOptions.appName = newName
			}

			if CustomAppLook.hasSaved(for: app.identifier) {
				_rememberLook = true
				if appIcon == nil { appIcon = CustomAppLook.icon(for: app.identifier) }
				if _temporaryOptions.appName == nil, let saved = CustomAppLook.name(for: app.identifier) {
					_temporaryOptions.appName = saved
				}
			}
			_applyReplacement()
		}
	}
}

extension SigningView {
	@ViewBuilder
	private func _customizationOptions(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Customization")) {
			Menu {
				Button(.localized("Select Alternative Icon"), systemImage: "app.dashed") { _isAltPickerPresenting = true }
				Button(.localized("Choose from Files"), systemImage: "folder") { _isFilePickerPresenting = true }
				Button(.localized("Choose from Photos"), systemImage: "photo") { _isImagePickerPresenting = true }
				Button(.localized("Paste Image"), systemImage: "doc.on.clipboard") { _pasteIcon() }
				Button(.localized("From a Link"), systemImage: "link") {
					_iconLink = ""
					_isIconLinkPresenting = true
				}
				if appIcon != nil {
					Button(.localized("Use Original Icon"), systemImage: "arrow.uturn.backward", role: .destructive) { appIcon = nil }
				}
			} label: {
				ZStack {
					if let icon = appIcon {
						Image(uiImage: icon)
							.appIconStyle()
					} else {
						FRAppIconView(app: app, size: 56)
					}
					if _isDownloadingIcon { ProgressView() }
				}
			}
			.alert(.localized("Icon from a Link"), isPresented: $_isIconLinkPresenting) {
				TextField("https://", text: $_iconLink)
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
				Button(.localized("Cancel"), role: .cancel) {}
				Button(.localized("Download")) { _downloadIcon() }
			} message: {
				Text(.localized("Paste a link to a PNG or JPEG image."))
			}

			_infoCell(.localized("Name"), desc: _temporaryOptions.appName ?? app.name) {
				SigningPropertiesView(
					title: .localized("Name"),
					initialValue: _temporaryOptions.appName ?? (app.name ?? ""),
					bindingValue: $_temporaryOptions.appName
				)
			}
			_infoCell(.localized("Identifier"), desc: _temporaryOptions.appIdentifier ?? app.identifier) {
				SigningPropertiesView(
					title: .localized("Identifier"),
					initialValue: _temporaryOptions.appIdentifier ?? (app.identifier ?? ""),
					bindingValue: $_temporaryOptions.appIdentifier
				)
			}
			_infoCell(.localized("Version"), desc: _temporaryOptions.appVersion ?? app.version) {
				SigningPropertiesView(
					title: .localized("Version"),
					initialValue: _temporaryOptions.appVersion ?? (app.version ?? ""),
					bindingValue: $_temporaryOptions.appVersion
				)
			}
			Picker(selection: $_temporaryOptions.appCategory) {
				Text(.localized("Automatic")).tag(Options.AppCategory?.none)
				ForEach(Options.AppCategory.allCases) { category in
					Text(category.localizedDescription).tag(Options.AppCategory?.some(category))
				}
			} label: {
				Text(.localized("App Library Folder"))
			}
			if app.identifier != nil {
				Toggle(isOn: $_rememberLook) {
					VStack(alignment: .leading, spacing: 2) {
						Text(.localized("Remember Icon and Name"))
						Text(.localized("Use them again next time you sign this app."))
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
		}
	}

	private func _pasteIcon() {
		guard let image = UIPasteboard.general.image?.resizeToSquare() else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Image Copied"),
				message: .localized("Copy an image first, then try again.")
			)
			return
		}
		appIcon = image
	}

	private func _downloadIcon() {
		let link = _iconLink
		_isDownloadingIcon = true
		Task { @MainActor in
			defer { _isDownloadingIcon = false }
			do {
				appIcon = try await CustomAppLook.downloadIcon(from: link)
			} catch {
				UIAlertController.showAlertWithOk(
					title: .localized("Couldn't Get That Image"),
					message: .localized("Make sure the link goes straight to a PNG or JPEG image.")
				)
			}
		}
	}

	/// Saves or clears the remembered icon and name, depending on the toggle.
	private func _storeLook() {
		guard let identifier = app.identifier else { return }
		if _rememberLook {
			let name = _temporaryOptions.appName.flatMap { $0 == app.name ? nil : $0 }
			CustomAppLook.save(icon: appIcon, name: name, for: identifier)
		} else if CustomAppLook.hasSaved(for: identifier) {
			CustomAppLook.forget(identifier)
		}
	}

	@ViewBuilder
	private func _cert() -> some View {
		NBSection(.localized("Signing")) {
			if let cert = _selectedCert() {
				NavigationLink {
					CertificatesView(selectedCert: $_temporaryCertificate)
				} label: {
					CertificatesCellView(
						cert: cert
					)
				}
			} else {
				Text(.localized("No Certificate"))
					.font(.footnote)
					.foregroundColor(.disabled())
			}
		}
	}

	@ViewBuilder
	private func _preSignCheck() -> some View {
		Section {
			if let issues = _checkIssues {
				if issues.isEmpty {
					Label(String.localized("Ready to sign"), systemImage: "checkmark.circle.fill")
						.foregroundStyle(.green)
				} else {
					ForEach(issues) { issue in
						Label {
							Text(issue.message).font(.footnote)
						} icon: {
							Image(systemName: issue.icon)
								.foregroundStyle(issue.isBlocking ? Color.red : Color.orange)
						}
					}
				}
			} else {
				HStack(spacing: 8) {
					ProgressView()
					Text(.localized("Checking…")).font(.footnote).foregroundStyle(.secondary)
				}
			}

			if let report = _entitlements {
				NavigationLink {
					EntitlementsReportView(report: report)
				} label: {
					LabeledContent {
						Text(_entitlementSummary(report))
					} label: {
						Label(String.localized("Entitlements"), systemImage: "key")
					}
				}
			}
		} header: {
			Text(.localized("Pre-sign Check"))
		}
	}

	@ViewBuilder
	private func _customizationProperties(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Advanced")) {
			DisclosureGroup(.localized("Modify")) {
				NavigationLink(.localized("Existing Dylibs")) {
					SigningDylibView(
						app: app,
						options: $_temporaryOptions.optional()
					)
				}

				NavigationLink(.localized("Frameworks & PlugIns")) {
					SigningFrameworksView(
						app: app,
						options: $_temporaryOptions.optional()
					)
				}

				NavigationLink(.localized("Entitlements") + " (BETA)") {
					SigningEntitlementsView(
						bindingValue: $_temporaryOptions.appEntitlementsFile
					)
				}

				NavigationLink(.localized("Tweaks")) {
					SigningTweaksView(
						options: $_temporaryOptions,
						app: app,
						findings: $_tweakFindings
					)
				}
			}

			NavigationLink(.localized("Properties")) {
				Form { SigningOptionsView(
					options: $_temporaryOptions,
					temporaryOptions: _optionsManager.options
				)}
				.navigationTitle(.localized("Properties"))
			}
		}
	}

	@ViewBuilder
	private func _infoCell<V: View>(_ title: String, desc: String?, @ViewBuilder destination: () -> V) -> some View {
		NavigationLink {
			destination()
		} label: {
			LabeledContent(title) {
				Text(desc ?? .localized("Unknown"))
			}
		}
	}
}

extension SigningView {
	private func _applyReplacement() {
		guard let preferredIdentifier else { return }
		_temporaryOptions.appIdentifier = preferredIdentifier
		_temporaryOptions.appVersion = nil
		if let old = GitHubReleases.shared.allApps().first(where: { $0.uuid == replacementUUID }), let cert = Storage.shared.getCertificate(from: old), let index = certificates.firstIndex(where: { $0.objectID == cert.objectID }) { _temporaryCertificate = index }
	}
	private var _checkKey: String {
		[
			"\(_temporaryCertificate)",
			_temporaryOptions.appIdentifier ?? "",
			"\(_temporaryOptions.signingOption)",
			_temporaryOptions.appEntitlementsFile?.path ?? "",
			_temporaryOptions.injectionFiles.map(\.path).joined(separator: ",")
		].joined(separator: "|")
	}

	private func _entitlementSummary(_ report: EntitlementsReport) -> String {
		if !report.notAllowed.isEmpty || !report.dropped.isEmpty {
			return String(format: .localized("%ld won't work"), report.notAllowed.count + report.dropped.count)
		}
		return report.kept.isEmpty ? String.localized("None") : String(format: .localized("%ld kept"), report.kept.count)
	}

	private var _effectiveIdentifier: String? {
		_temporaryOptions.appIdentifier ?? app.identifier
	}

	private func _currentIssues() -> [AppCompatibility.Issue] {
		AppCompatibility.issues(
			for: app,
			certificate: _temporaryOptions.signingOption == .default ? _selectedCert() : nil,
			identifier: _effectiveIdentifier,
			appMegabytes: _appMegabytes
		)
		+ AppCompatibility.issues(for: _entitlements)
		+ AppCompatibility.issues(for: _tweakFindings, order: _temporaryOptions.injectionFiles)
	}

	@MainActor
	private func _runCheck() async {
		if _appMegabytes == nil {
			let directory = Storage.shared.getAppDirectory(for: app)
			_appMegabytes = await Task.detached(priority: .userInitiated) {
				directory.map(SigningProgress.megabytes) ?? 0
			}.value
		}

		let input = EntitlementsReport.Input.make(
			app: app,
			certificate: _temporaryOptions.signingOption == .default ? _selectedCert() : nil,
			customFile: _temporaryOptions.appEntitlementsFile
		)
		let report = await Task.detached(priority: .userInitiated) {
			EntitlementsReport.make(input)
		}.value

		let files = _temporaryOptions.injectionFiles
		var findings: [URL: [TweakInspector.Finding]] = [:]
		if !files.isEmpty {
			findings = await TweakInspector.inspect(files, context: .make(app: app, identifier: _effectiveIdentifier))
		}

		guard !Task.isCancelled else { return }
		_entitlements = report
		_tweakFindings = findings
		let issues = _currentIssues()
		withAnimation(.snappy) { _checkIssues = issues }
	}

	private func _start() {
		guard
			_selectedCert() != nil || _temporaryOptions.signingOption != .default
		else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate"),
				isCancel: true
			)
			return
		}

		let issues = _currentIssues()
		if let blocking = issues.first(where: \.isBlocking) {
			UINotificationFeedbackGenerator().notificationOccurred(.error)
			UIAlertController.showAlertWithOk(
				title: .localized("Can't Sign Yet"),
				message: blocking.message
			)
			return
		}
		let warnings = issues.filter { !$0.isAdvisory }
		guard warnings.isEmpty else {
			UIAlertController.showAlert(
				title: .localized("This App May Not Work"),
				message: warnings.map(\.message).joined(separator: "\n\n"),
				actions: [
					UIAlertAction(title: .localized("Sign Anyway"), style: .destructive) { _ in _beginSigning() },
					UIAlertAction(title: .localized("Cancel"), style: .cancel)
				]
			)
			return
		}
		_beginSigning()
	}

	private func _beginSigning() {
		let generator = UIImpactFeedbackGenerator(style: .light)
		generator.impactOccurred()
		_isSigning = true
		_storeLook()

		let options = _temporaryOptions
		FR.signPackageFile(
			app,
			using: options,
			icon: appIcon,
			certificate: _selectedCert(),
			onSigned: { signed in
				if options.post_installAppAfterSigned {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NotificationCenter.default.post(name: Notification.Name("Quill.installApp"), object: signed) }
				}
				if let replacementUUID, let old = GitHubReleases.shared.allApps().first(where: { $0.uuid == replacementUUID }), old.uuid != signed.uuid {
					Storage.shared.deleteApp(for: old)
				}
			}
		) { error in
			if error is CancellationError { return }
			if let error {
				let ok = UIAlertAction(title: .localized("Dismiss"), style: .cancel) { _ in
					dismiss()
				}

				UIAlertController.showAlert(
					title: "Error",
					message: error.localizedDescription,
					actions: [ok]
				)
			} else {
				if
					options.post_deleteAppAfterSigned,
					!app.isSigned
				{
					Storage.shared.deleteApp(for: app)
				}

				dismiss()
			}
		}
		dismiss()
	}
}
