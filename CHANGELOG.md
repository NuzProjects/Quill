# Changelog

All notable changes to Quill. Each version links to its release, where you can download it.

Versions 1.3.5 and earlier were released under the Feather name.

## Unreleased

### New
- Inspect App: see what's inside an app before you sign it, including its permissions, frameworks, tweaks, extensions and size
- Share IPA: send a signed or unsigned app to someone from the Library's menu
- Sign with Quill: open an .ipa from Files, Safari or any app's share sheet and Quill imports it. Turn on Sign Right After Opening in Settings to go straight to signing
- Control Center controls (iOS 18): Import IPA, Download Copied Link, Sign Latest IPA, and a certificate control that shows how many days you have left. You can also put these on the Lock Screen or the Action button
- Check Sources: find out which of your sources are broken, slow, or haven't been updated in a while, and remove the broken ones with a swipe
- Make a Source: turn apps in your Library into a source file you can host anywhere and add to Quill, AltStore or SideStore
- iCloud Sync for certificates: your certificates are saved in iCloud Keychain, end-to-end encrypted, and show up in Quill on your other devices. Turn it on in Settings > iCloud Sync
- Custom app icons: paste a copied image, or download one from a link
- Remember Icon and Name: Quill uses the same custom icon and name next time you sign that app
- Quill now opens quill:// links. Older feather:// links still work

## [1.4.0 Beta 2](https://github.com/NuzProjects/Quill/releases/tag/v1.4.0-beta2-build179) (pre-release) - 2026-11-24

### New
- iPad: a sidebar that stays open, with Sources, Library and Settings, plus every GitHub repo and source you've added. Swipe to delete a source, or add one right from the sidebar
- iPad: Library and Sources now use the same clean rows as iPhone
- Library: switch between List and Grid from the sort menu
- Quill warns before signing or installing if this device isn't in your certificate's provisioning profile, and can check this device for you
- Copied an .ipa link? When you open Quill, a Paste button offers to import it. Turn this off under Settings > Misc

### Changes
- Days left on signed apps and certificates now roll up like an odometer
- What's New in Settings > Updates now looks like the update pop-up, with a heading and icon for each change
- The sidebar's Quill title is now left-aligned
- A cleaner icon for the Library sort menu

### Fixes
- Copying any web link no longer makes iOS ask to allow pasting when you open Quill
- iPad: switching in the sidebar keeps your place in each tab instead of starting over
- iPad: screens opened from Library and Sources use the full iPad layout again

## [1.3.9](https://github.com/NuzProjects/Quill/releases/tag/v1.3.9-build176) - 2026-11-23

### New
- Tap the certificate expiry reminder to jump straight to the apps signed with it, so you know what to re-sign
- Quill now checks your sources for newer versions of your Library apps on its own, shows the count as a badge on the Library tab, and sends a notification when new updates show up
- When signing fails, the card now says why. Tap it to open the full log
- Sort your Library by date signed, name, size or expires soonest
- Pre-sign check: before you sign, Quill warns if the app needs a newer iOS, your certificate is expired, revoked or about to expire, your free Apple ID is close to its 10 App IDs per week, or there isn't enough free space
- Pick which App Library folder a signed app goes in (Social, Utilities, Games and more) under Customization
- Quill now checks for revoked certificates in the background and sends a notification if one gets revoked
- Library apps now show up in Spotlight. Tap a result to open the app in Quill
- Siri and Shortcuts: sign your latest import, check for app updates, or ask how many days your certificate has left

### Changes
- Changing numbers now roll smoothly instead of jumping: progress percentages, signing time left, certificate days left, section counts, the screenshot counter, Home Screen widgets and Live Activities
- The update card now shows a rolling percentage while Quill updates itself
- Quill now taps a haptic when an install finishes or fails, and when an update download fails
- Website: the Download button now fetches Quill.ipa, and the FAQ credits Feather by Samara correctly

## [1.3.7](https://github.com/NuzProjects/Quill/releases/tag/v1.3.7-build166) - 2026-11-18

### Changes
- New softer Cornflower blue look across the app tint, app icon, alternate icons, widgets, Live Activities and artwork
- If you were using the old deep blue default, you move to Cornflower automatically. The old color is still in Settings → Appearance as "Deep Blue"

## [1.3.6](https://github.com/NuzProjects/Quill/releases/tag/v1.3.6-build163) - 2026-11-18

### New Features
- Feather is now Quill. The app name, Live Activity titles, signing progress and alternate icon names use the new name. Your certificates, apps and settings stay where they are
- Get a Certificate can sign in with your Apple ID, as well as use a trusted certificate provider, from Settings → Certificates
- New deep blue look across the app icon, alternate icons, widgets and artwork

