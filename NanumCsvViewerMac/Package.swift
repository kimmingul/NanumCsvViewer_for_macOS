// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "NanumCsvViewerMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CsvCore", targets: ["CsvCore"]),
        .executable(name: "NanumCsvViewerMac", targets: ["NanumCsvViewerMac"]),
        .executable(name: "CsvBench", targets: ["CsvBench"]),
    ],
    targets: [
        .target(
            name: "CsvCore"
        ),
        .executableTarget(
            name: "NanumCsvViewerMac",
            dependencies: ["CsvCore"]
        ),
        .executableTarget(
            name: "CsvBench",
            dependencies: ["CsvCore"]
        ),
        .testTarget(
            name: "CsvCoreTests",
            dependencies: ["CsvCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
