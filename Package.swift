// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XClose",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "XClose", targets: ["XClose"]),
        .library(name: "XCloseCore", targets: ["XCloseCore"]),
    ],
    dependencies: [
        // Auto-updates for direct distribution (EdDSA-signed appcast).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Platform-independent policy, state and sequencing logic. No AppKit/AX imports.
        .target(name: "XCloseCore"),
        // The menu-bar application: event tap, Accessibility, AppKit/SwiftUI UI.
        .executableTarget(
            name: "XClose",
            dependencies: [
                "XCloseCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "XCloseCoreTests", dependencies: ["XCloseCore"]),
    ]
)
