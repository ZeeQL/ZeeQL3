//
//  QualifierVariable.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public struct QualifierVariable {
  
  public let key : String
  
}

extension QualifierVariable : CustomStringConvertible {
  public var description : String {
    return "<QualifierVariable: \(key)>"
  }
}
