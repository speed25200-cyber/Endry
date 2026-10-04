// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{PREFIXE}}Kit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "{{PREFIXE}}Kit", targets: ["{{PREFIXE}}Kit"]),
    ],
    targets: [
        .target(
            name: "{{PREFIXE}}Kit",
            resources: [.copy("Resources/Fixtures")]
        ),
        .testTarget(
            name: "{{PREFIXE}}KitTests",
            dependencies: ["{{PREFIXE}}Kit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
