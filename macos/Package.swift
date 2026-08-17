// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SettingsManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "SettingsManager",
            dependencies: [
                .product(name: "AWSLambda", package: "aws-sdk-swift"),
                .product(name: "AWSSecretsManager", package: "aws-sdk-swift"),
                .product(name: "AWSSDKIdentity", package: "aws-sdk-swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/SettingsManager"
        ),
    ]
)
