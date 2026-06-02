// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Alaya",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "Alaya", targets: ["Alaya"]),
        .executable(name: "alayad", targets: ["alayad"])
    ],
    dependencies: [
        .package(path: "../bioid-core"),
        .package(path: "../vijna"),
        .package(path: "../manas"),
        .package(path: "../manovijna")
    ],
    targets: [
        .target(
            name: "Alaya",
            dependencies: [
                .product(name: "BioidCore", package: "bioid-core")
            ]
        ),
        .executableTarget(
            name: "alayad",
            dependencies: [
                "Alaya",
                .product(name: "Vijna", package: "vijna"),
                .product(name: "Manas", package: "manas"),
                .product(name: "Manovijna", package: "manovijna")
            ]
        ),
        .testTarget(
            name: "AlayaTests",
            dependencies: ["Alaya"]
        )
    ],
    swiftLanguageModes: [.v6]
)
