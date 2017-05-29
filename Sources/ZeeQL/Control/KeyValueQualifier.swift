//
//  KeyValueQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public struct KeyValueQualifier : Qualifier, Equatable {
  // , QualifierEvaluation {
  // TODO: Evaluation is a little harder in Swift, also coercion
  // Note: Had this as KeyValueQualifier<T>, but this makes class-checks harder.
  //       Not sure what the best Swift approach would be to avoid the Any
  
  public let keyExpr   : Key
  public let value     : Any? // TBD: change to Expression?
  public let operation : ComparisonOperation

  public init(_ key: Key, _ op: ComparisonOperation = .EqualTo, _ value: Any?) {
    self.keyExpr   = key
    self.value     = value
    self.operation = op
  }
  public init(_ key: String, _ op: ComparisonOperation = .EqualTo,
              _ value: Any?)
  {
    self.init(StringKey(key), op, value)
  }
  public init(_ key: String, _ op: String = "==", _ value: Any?) {
    self.init(StringKey(key), ComparisonOperation(string: op), value)
  }
  
  public var key : String { return keyExpr.key }
  
  public var leftExpression  : Expression { return keyExpr }
  public var rightExpression : Expression {
    guard let value = value else { return NullExpression.shared }
    return ConstantValue(value: value)
  }
  
  public var variable : QualifierVariable? {
    return value as? QualifierVariable
  }
  
  public var isEmpty : Bool { return false }
  
  public func addReferencedKeys(to set: inout Set<String>) {
    set.insert(keyExpr.key)
  }
  
  
  // MARK: - Bindings
  
  public func addBindingKeys(to set: inout Set<String>) {
    guard let v = variable else { return }
    set.insert(v.key)
  }
  
  public var hasUnresolvedBindings : Bool {
    return variable != nil
  }
  
  public func keyPathForBindingKey(_ variable: String) -> String? {
    guard let v = self.variable else { return nil }
    guard variable == v.key     else { return nil }
    return key
  }
  
  public func qualifierWith(bindings: Any?, requiresAll: Bool) throws
              -> Qualifier?
  {
    guard let v = self.variable else { return self } /* nothing to replace */
    
    /* check if the value was found */
    
    guard let vv = KeyValueCoding.value(forKeyPath: v.key, inObject: bindings)
     else {
      if requiresAll { throw QualifierBindingNotFound(binding: v.key) }
      return nil
     }
    
    // TBD: Hm
    return KeyValueQualifier(keyExpr, operation, vv)
  }

  
  // MARK: - Equality
  
  public static func ==(lhs: KeyValueQualifier, rhs: KeyValueQualifier)
                     -> Bool
  {
    guard lhs.operation == rhs.operation       else { return false }
    guard lhs.keyExpr.isEqual(to: rhs.keyExpr) else { return false }
    
    if let a = lhs.value, let b = rhs.value {
      if let ac = a as? EquatableType {
        return ac.isEqual(to: b)
      }
      return false
    }
    else if lhs.value != nil { return false }
    else if rhs.value != nil { return false }
    
    return true
  }
  
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? KeyValueQualifier else { return false }
    return self == other
  }
  
  
  // MARK: - Description
  
  public func appendToDescription(_ ms: inout String) {
    // TODO: improve
    ms += " \(keyExpr) \(operation) \(value as Optional)"
  }

  public func appendToStringRepresentation(_ ms: inout String) {
    ms += keyExpr.key
    
    switch ( value, operation ) {
      case ( nil, .EqualTo ):    ms += " IS NULL";     return
      case ( nil, .NotEqualTo ): ms += " IS NOT NULL"; return
      default: break
    }
    
    ms += " \(operation.stringRepresentation) "
    
    guard let value = value else {
      ms += " NULL"
      return
    }
    
    if let v = value as? QualifierVariable {
      ms += " $\(v.key)"
    }
    else if let v = value as? Int {
      ms += " \(v)"
    }
    else if let v = value as? Bool {
      ms += v ? " true" : " false"
    }
    else if let v = value as? String {
      // TODO
      let s = v.replacingOccurrences(of: "'", with: "\\'")
      ms += "'\(s)'"
    }
    else {
      ms += " \(value)"
    }
  }
}
