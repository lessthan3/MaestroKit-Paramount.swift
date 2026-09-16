# MaestroKit for Paramount

The Maestro SDK for Paramount, delivered as a Swift Package. Supports **iOS 18+**
and **tvOS 18+**.

## Install

In Xcode: **File → Add Package Dependencies…**, enter the repository URL, and
choose **Up to Next Major** from the latest version.

```
https://github.com/lessthan3/MaestroKit-Paramount.swift
```

Or add it to your own `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lessthan3/MaestroKit-Paramount.swift", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "MaestroKit", package: "MaestroKit-Paramount.swift"),
        ]
    ),
]
```

Xcode resolves the package and downloads the prebuilt frameworks automatically —
there's nothing else to link or embed.

### Preview builds

Prerelease versions (`1.2.0-beta.1` and the like) aren't picked up by `from:` —
Swift Package Manager skips prerelease tags. To try one, point at the branch of
the same name:

```swift
.package(url: "https://github.com/lessthan3/MaestroKit-Paramount.swift", branch: "1.2.0-beta.1"),
```

Move back to `from:` once the final version ships.

## Quick start

```swift
import MaestroKitParamount

// Once, early in your app's lifecycle:
await MaestroManager.shared.configure(siteID: "YOUR_SITE_ID")
```

Replace `YOUR_SITE_ID` with the site ID your Maestro contact provides.

## Documentation

Integration guides are provided in the `Docs/` folder of this repo.

## Release notes

Each version's changes are on the repo's
[Releases](https://github.com/lessthan3/MaestroKit-Paramount.swift/releases) page.
