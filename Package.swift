// swift-tools-version: 6.2
// GENERATED — do not edit by hand.
//
// Rendered by scripts/render_package_manifest.sh during a tagged release build
// and committed to the public client SDK repo. Core, Kit, and KMP all ship as
// remote binaryTargets: the url points at the matching GitHub Release asset and
// the checksum is computed from that exact zip, so a resolved package can never
// drift from the binary it was built against.

import PackageDescription

let package = Package(
    name: "MaestroKit",
    platforms: [.tvOS(.v18), .iOS(.v18)],
    products: [
        // MaestroSentryLink and MaestroRiveLink are internal link shims:
        // consumers never import them, but their presence pulls the Sentry and
        // RiveRuntime dependencies into the app so the binary targets resolve.
        .library(name: "MaestroKit", targets: ["MaestroKitParamount", "MaestroCore", "paramountKit", "MaestroSentryLink", "MaestroRiveLink"])
    ],
    dependencies: [
        // Dynamic Sentry product so MaestroCore's `@rpath/Sentry.framework`
        // reference resolves to a single shared copy (no static bake-in, no
        // duplicate-symbol collision with a host app that also uses Sentry).
        .package(url: "https://github.com/getsentry/sentry-cocoa", .upToNextMajor(from: "9.19.1")),
        // RiveRuntime renders MaestroKit's overlays. Pinned to the exact version
        // the shipped binaries were compiled against.
        .package(url: "https://github.com/rive-app/rive-ios", exact: "6.21.0"),
    ],
    targets: [
        .binaryTarget(
            name: "MaestroKitParamount",
            url: "https://github.com/lessthan3/MaestroKit-Paramount.swift/releases/download/1.12.0/MaestroKitParamount.xcframework.zip",
            checksum: "f5dd09fe89ad02917a2f57805bbb065f0a323f9e390f41a79432f0941590de21"
        ),
        .binaryTarget(
            name: "MaestroCore",
            url: "https://github.com/lessthan3/MaestroKit-Paramount.swift/releases/download/1.12.0/MaestroCore.xcframework.zip",
            checksum: "a3d473f2089cade75f637f80aa756c8595180ae06d4449a20055a0d6fcbfc34f"
        ),
        .binaryTarget(
            name: "paramountKit",
            url: "https://github.com/lessthan3/MaestroKit.android/releases/download/paramountKit-4.0.36.374/paramountKit-4.0.36.374.zip",
            checksum: "7bb8aabc4a191364c0ec0ed1bb23e32a01e5fa286da949b9e4345d582ff2a0d5"
        ),
        // Internal link shim (source target): pulls the dynamic Sentry framework
        // into the product so MaestroCore's telemetry resolves at runtime. Its
        // source is committed to the public repo at the path below.
        .target(
            name: "MaestroSentryLink",
            dependencies: [
                .product(name: "Sentry-Dynamic", package: "sentry-cocoa"),
            ],
            path: "Sources/MaestroSentryLink"
        ),
        // Internal link shim (source target): pulls RiveRuntime into the product
        // so the kit binary's `import RiveRuntime` resolves and links. Its source
        // is committed to the public repo at the path below.
        .target(
            name: "MaestroRiveLink",
            dependencies: [
                .product(name: "RiveRuntime", package: "rive-ios"),
            ],
            path: "Sources/MaestroRiveLink"
        )
    ]
)
