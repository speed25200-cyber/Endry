// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EndryKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EndryKit", targets: ["EndryKit"]),
    ],
    targets: [
        .target(
            name: "EndryKit",
            resources: [.copy("Resources/Fixtures")]
        ),
        .testTarget(
            name: "EndryKitTests",
            dependencies: ["EndryKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
