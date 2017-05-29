//
//  MirrorHelpers.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

extension Mirror {

  func mirrorHierarchy(shouldStop: ( Mirror ) -> Bool) -> [ Mirror ] {
    var cursor : Mirror? = self
    var mirrorHierarchy = [ Mirror ]()
    
    while let mirror = cursor {
      guard !shouldStop(mirror) else { break }
      mirrorHierarchy.append(mirror)
      cursor = mirror.superclassMirror
    }
    return mirrorHierarchy.reversed()
  }

  func mirrorHierarchy() -> [ Mirror ] {
    return mirrorHierarchy() { _ in return false }
  }
  
  func mirrorHierarchy(stopAt prefix: String) -> [ Mirror ] {
    // TODO: another very bad hack :-> Tell me how to do it: @helje5
    let stopPrefix = "Mirror for \(prefix)"
    return mirrorHierarchy() { "\($0)".hasPrefix(stopPrefix) }
  }
  
  func mirrorHierarchy(stopAt stopType: Any.Type) -> [ Mirror ] {
    return mirrorHierarchy() { mirror in mirror.subjectType == stopType }
  }
  
}
