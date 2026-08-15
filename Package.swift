// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FolderTerminal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FolderTerminal", targets: ["FolderTerminal"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            revision: "f02e34bb7d564408a0f48d5c73d382ddb7d04dc0"
        )
    ],
    targets: [
        .target(name: "FolderTerminalCore"),
        .executableTarget(
            name: "FolderTerminal",
            dependencies: [
                "FolderTerminalCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .testTarget(
            name: "FolderTerminalCoreTests",
            dependencies: ["FolderTerminalCore"]
        )
    ]
)
