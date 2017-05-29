import PackageDescription

let package = Package(
  name: "ZeeQL3",
  
  targets: [ Target(name: "ZeeQL") ],
  
  dependencies: [
    // TODO: factor out KVC?
    .Package(url: "git@github.com:helje5/CSQLite3.git", majorVersion: 0)
  ],
	
  exclude: [
    "ZeeQL3.xcodeproj",
    "GNUmakefile",
    "LICENSE",
    "README.md",
    "xcconfig",
    "Documentation"
  ]
)
