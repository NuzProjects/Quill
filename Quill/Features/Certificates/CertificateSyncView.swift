import SwiftUI
import NimbleViews

/// Settings → Certificates → iCloud Sync.
struct CertificateSyncView: View {
	@AppStorage(CertificateSync.enabledKey) private var _isEnabled = false
	@State private var _isSyncing = false
	@State private var _message: String?
	@State private var _lastSync: Date? = CertificateSync.lastSync

	var body: some View {
		List {
			Section {
				Toggle(.localized("Sync Certificates with iCloud"), systemImage: "icloud", isOn: $_isEnabled)
			} footer: {
				Text(.localized("Your certificates, profiles and passwords are saved in iCloud Keychain, end-to-end encrypted, and added to Quill on your other devices. Certificates made with an Apple ID stay on this device."))
			}

			if _isEnabled {
				Section {
					Button {
						Task { await _sync() }
					} label: {
						HStack {
							Label(.localized("Sync Now"), systemImage: "arrow.triangle.2.circlepath")
							Spacer()
							if _isSyncing { ProgressView() }
						}
					}
					.disabled(_isSyncing)
					if let last = _lastSync {
						LabeledContent(.localized("Last Synced"), value: last.formatted(date: .abbreviated, time: .shortened))
					}
				} footer: {
					if let message = _message { Text(message) }
				}

				Section {
					Button(.localized("Remove Certificates from iCloud"), role: .destructive) {
						UIAlertController.showAlert(
							title: .localized("Remove from iCloud?"),
							message: .localized("Certificates stay in Quill on every device. They just stop syncing."),
							actions: [
								UIAlertAction(title: .localized("Remove"), style: .destructive) { _ in
									CertificateSync.removeAllFromiCloud()
									_isEnabled = false
									_lastSync = nil
								},
								UIAlertAction(title: .localized("Cancel"), style: .cancel)
							]
						)
					}
				}
			}

			NBSection(.localized("Good to Know")) {
				Label(.localized("iCloud Keychain needs to be on for your Apple Account on each device."), systemImage: "key.icloud")
				Label(.localized("Syncing only works between copies of Quill signed by the same team, because iOS keeps each team's keychain separate."), systemImage: "person.2")
				Label(.localized("New certificates can take a few minutes to show up on your other devices."), systemImage: "clock")
			}
			.font(.footnote)
		}
		.navigationTitle(.localized("iCloud Sync"))
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: _isEnabled) { enabled in
			if enabled { Task { await _sync() } }
		}
	}

	@MainActor
	private func _sync() async {
		_isSyncing = true
		let outcome = await CertificateSync.sync()
		_isSyncing = false
		_lastSync = CertificateSync.lastSync
		switch outcome {
		case let .synced(uploaded, added):
			if added > 0 {
				_message = added == 1 ? .localized("Added 1 certificate from your other devices.") : String(format: .localized("Added %d certificates from your other devices."), added)
			} else if uploaded > 0 {
				_message = uploaded == 1 ? .localized("Saved 1 certificate to iCloud.") : String(format: .localized("Saved %d certificates to iCloud."), uploaded)
			} else {
				_message = .localized("Everything is up to date.")
			}
		case let .unavailable(reason):
			_message = reason
			UINotificationFeedbackGenerator().notificationOccurred(.error)
		}
	}
}
