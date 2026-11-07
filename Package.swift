// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NapeCompanion",
    products: [
        .library(name: "NapeProtocol", targets: ["NapeProtocol"]),
    ],
    targets: [
        .target(name: "NapeProtocol"),
        .testTarget(name: "NapeProtocolTests", dependencies: ["NapeProtocol"]),
    ]
)