## [1.3.5](https://github.com/NuzProjects/Quill/releases/tag/v1.3.5-build153) - 2026-11-14

### New Features
- Sign in with a free Apple ID: no certificate needed. Go to Settings → Certificates → + → Sign In with Apple ID, and Feather creates a free development certificate and signs each app with its own profile from Apple
- Find My UDID fills in your device's UDID for the Apple ID sign-in, and two-factor codes are asked for when Apple needs them. Your Apple ID details stay in this device's Keychain
- Free Apple ID limits apply: signed apps last 7 days, up to 3 can be installed at once, and up to 10 new apps can be added per week. Apps get a bundle ID ending in your team ID
- GitHub repositories in Sources show their icon, name and latest release, just like other sources
- Sources open instantly, even offline, and refresh in the background
- Better on iPad: Settings, app pages and lists keep to a comfortable width
- Lock Screen certificate widgets: a days-left gauge, a larger card with the expiry date, and a one-line version
- Feather warns before installing an app signed with an expired or revoked certificate, and offers to re-sign it
- Signing keeps going when you leave Feather, and you get a notification when it finishes
- A refreshed update sheet that matches the rest of Feather

### Fixes
- GitHub and download errors explain what went wrong in plain words
- Leftover files from signing and installing are cleared automatically
- Subtext no longer flickers between shades when screens open

### Security
- A malicious IPA or .deb tweak can no longer write files outside its own unpack folder
- Links that add a source now ask you first instead of adding it silently
- Removed a leftover exception that allowed one website to load over plain HTTP

## [1.3.4](https://github.com/NuzProjects/Quill/releases/tag/v1.3.4-build124) - 2026-11-07

### New Features
- Semi Local installs and updates go straight to iOS's install prompt, with no Safari page first
- The signing card shows about how long is left, based on how fast your device signed before
- New signing options: Remove Apple Watch App and Remove Unused Languages, for smaller apps
- Widgets, Live Activities and progress messages are translated into 13 languages

### Bug Fixes
- Updates always bring up the install prompt, and Feather retries when GitHub has a brief hiccup
- Certificates show their team name and team ID instead of a long device ID
- The Updates page only shows release notes when there's a newer version
- The install sheet is back to Feather's original look, and progress panels use the same glass as the tab bar
- Semi Local installs over cellular work on carriers that give phones unusual network addresses
- Widgets keep updating if Feather started before the phone was first unlocked
- Install alerts no longer appear after you close the install sheet

## [1.3.3](https://github.com/NuzProjects/Quill/releases/tag/v1.3.3-build112) - 2026-11-07

### New Features
- Fully Local works again: it uses Feather's own certificate for local.feather.madebynuz.dev, which renews automatically and is replaced if it's ever revoked
- Semi Local uses Feather's own install helper, so app names and bundle IDs aren't sent to a third-party service

### Bug Fixes
- Feather asks before a link adds a certificate
- Certificates are only exported to other apps, never to websites, and the prompt shows which app is asking
- When it doesn't need your network, Feather's install server only listens on your device
- If Fully Local can't start an install, Feather offers to switch to Semi Local instead of waiting on Ready
- The install sheet has a bigger app icon and no extra box inside it

## [1.3.2](https://github.com/NuzProjects/Quill/releases/tag/v1.3.2-build107) - 2026-11-07

### New Features
- Home Screen widgets: a Certificate widget with days left and status, and a Library widget with your recently signed apps, each in small and medium, using your accent color
- Live Activities: signing, downloads and updates show their progress on the Lock Screen and in the Dynamic Island
- Feather warns you before signing an app that's still App Store encrypted or needs a newer iOS than your device has
- A small Liquid Glass pill above the tab bar shows when you're offline
- New screens, alerts and errors are translated into 13 languages
- After a crash, Report on GitHub opens a bug report with the details already filled in

### Bug Fixes
- Tidier Settings: App Icon and Navigator are inside Appearance, which is now under Features, and compression options are in Signing Options
- Widgets, share sheets and other extensions inside apps you sign get a signing profile, so they can open
- Feather explains when your certificate can't run widgets and Live Activities, instead of showing an empty Live Activity
- No divider line at the top of pages; content blurs under the bar when you scroll
- Get a Certificate uses your accent color
- Contributors in About show a loading placeholder while their GitHub picture loads

Widgets and Live Activities need a certificate that covers all app IDs.

## [1.3.0](https://github.com/NuzProjects/Quill/releases/tag/v1.3.0-build94) - 2026-11-06

### New Features
- Get a Certificate when you don't have one, with Apple and unofficial providers (with their logos) and a shortcut to import
- Pages blur content as it scrolls under the top bar, like the Settings app
- Version history and What's New show Markdown: bold, links and bullet points
- Receive Beta Updates asks before turning on, and the version and notes animate when you switch

