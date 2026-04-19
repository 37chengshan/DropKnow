// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DropKnow",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DropKnow",
            dependencies: [],
            path: "DropKnow",
            exclude: ["Resources/SampleData"]
        ),
        .testTarget(
            name: "DropKnowTests",
            dependencies: ["DropKnow"],
            path: "Tests"
        )
    ]
)
