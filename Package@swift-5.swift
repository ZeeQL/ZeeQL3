// swift-tools-version:5.0
import PackageDescription

let package = Package(
  name: "ZeeQL3",

  products: [ // TBD: Use ZeeQL3 as library name?
    .library(name: "ZeeQL", targets: [ "ZeeQL" ])
  ],
  dependencies: [
    .package(url: "https://github.com/ZeeQL/CSQLite3.git",
             from: "2.0.0")
  ],
  targets: [
    .target    (name: "ZeeQL",      dependencies: [ "CSQLite3" ]),
    .testTarget(name: "ZeeQLTests", dependencies: [ "ZeeQL"    ])
  ]
)
