// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hago",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hago", targets: ["Hago"])
    ],
    targets: [
        .target(
            name: "HagoCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Hago",
            dependencies: ["HagoCore"]
        ),
        .testTarget(
            name: "HagoCoreTests",
            dependencies: ["HagoCore"]
        ),
        .testTarget(
            name: "HagoTests",
            dependencies: ["Hago"]
        )
    ]
)
