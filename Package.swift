import PackageDescription

let package = Package(
  name: "ZeeQL3",

  swiftLanguageVersions: [ 3, 4 ],  

  targets: [ Target(name: "ZeeQL") ],
  
  dependencies: [
    // TODO: factor out KVC?
    .Package(url: "https://github.com/ZeeQL/CSQLite3.git", 
             majorVersion: 1, minor: 0)
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
