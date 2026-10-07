# Development and releases

| Remote / branch | Repository | Responsibility |
| --- | --- | --- |
| `upstream/main` | `palmier-io/palmier-pro` | Original source; fetch only by convention |
| `fork/main` | `orca-studio/palmier-pro` | Mirror upstream source |
| `dev/dev` | `orca-studio/palmier-pro-dev` | Development, tests, source tags, and builds |
| `fork/release` | `orca-studio/palmier-pro` | Branch from `fork/main`; subsequent commits change appcast and release notes only |

Local `dev` tracks `dev/dev`; local `main` tracks `fork/main`. Default development pushes target `dev`. Remote names and push defaults are local Git configuration, so configure them again in a fresh checkout.

Create `release` from `fork/main` with ordinary branch history, retaining all inherited source files. After creation, commit only release materials. Do not update source code on this branch or merge development changes into it. Application builds always use source tags in the development repository, not the inherited source on `release`.

## Upstream updates

Fetch `upstream`, update `fork/main` from the selected upstream commit, and explicitly push `main` to `fork`. Integrate upstream changes into `dev/dev` separately and test them. Never merge `dev` into `fork/main` or `fork/release`.

## Source and build

1. Select a commit in the development repository. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/PalmierPro/Resources/Info.plist`; the build number must increase for each published update.
2. Run the required builds and tests, including `swift build --traits BundledSpeech`, and complete manual verification for the release.
3. Commit the version and source changes, create an annotated version tag such as `v0.12.0`, and explicitly push the branch and that tag to `dev`.
4. Build from a clean checkout of that source tag using `scripts/bundle.sh release --dist`. Release builds include all optional traits. Configure the intended Developer ID identity, provisioning profile, entitlements, notary profile, and production services before building.
5. Keep the final `.build/PalmierPro.dmg`, its Sparkle EdDSA signature and byte length, and the source tag and full commit SHA. The signing private key must match the application's `SUPublicEDKey`; never commit private keys or credentials. Do not change the DMG after generating its Sparkle signature.

Build in the development repository, not in the release-material checkout. `SUFeedURL` points to:

```text
https://raw.githubusercontent.com/orca-studio/palmier-pro/release/appcast.xml
```

## Release materials and distribution

1. Fetch `fork/release` into a separate worktree. Maintain release notes there, recording the development repository, source tag, full source commit SHA, application version, and build number.
2. Commit the release notes and create the same version tag in the fork repository. This tag identifies release materials, not the application source. Push that tag explicitly to `fork`; do not push all tags across repositories.
3. Create a draft GitHub Release in `orca-studio/palmier-pro` for the material tag and upload the final DMG. Include the source provenance in its release notes.
4. Publish the GitHub Release. Verify the version-specific asset URL is accessible without authentication and downloads the exact signed DMG.
5. Add an item to `fork/release`'s `appcast.xml` with the build number as `sparkle:version`, the application version as `sparkle:shortVersionString`, macOS minimum version, publication date, DMG URL, byte length, and `sparkle:edSignature`. Keep previous valid entries.
6. Validate the XML, commit, and explicitly push `release` to `fork`. This publishes the update to Sparkle clients. Verify the public feed and test an update from the previous distributed application.

DMG URLs have this form:

```text
https://github.com/orca-studio/palmier-pro/releases/download/v0.12.0/PalmierPro.dmg
```

The feed and assets must be publicly accessible for this setup. Do not advertise draft, missing, unsigned, or unverified assets. An empty initial feed publishes no updates. If an upload or validation fails, leave the live appcast unchanged and report the failure.

Existing applications retain their embedded feed URL. Changing this repository's `SUFeedURL` affects newly built applications; it does not redirect applications already using the upstream feed.

## Client update flow

```text
Application → fork/release/appcast.xml → fork GitHub Release DMG → signature verification → installation
```

Sparkle does not need the source code in the distribution repository. See [Publishing an update](https://sparkle-project.org/documentation/publishing/).
