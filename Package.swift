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
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(
            name: "HagoCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Hago",
            dependencies: ["HagoCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "HagoCoreTests",
            dependencies: ["HagoCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "HagoTests",
            dependencies: ["Hago"]
        )
    ]
)
