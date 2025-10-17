// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Drink",
    products: [
        .library(
            name: "Water",
            targets: ["Water"]
        ),
        .library(
            name: "Juice",
            targets: ["Juice"]
        ),
    ],
    targets: [
        .target(
            name: "Water",
            dependencies: [
                .target(name: "Drink")
            ],
            path: "Sources/Water/"
        ),
        .target(
            name: "Juice",
            dependencies: [
                .target(name: "Drink")
            ],
            path: "Sources/Juice",
        ),
        .target( 
            name: "Drink",
            path: "Sources/Drink"
        )
    ]
)
