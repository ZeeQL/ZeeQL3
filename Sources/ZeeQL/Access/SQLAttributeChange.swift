//
//  SQLAttributeChange.swift
//  ZeeQL3
//
//  Created by Helge Hess on 10/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

struct SQLAttributeChange : SmartDescription {
  
  var name         : ( String, String )?
  var nullability  : Bool?
  var externalType : String?
  
  var hasChanges : Bool {
    if name         != nil { return true }
    if nullability  != nil { return true }
    if externalType != nil { return true }
    return false
  }
  
  func appendToDescription(_ ms: inout String) {
    if let (old,new) = name { ms += " rename[\(old)=>\(new)]"   }
    if let v = nullability  { ms += (v ? " null" : " not-null") }
    if let v = externalType { ms += " type=\(v)"                }
  }
}
