// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftlyFeedbackServer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.2.0"),
        .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "5.0.0"),
        .package(url: "https://github.com/vapor-community/stripe-kit.git", from: "25.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftlyFeedbackServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "APNS", package: "APNSwift"),
                .product(name: "StripeKit", package: "stripe-kit"),
            ],
            path: "Sources/App"
        ),
        .testTarget(
            name: "SwiftlyFeedbackServerTests",
            dependencies: [
                .target(name: "SwiftlyFeedbackServer"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            path: "Tests/AppTests"
        ),
    ]
)
