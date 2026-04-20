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
            exclude: [
                "Assets.xcassets",
                "Infrastructure/Database/DatabaseREADME.md",
                "Infrastructure/Database/migration_v1.sql",
                "Infrastructure/Database/schema.sql"
            ]
        ),
        .testTarget(
            name: "DropKnowTests",
            dependencies: ["DropKnow"],
            path: "Tests"
        )
    ]
)
