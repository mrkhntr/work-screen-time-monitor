// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WorkScreenTimeApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WorkScreenTimeApp", targets: ["WorkScreenTimeApp"]),
        .library(name: "WorkScreenTimeCore", targets: ["WorkScreenTimeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .target(
            name: "WorkScreenTimeCore",
            resources: [
                .copy("Resources/core.js")
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .executableTarget(
            name: "WorkScreenTimeApp",
            dependencies: [
                "WorkScreenTimeCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "WorkScreenTimeCoreTests",
            dependencies: ["WorkScreenTimeCore"]
        )
    ]
)
