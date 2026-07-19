// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CineVietIOSFoundation",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "CineVietIOSFoundation", targets: ["CineVietIOSFoundation"])
    ],
    targets: [
        .target(
            name: "CineVietIOSFoundation",
            path: "CineViet"
        )
    ]
)