### Bug Fixes
- Download and Install opens Get a Certificate when no certificate is selected, instead of doing nothing
- Resetting no longer crashes the first time Feather reopens, and most resets now happen without restarting
- Reset confirmations no longer show stray numbers
- Importing a certificate from Get a Certificate closes the sheet when you're done
- KravaSign uses its official website and logo
- What's New lists only this update's changes

## [1.2.5](https://github.com/NuzProjects/Quill/releases/tag/v1.2.5-build88) - 2026-11-06

### New Features
- Receive Beta Updates switch in Settings → Updates
- Feather can show announcements, and its certificate providers, featured sources and install server can be updated without a new version

### Bug Fixes
- Get a Certificate in Settings now looks like the other rows and only shows when you have no certificates
- If the selected certificate was deleted, Feather selects your newest one instead of showing no certificate

## [1.2.4](https://github.com/NuzProjects/Quill/releases/tag/v1.2.4-build86) - 2026-11-06

### New Features
- Get a Certificate in Settings when you don't have one, with official and third-party providers and a shortcut to import
- Tapping an app in a source opens its page on iOS 16

### Bug Fixes
- Fixed a crash when installing or exporting apps that have no version or name
- Fixed a crash when signing an app with a missing or broken Info.plist
- Fixed crashes when reading some .deb tweaks, and .deb files from more tools are read correctly
- Fixed a possible crash when the install server's port was busy, and installs now stop with a clear error if the server can't start
- Install progress no longer checks 1,000 times a second, saving battery during installs
- Fixed crashes from alerts or the share sheet appearing while Feather is in the background
- Failed downloads now show why, and server error pages are no longer imported as apps
- Downloads keep going in the background on iOS 26 again
- Importing a certificate shows an error instead of closing silently, and no longer writes to the database off the main thread
- Featured sources no longer go missing, Import explains an empty clipboard, and invalid source URLs show a message
- Sources that can't load show a message instead of spinning forever
- Retrying a sign keeps your .dylib tweaks
- Imports work right after Reset without relaunching
- Lists update immediately after Reset
- Exported certificates with special characters in the password reach other apps correctly
- Changing a bundle ID also updates watch extension identifiers
- Clearer errors for damaged IPAs and unreadable provisioning profiles

## [1.2.2](https://github.com/NuzProjects/Quill/releases/tag/v1.2.2-build85) - 2026-11-06

### Bug Fixes
- Edit and Done in Library fade smoothly, and the toolbar buttons no longer jump

## [1.2.1](https://github.com/NuzProjects/Quill/releases/tag/v1.2.1-build82) - 2026-11-05

### Bug Fixes
- Edit in Library no longer disappears or stops working after leaving the page
- Leaving Library or Navigator ends editing so the buttons stay usable

## [1.2.0](https://github.com/NuzProjects/Quill/releases/tag/v1.2.0-build78) - 2026-11-05

### New Features
- Certificate Overview: tap the certificate in Settings to see days left, capabilities, devices and signed apps
- Check Revocation shows a loading indicator and the result
- Developer Logs in Settings → Misc with crash reports, export and Save to Files
- Tap a featured source in Add Source to preview its apps before adding it
- The update popup opens Settings → Updates, with one progress bar for signing and installing
- GitHub section in Settings: Star on GitHub, Report an Issue and About
- Cleaner Navigator icon, and the tab bar animates when showing or hiding labels
- AltStore source for this fork

### Bug Fixes
- Descriptions and release notes expand without flashing, and More shows whenever text is cut off
- Adding a source from its preview no longer jumps back to Add Source
- The crash report prompt shows only once
- Check Revocation keeps its color while checking
- GitHub links and the featured source point to this fork, and "open an issue" is translated again
- Larger section titles in What's New, listing only this version's changes
- Signing and download panel icons no longer have a light outline

## [1.1.0](https://github.com/NuzProjects/Quill/releases/tag/v1.1.0) - 2026-11-05

### New Features
- Update Feather from Settings → Updates
- Backup & Transfer
- Revoked certificate alerts
- Certificate expiry notifications
- Search apps across sources
- Library swipe actions
- Cancel signing or downloads
- Welcome guide and What's New

### Bug Fixes
- Clearer signing errors
- Semi Local by default
- Apps with extensions sign correctly

## [1.0.0](https://github.com/NuzProjects/Quill/releases/tag/v1.0.0-build28) - 2026-11-05

### New Features
- Update Feather from Settings
- New featured sources

### Bug Fixes
- Reset button no longer turns into three dots
- Removed broken featured sources
