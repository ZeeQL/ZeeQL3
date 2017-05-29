//
//  BooleanQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public struct BooleanQualifier : Qualifier, QualifierEvaluation, Equatable {
  
  public static let trueQualifier  = BooleanQualifier(value: true)
  public static let falseQualifier = BooleanQualifier(value: false)
  
  public let value : Bool
  
  init(value: Bool) {
    self.value = value
  }

  public var isEmpty : Bool { return false }
  public var hasUnresolvedBindings : Bool { return false }

  public func evaluateWith(object: Any?) -> Bool { return value }
  public func valueFor    (object: Any?) -> Any? { return value }
  
  
  // MARK: - Convenience Overrides

  public var not : Qualifier {
    return value
      ? BooleanQualifier.falseQualifier
      : BooleanQualifier.trueQualifier
  }
  
  public func or(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    return value ? BooleanQualifier.trueQualifier : q
  }
  public func and(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    return value ? q : BooleanQualifier.falseQualifier
  }
  
  
  // MARK: - Equality
  
  public static func ==(lhs: BooleanQualifier, rhs: BooleanQualifier) -> Bool {
    return lhs.value == rhs.value
  }
  
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? BooleanQualifier else { return false }
    return self == other
  }
  
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    ms += value ? " TRUE" : " FALSE"
  }
  
  public func appendToStringRepresentation(_ ms: inout String) {
    ms += value ? "*true*" : "*false"
  }
}
