// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SyntaxErrorDiagnostic",
    products: [
        .library(
            name: "SyntaxErrorDiagnostic",
            targets: ["SyntaxErrorDiagnostic"]
        ),
    ],
    targets: [
        .target(
            name: "SyntaxErrorDiagnostic"
        ),
        .testTarget(
            name: "SyntaxErrorDiagnosticTests",
            dependencies: ["SyntaxErrorDiagnostic"]
        ),
    ]
)
