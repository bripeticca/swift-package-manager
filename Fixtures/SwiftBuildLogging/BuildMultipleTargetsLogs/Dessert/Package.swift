// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Dessert",
    products: [
        .library(
            name: "ChocolateCake",
            targets: ["ChocolateCake"]
        ),
        .library(
            name: "BananaPudding",
            targets: ["BananaPudding"] 
        ),
        .library(
            name: "SugarCookie",
            targets: ["SugarCookie"]
        )
    ],
    targets: [
        .target(
            name: "ChocolateCake",
            dependencies: [
                .target(name: "Dessert")
            ],
            path: "Sources/ChocolateCake/"
        ),
        .target(
            name: "BananaPudding",
            dependencies: [ 
                .target(name: "Dessert")
            ],
            path: "Sources/BananaPudding/"
        ),
        .target(
            name: "SugarCookie",
            dependencies: [ 
                .target(name: "Dessert")
            ],
            path: "Sources/SugarCookie/"
        ),
        .target( 
            name: "Dessert",
            path: "Sources/Dessert/"
        )
    ]
)
