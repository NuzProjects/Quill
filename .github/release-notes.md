## Update 1.3.8 Beta 4

**New:**
* Tap the certificate expiry reminder to jump straight to the apps signed with it, so you know what to re-sign
* Quill now checks your sources for newer versions of your Library apps on its own, shows the count as a badge on the Library tab, and sends a notification when new updates show up
* When signing fails, the card now says why. Tap it to open the full log
* Sort your Library by date signed, name, size or expires soonest
* Pre-sign check: before you sign, Quill warns if the app needs a newer iOS, your certificate is expired, revoked or about to expire, your free Apple ID is close to its 10 App IDs per week, or there isn't enough free space
* Pick which App Library folder a signed app goes in (Social, Utilities, Games and more) under Customization
* Quill now checks for revoked certificates in the background and sends a notification if one gets revoked
* Library apps now show up in Spotlight. Tap a result to open the app in Quill
* Siri and Shortcuts: sign your latest import, check for app updates, or ask how many days your certificate has left
* Entitlements check: see which features the app asks for (iCloud, push notifications, App Groups and more) and which ones your certificate can't give it, before you sign
* Tweak checker: tweaks are checked before they're injected, with a warning if one is built for the wrong architecture, needs a newer iOS, needs jailbreak-only libraries or is made for a different app

**Changes:**
* Changing numbers now roll smoothly instead of jumping: progress percentages, signing time left, certificate days left, section counts, the screenshot counter, Home Screen widgets and Live Activities
* The update card now shows a rolling percentage while Quill updates itself
* Quill now taps a haptic when an install finishes or fails, and when an update download fails
* Website: the Download button now fetches Quill.ipa, and the FAQ credits Feather by Samara correctly
