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
        .executable(name: "ImportService", targets: ["ImportService"]),
        .executable(name: "CsvBench", targets: ["CsvBench"]),
    ],
    targets: [
        .target(
            name: "CsvCore"
        ),
        .target(
            name: "CLibXLS",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("src")
            ],
            linkerSettings: [
                .linkedLibrary("iconv")
            ]
        ),
        .target(
            name: "CReadStat",
            exclude: [
                "src/stata",
                "src/sas/readstat_sas7bcat_write.c",
                "src/sas/readstat_sas7bdat_write.c",
                "src/sas/readstat_xport.c",
                "src/sas/readstat_xport.h",
                "src/sas/readstat_xport_parse_format.c",
                "src/sas/readstat_xport_parse_format.h",
                "src/sas/readstat_xport_parse_format.rl",
                "src/sas/readstat_xport_read.c",
                "src/sas/readstat_xport_write.c",
                "src/spss/readstat_por.c",
                "src/spss/readstat_por.h",
                "src/spss/readstat_por_parse.c",
                "src/spss/readstat_por_parse.h",
                "src/spss/readstat_por_parse.rl",
                "src/spss/readstat_por_read.c",
                "src/spss/readstat_por_write.c",
                "src/spss/readstat_sav_write.c",
                "src/spss/readstat_zsav_write.c",
                "src/txt"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_ZLIB", to: "1"),
                .headerSearchPath("include"),
                .headerSearchPath("src")
            ],
            linkerSettings: [
                .linkedLibrary("iconv"),
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "ImportServiceProtocol"
        ),
        .executableTarget(
            name: "NanumCsvViewerMac",
            dependencies: ["CsvCore", "ImportServiceProtocol"]
        ),
        .executableTarget(
            name: "ImportService",
            dependencies: ["ImportServiceProtocol", "CLibXLS", "CReadStat"]
        ),
        .executableTarget(
            name: "CsvBench",
            dependencies: ["CsvCore"]
        ),
        .testTarget(
            name: "CsvCoreTests",
            dependencies: ["CsvCore"]
        ),
        .testTarget(
            name: "NanumCsvViewerMacTests",
            dependencies: ["NanumCsvViewerMac"]
        ),
        .testTarget(
            name: "ImportServiceProtocolTests",
            dependencies: ["ImportServiceProtocol"]
        ),
        .testTarget(
            name: "ImportServiceTests",
            dependencies: ["CsvCore", "ImportService", "ImportServiceProtocol"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
