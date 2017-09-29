import PackageDescription

let package = Package(
  name: "ZeeQL3",

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

#if swift(>=3.1)
package.swiftLanguageVersions = [ 3, 4 ]
#endif
