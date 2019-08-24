//
//  KeyComparisonQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

public struct KeyComparisonQualifier : Qualifier, Equatable {
  
  public let leftKeyExpr  : Key
  public let rightKeyExpr : Key
  public let operation    : ComparisonOperation

  public init(_ left: Key, _ op: ComparisonOperation = .EqualTo, _ right: Key) {
    self.leftKeyExpr  = left
    self.rightKeyExpr = right
    self.operation    = op
  }
  public init(_ left: String, _ op: String = "==", _ right: String) {
    self.init(StringKey(left),
              ComparisonOperation(string: op),
              StringKey(right))
  }
  
  public var leftKey  : String { return leftKeyExpr.key  }
  public var rightKey : String { return rightKeyExpr.key }
  
  public var leftExpression  : Expression { return leftKeyExpr  }
  public var rightExpression : Expression { return rightKeyExpr }
  
  public var isEmpty : Bool { return false }
  
  public func addReferencedKeys(to set: inout Set<String>) {
    set.insert(leftKeyExpr.key)
    set.insert(rightKeyExpr.key)
  }
  
  
  // MARK: - Bindings
  
  public var hasUnresolvedBindings : Bool { return false }

  
  // MARK: - Equality
  
  public static func ==(lhs: KeyComparisonQualifier,
                        rhs: KeyComparisonQualifier) -> Bool
  {
    guard lhs.operation    == rhs.operation              else { return false }
    guard lhs.leftKeyExpr.isEqual(to: rhs.leftKeyExpr)   else { return false }
    guard lhs.rightKeyExpr.isEqual(to: rhs.rightKeyExpr) else { return false }
    return true
  }
  
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? KeyComparisonQualifier else { return false }
    return self == other
  }
  
  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    // TODO: improve
    ms += " \(leftKeyExpr) \(operation) \(rightKeyExpr)"
  }

  public func appendToStringRepresentation(_ ms: inout String) {
    ms += leftKeyExpr.key
    ms += " \(operation.stringRepresentation) "
    ms += rightKeyExpr.key
  }
}
