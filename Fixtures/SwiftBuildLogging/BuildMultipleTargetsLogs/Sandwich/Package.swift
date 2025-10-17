// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Sandwich",
    products: [
        .library(
            name: "PBJ",
            targets: ["PBJ"]
        ),
        .library(
            name: "BLT",
            targets: ["BLT"]
        ),
    ],
    targets: [
        .target(
            name: "PBJ",
            path: "Sources/PeanutButterJelly/"
        ),
        .target( 
            name: "BLT",
            path: "Sources/BaconLettuceTomato/"
        ),
    ]
)
