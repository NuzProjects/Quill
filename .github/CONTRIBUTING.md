# Contributing

Thanks for helping out! Quill is a sideloading app meant to be used on stock versions of iOS. To keep it working there, we only use stock features, so there are a few rules to keep Quill's integrity.

Any contributions should follow the [Code of Conduct](./CODE_OF_CONDUCT.md).

**New here?** Look for issues labeled [`good first issue`](https://github.com/NuzProjects/Quill/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) or [`help wanted`](https://github.com/NuzProjects/Quill/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22), or ask in [Discussions](https://github.com/NuzProjects/Quill/discussions).

## Rules

- **No usage of any exploits of any kind**.
- **No contributions related to retrieving any signing certificates owned by companies**.
- **Modifying any hardcoded links should be discussed before changing**.
- **If you're planning on making a large contribution, please [make an issue](https://github.com/NuzProjects/Quill/issues) beforehand**.
- **Your contributions should be licensed appropriately**.
  - Quill: GPLv3
  - AltSourceKit: MIT
  - NimbleKit: MIT
  - Zsign: MIT
- **Typo contributions are okay**, just make sure they are appropriate.
  - This includes localizations
- **Code cleaning contributions are okay**.

## Contributing to Quill

#### Compiling requirements

- Xcode 26 (CI builds with Xcode 26.3)
- Swift 5 language mode
- Deployment target: iOS 16.0

1. Clone the repository
    ```sh
    git clone https://github.com/NuzProjects/Quill --recursive
    ```
    - `Zsign` and `IDeviceKitten` are submodules; recursive is required.

2. Opening with Xcode
    ```sh
    cd Quill && open Quill.xcworkspace
    ```

3. Running the tests
    ```sh
    swift test
    ```
    - These cover the platform-independent code in `Quill/Core` and run on macOS or Linux. They also run automatically on every pull request.

#### How the project is laid out

| Folder | What's in it |
| --- | --- |
| `Quill/App` | App entry point, tab bar and iPad sidebar, notification routing. |
| `Quill/Features` | One folder per screen area: Certificates, Library, Onboarding, Settings, Signing, Sources, What's New. |
| `Quill/Services` | The work behind the screens: signing, installing, downloads, Apple ID, certificates, updates, widgets, Spotlight, Shortcuts, remote settings, storage and logging. |
| `Quill/Shared` | Reusable views, extensions and utilities. |
| `Quill/Core` | Small, platform-independent logic with unit tests in `Tests/QuillCoreTests`. |
| `Quill/Resources` | Assets, icons and `Localizable.xcstrings`. |
| `QuillWidgets` | Home Screen widgets and Live Activities. |
| `NimbleKit` | Shared SwiftUI views, extensions and JSON helpers (MIT). |
| `AltSourceKit` | Parses AltStore sources (MIT). |
| `Zsign` | The on-device signing engine (submodule, MIT). |
| `IDeviceKitten` | Talks to `installd` for installs over pairing (submodule). |
| `website`, `functions` | The [quill.madebynuz.dev](https://quill.madebynuz.dev) website and its install helper functions. |
| `source.json` | The AltStore source for Quill itself. |
| `remote-config.json` | Settings Quill downloads at launch, so some things can change without a new build. See [Remote settings](./REMOTE_CONFIG.md). |

For how signing and the different install methods work, read [How it works](./HOW_IT_WORKS.md).

#### Localizations
- For localizations, you will need Xcode 15 or higher to edit the `Quill/Resources/Localizable.xcstrings` file, or some alternative software that allows you to edit an `.xcstrings` file.
- We use a newer format for convenience, but at the cost of less accessibility when it comes to actually editing it.
  - **Disclaimer: do NOT edit by hand.**
- Some localizations were imported from V1; if they don't make sense, please feel free to change them.
- After localizing, please have another person review your localizations (unless the owners have asked you personally to help translate).
  - We want high-quality localizations and have them actually make sense when in the application.
  - They will not be merged unless the latter was done.

#### Making a pull request

- Make sure your contributions stay isolated in their own branch, and not `main`.
- Fill in the pull request template: what changed, how you tested it, and screenshots for anything visible.
- When contributing, don't be afraid of any reviewers requesting changes or judging how you wrote something; it's all to keep the project clean and tidy.

## Contributing to Zsign

When contributing to Zsign, head over to [khcrysalis/Zsign-Package](https://github.com/khcrysalis/Zsign-Package/tree/package) and make your contributions.

Any contributions to here will be immediately updated to here, to keep things consistent.

## Contributing to the wiki
- If you want to add a page or suggest edits, make an issue with your proposed changes.
