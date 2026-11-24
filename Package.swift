// swift-tools-version:6.4
import PackageDescription

/// The Cacao desktop shell for Linux.
///
/// See `Documentation/Plan.md` for the architecture. In short:
///
/// - `CacaoWindowServer`: the compositor. Window policy in Swift, over
///   wlroots through the `CWLRoots` shim.
/// - `CacaoMenuBar`: the menu bar, and the status bar in tablet and phone
///   modes.
/// - `CacaoDock`: the dock, the app grid and launcher entries.
/// - `CacaoSettings`: the settings daemon and portal backend.
/// - `CacaoDesktop`: the wallpaper, until the file manager owns the desktop.
/// - `CacaoShellKit`: what the four share: form factor, desktop entries,
///   D-Bus names and settings, and the Swift side of the dock protocol.
/// - `CWLRoots`: the C shim over wlroots, with the protocol handlers.
/// - `CShellProtocols`: code generated from protocol XML.
///
/// The compositor and its C targets build on Linux only. One wlroots
/// release is pinned: 0.18.
let package = Package(
    name: "CacaoShell",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CacaoShellKit",
            targets: ["CacaoShellKit"]
        ),
        .executable(
            name: "CacaoMenuBar",
            targets: ["CacaoMenuBar"]
        ),
        .executable(
            name: "CacaoDock",
            targets: ["CacaoDock"]
        ),
        .executable(
            name: "CacaoSettings",
            targets: ["CacaoSettings"]
        ),
        .executable(
            name: "CacaoDesktop",
            targets: ["CacaoDesktop"]
        )
    ] + compositorProducts,
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/Cacao.git",
            branch: "develop"
        ),
        .package(
            url: "https://github.com/PureSwift/DBus.git",
            branch: "master"
        )
    ],
    targets: [
        .target(
            name: "CacaoShellKit",
            dependencies: [
                .product(
                    name: "DBus",
                    package: "DBus"
                )
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            name: "CacaoMenuBar",
            dependencies: [
                "CacaoShellKit",
                .product(
                    name: "CacaoSDL",
                    package: "Cacao"
                )
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            name: "CacaoDock",
            dependencies: [
                "CacaoShellKit",
                .product(
                    name: "CacaoSDL",
                    package: "Cacao"
                )
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            name: "CacaoDesktop",
            dependencies: [
                .product(
                    name: "CacaoSDL",
                    package: "Cacao"
                )
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            name: "CacaoSettings",
            dependencies: [
                "CacaoShellKit",
                .product(
                    name: "DBus",
                    package: "DBus"
                )
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .testTarget(
            name: "CacaoSettingsTests",
            dependencies: [
                "CacaoSettings",
                "CacaoShellKit",
                .product(
                    name: "DBus",
                    package: "DBus"
                )
            ]
        ),
        .testTarget(
            name: "CacaoShellKitTests",
            dependencies: [
                "CacaoShellKit",
                .product(
                    name: "DBus",
                    package: "DBus"
                )
            ]
        )
    ] + compositorTargets
)

// MARK: - Compositor

// The compositor needs wlroots and libwayland-server, so it builds on Linux
// only.
#if os(Linux)
var compositorProducts: [Product] {
    [
        .executable(
            name: "CacaoWindowServer",
            targets: ["CacaoWindowServer"]
        )
    ]
}
var compositorTargets: [Target] {
    [
        .executableTarget(
            name: "CacaoWindowServer",
            dependencies: [
                "CacaoShellKit",
                "CWLRoots"
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .target(
            name: "CWLRoots",
            dependencies: [
                "CWLRootsSystem",
                "CShellProtocols"
            ],
            exclude: ["CMakeLists.txt"],
            cSettings: [
                .define("WLR_USE_UNSTABLE")
            ],
            linkerSettings: [
                .linkedLibrary("wayland-server"),
                .linkedLibrary("xkbcommon")
            ]
        ),
        // wlroots' include and library paths, from pkg-config.
        .systemLibrary(
            name: "CWLRootsSystem",
            pkgConfig: "wlroots-0.18",
            providers: [
                .apt(["libwlroots-0.18-dev"])
            ]
        ),
        .target(
            name: "CShellProtocols",
            exclude: ["protocol", "CMakeLists.txt"]
        )
    ]
}
#else
var compositorProducts: [Product] { [] }
var compositorTargets: [Target] { [] }
#endif
