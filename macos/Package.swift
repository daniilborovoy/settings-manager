// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SettingsManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SettingsManager",
            dependencies: [
                .product(name: "AWSLambda", package: "aws-sdk-swift"),
                .product(name: "AWSSecretsManager", package: "aws-sdk-swift"),
                .product(name: "AWSSDKIdentity", package: "aws-sdk-swift"),
            ],
            path: "Sources/SettingsManager"
        ),
    ]
)
