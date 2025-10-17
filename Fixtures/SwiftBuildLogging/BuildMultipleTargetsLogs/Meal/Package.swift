// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Meal",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Lunch",
            targets: ["Lunch"]
        ),
        .library(
            name: "Brunch",
            targets: ["Breakfast", "Lunch"]
        ),
        .library(
            name: "Breakfast",
            targets: ["Breakfast"]
        )
    ],
    dependencies: [
        .package(path: "../Dessert"),
        .package(path: "../Drink"),
        .package(path: "../Sandwich")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Lunch",
            dependencies: [
                .product(
                    name: "BLT",
                    package: "Sandwich"
                ),
                .product(
                    name: "Water",
                    package: "Drink"
                ),
                .product(
                    name: "Juice",
                    package: "Drink"
                ),
                .product(
                    name: "ChocolateCake",
                    package: "Dessert"
                ),
                .product(
                    name: "SugarCookie",
                    package: "Dessert"
                )
            ],
            path: "Sources/Lunch/"
        ),
        .target(
            name: "Breakfast",
            dependencies: [
                .product(
                    name: "PBJ",
                    package: "Sandwich"
                ),
                .product(
                    name: "Water",
                    package: "Drink"
                ),
                .product(
                    name: "Juice",
                    package: "Drink"
                ),
                .product(
                    name: "BananaPudding",
                    package: "Dessert"
                )
            ],
            path: "Sources/Breakfast/"
        ),

    ]
)
