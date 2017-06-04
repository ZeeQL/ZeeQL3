//
//  NotQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public struct NotQualifier : Qualifier, Equatable {
  
  public let qualifier : Qualifier

  public init(qualifier: Qualifier) {
    self.qualifier = qualifier
  }
  
  public var isEmpty : Bool      { return qualifier.isEmpty }
  public var not     : Qualifier { return qualifier }
  
  
  // MARK: - Bindings and References

  public func addReferencedKeys(to set: inout Set<String>) {
    qualifier.addReferencedKeys(to: &set)
  }

  public var hasUnresolvedBindings : Bool {
    return qualifier.hasUnresolvedBindings
  }
  
  public func keyPathForBindingKey(_ variable: String) -> String? {
    return qualifier.keyPathForBindingKey(variable)
  }
  
  public func qualifierWith(bindings: Any?, requiresAll: Bool) throws
              -> Qualifier?
  {
    return try qualifierWith(bindings: bindings, requiresAll: requiresAll)?.not
  }
  
  
  // MARK: - Equality
  
  public static func ==(lhs: NotQualifier, rhs: NotQualifier) -> Bool {
    return lhs.qualifier.isEqual(to: rhs.qualifier)
  }
  
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? NotQualifier else { return false }
    return self == other
  }
  
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    ms += " NOT(\(qualifier))"
  }
  
  public func appendToStringRepresentation(_ ms: inout String) {
    if qualifier is KeyValueQualifier || qualifier is KeyComparisonQualifier {
      ms.append("NOT ")
      qualifier.appendToStringRepresentation(&ms)
    }
    else {
      ms.append("NOT (")
      qualifier.appendToStringRepresentation(&ms)
      ms.append(")")
    }
  }
}
