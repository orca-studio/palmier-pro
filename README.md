# Palmier Pro — Orca releases

Download builds from [GitHub Releases](https://github.com/orca-studio/palmier-pro/releases). Published releases include the DMG, release manifest, and SHA256 checksums.

This distribution uses bundle ID `ai.orca-studio.palmierpro` and the [Sparkle update feed](https://raw.githubusercontent.com/orca-studio/palmier-pro/release/appcast.xml).

Application development and builds live in [palmier-pro-dev](https://github.com/orca-studio/palmier-pro-dev), a private repository. Each release manifest records its source tag and full commit SHA. The `release` branch retains the upstream `main` baseline and commits release materials only; its inherited source is not the source used for distributed builds.

See [Releasing.md](docs/Releasing.md) for packaging, notarization, publication and recovery. Both manual Actions run in the development repository; Actions are disabled here.

Upstream: [palmier-io/palmier-pro](https://github.com/palmier-io/palmier-pro). The inherited source retains its [LICENSE](LICENSE).
