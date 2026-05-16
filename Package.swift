// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DropKnow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DropKnow", targets: ["DropKnow"])
    ],
    targets: [
        .executableTarget(
            name: "DropKnow",
            resources: [
                .copy("Scripts/rag_helper.py")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "DropKnowTests",
            dependencies: ["DropKnow"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
