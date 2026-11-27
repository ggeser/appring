// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "appring-macos",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "appring", targets: ["appring"]),
    ],
    targets: [
        .target(name: "AppringCore"),
        .executableTarget(
            name: "appring",
            dependencies: ["AppringCore"],
            resources: [.process("default.json")]
        ),
        // Не XCTest: у Command Line Tools нет этого фреймворка, раннер запускается через swift run.
        .executableTarget(name: "appring-core-tests", dependencies: ["AppringCore"]),
    ]
)
