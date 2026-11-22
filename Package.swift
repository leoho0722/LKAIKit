// swift-tools-version: 6.2
import PackageDescription

/// LKAIKit 套件的宣告，包含名稱、最低支援平台、對外的 product 與各個 target
let package = Package(
    name: "LKAIKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LKAIKit", targets: ["LKAIKit"]),
        .executable(name: "lkai", targets: ["LKAIKitCLI"]),
    ],
    // ArgumentParser 只給 LKAIKitCLI 與它的測試使用，LKAIKit 與它可達的 target 不依賴外部套件
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    ],
    targets: [
        .target(name: "LKAICore", resources: [.process("Resources")]),
        .testTarget(name: "LKAICoreTests", dependencies: ["LKAICore"]),
        .target(name: "LKAITestSupport", dependencies: ["LKAICore"]),
        .testTarget(name: "LKAITestSupportTests", dependencies: ["LKAITestSupport", "LKAICore"]),
        .target(name: "LKAIAnthropic", dependencies: ["LKAICore"]),
        .testTarget(
            name: "LKAIAnthropicTests",
            dependencies: ["LKAIAnthropic", "LKAICore", "LKAITestSupport"]
        ),
        .target(name: "LKAIOpenAI", dependencies: ["LKAICore"]),
        .testTarget(
            name: "LKAIOpenAITests",
            dependencies: ["LKAIOpenAI", "LKAICore", "LKAITestSupport"]
        ),
        .target(name: "LKAIGemini", dependencies: ["LKAICore"]),
        .testTarget(
            name: "LKAIGeminiTests",
            dependencies: ["LKAIGemini", "LKAICore", "LKAITestSupport"]
        ),
        .target(
            name: "LKAIKit",
            dependencies: ["LKAICore", "LKAIAnthropic", "LKAIOpenAI", "LKAIGemini"]
        ),
        .testTarget(name: "LKAIKitTests", dependencies: ["LKAIKit"]),
        .executableTarget(
            name: "LKAIKitCLI",
            dependencies: [
                "LKAIKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "LKAIKitCLITests",
            dependencies: [
                "LKAIKitCLI",
                "LKAIKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
