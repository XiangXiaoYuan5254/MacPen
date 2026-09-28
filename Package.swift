// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacPen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacPen", targets: ["MacPen"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "MacPen",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                // Scripts/package_app.sh embeds Sparkle.framework in MacPen.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
