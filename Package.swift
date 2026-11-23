// swift-tools-version:6.4
import PackageDescription

/// The Cacao desktop shell for Linux.
///
/// See `Documentation/Plan.md` for the architecture. In short:
///
/// - `CacaoMenuBar`: the menu bar, and the status bar in tablet and phone
///   modes.
/// - `CacaoDock`: the dock, the app grid and launcher entries.
/// - `CacaoSettings`: the settings daemon and portal backend.
/// - `CacaoShellKit`: what the four share: form factor, desktop entries,
///   D-Bus names and settings, and the Swift side of the dock protocol.
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
        )
    ],
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
            ]
        ),
        .executableTarget(
            name: "CacaoMenuBar",
            dependencies: [
                "CacaoShellKit",
                .product(
                    name: "CacaoSDL",
                    package: "Cacao"
                )
            ]
        ),
        .executableTarget(
            name: "CacaoDock",
            dependencies: [
                "CacaoShellKit",
                .product(
                    name: "CacaoSDL",
                    package: "Cacao"
                )
            ]
        ),
        .executableTarget(
            name: "CacaoSettings",
            dependencies: [
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
    ]
)
