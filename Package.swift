// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS("14.4")],
    products: [
        // Заставка собирается динамической библиотекой и упаковывается
        // в бандл .saver скриптом Scripts/install-saver.sh
        .library(name: "AuraSaver", type: .dynamic, targets: ["AuraSaver"]),
    ],
    targets: [
        // Точка входа. Всё остальное живёт в AuraCore, чтобы логику можно было
        // покрыть тестами — тестовый таргет не умеет импортировать executable.
        .executableTarget(
            name: "Aura",
            dependencies: ["AuraCore"],
            path: "Sources/Aura",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AuraCore",
            path: "Sources/AuraCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AuraSaver",
            path: "Sources/AuraSaver",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AuraCoreTests",
            dependencies: ["AuraCore"],
            path: "Tests/AuraCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
