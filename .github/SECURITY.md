# Security Policy

Quill handles signing certificates, provisioning profiles and Apple ID sign-ins, so we take security reports seriously.

## Supported versions

Security fixes go into the latest release. Quill updates itself from Settings → Updates, so please check you're on the [latest release](https://github.com/NuzProjects/Quill/releases/latest) before reporting.

## Reporting a vulnerability

**Please don't open a public issue for security problems.**

Report it privately from the repository's [Security tab](https://github.com/NuzProjects/Quill/security/advisories/new) ("Report a vulnerability"). Include:

- what the problem is and what someone could do with it,
- steps or a sample file to reproduce it,
- the Quill version and iOS version you tested on.

You should hear back within a few days. Once it's fixed and released, we'll credit you in the release notes unless you'd rather stay anonymous.

## In scope

- Quill's app code, its install server and helper, and the update flow.
- Handling of certificates, `.p12` passwords, Apple ID details and files imported into Quill (IPAs, `.deb` and `.dylib` tweaks).
- The [quill.madebynuz.dev](https://quill.madebynuz.dev) website and its functions in this repository.

Problems in Zsign or IDeviceKitten can be reported here too; we'll pass them on upstream.
