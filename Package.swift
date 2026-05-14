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
    dependencies: [],
    targets: [
        .target(name: "WorkScreenTimeCore"),
        .executableTarget(
            name: "WorkScreenTimeApp",
            dependencies: ["WorkScreenTimeCore"],
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
