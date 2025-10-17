// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WarningDiagnostic",
    products: [
        .library(
            name: "WarningDiagnostic",
            targets: ["WarningDiagnostic"]
        ),
    ],
    targets: [
        .target(
            name: "WarningDiagnostic"
        ),
        .testTarget(
            name: "WarningDiagnosticTests",
            dependencies: ["WarningDiagnostic"]
        ),
    ]
)
