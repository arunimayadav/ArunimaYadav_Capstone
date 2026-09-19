// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Archivist",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Archivist",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreServices")
            ]
        )
    ]
)
