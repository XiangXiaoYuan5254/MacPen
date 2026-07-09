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
    targets: [
        .executableTarget(
            name: "MacPen",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
