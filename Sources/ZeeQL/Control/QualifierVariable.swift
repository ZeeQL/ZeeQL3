//
//  QualifierVariable.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

public struct QualifierVariable: Hashable {
  
  public let key : String
  
  @inlinable
  public init(key: String) { self.key = key }
}

extension QualifierVariable : CustomStringConvertible {
  public var description : String {
    return "<QualifierVariable: \(key)>"
  }
}

#if swift(>=5.5)
extension QualifierVariable : Sendable {}
#endif
