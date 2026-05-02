// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Alaya",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "alaya", targets: ["Alaya"])
    ],
    targets: [
        .executableTarget(
            name: "Alaya"
        ),
        .testTarget(
            name: "AlayaTests",
            dependencies: ["Alaya"]
        )
    ],
    swiftLanguageModes: [.v6]
)
