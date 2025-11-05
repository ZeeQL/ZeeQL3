//
//  KeyValueQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

public struct KeyValueQualifier : Qualifier, Equatable {
  
  public let keyExpr   : Key
  public let value     : Any? // TBD: change to Expression?
  public let operation : ComparisonOperation

  @inlinable
  public init(_ key: Key, _ op: ComparisonOperation = .equalTo, _ value: Any?) {
    self.keyExpr   = key
    self.value     = value
    self.operation = op
  }

  @inlinable
  public init(_ key: String, _ op: ComparisonOperation = .equalTo,
              _ value: Any?)
  {
    self.init(StringKey(key), op, value)
  }
  
  @inlinable
  public init<T>(_ key: Key, _ op: ComparisonOperation = .equalTo, _ value: T)
    where T: AnyOptional
  {
    self.keyExpr   = key
    self.value     = value.value
    self.operation = op
  }
  @inlinable
  public init<T>(_ key: String, _ op: ComparisonOperation = .equalTo,
                 _ value: T)
    where T: AnyOptional
  {
    self.init(StringKey(key), op, value)
  }

  @inlinable
  public init(_ key: String, _ op: String, _ value: Any?) {
    self.init(StringKey(key), ComparisonOperation(string: op), value)
  }
  
  
  // MARK: - Properties
  
  @inlinable
  public var key : String { return keyExpr.key }
  
  @inlinable
  public var isEmpty : Bool { return false }
  

  // MARK: - Expressions
  
  @inlinable
  public var leftExpression  : Expression { return keyExpr }
  public var rightExpression : Expression {
    guard let value = value else { return NullExpression.shared }
    return ConstantValue(value: value)
  }
  
  
  // MARK: - Variables
  
  @inlinable
  public var variable : QualifierVariable? {
    return value as? QualifierVariable
  }
  
  @inlinable
  public func addReferencedKeys(to set: inout Set<String>) {
    set.insert(keyExpr.key)
  }
  
  
  // MARK: - Bindings
  
  @inlinable
  public func addBindingKeys(to set: inout Set<String>) {
    guard let v = variable else { return }
    set.insert(v.key)
  }
  
  @inlinable
  public var hasUnresolvedBindings : Bool { return variable != nil }
  
  @inlinable
  public func keyPathForBindingKey(_ variable: String) -> String? {
    guard let v = self.variable else { return nil }
    guard variable == v.key     else { return nil }
    return key
  }
  
  @inlinable
  public func qualifierWith(bindings: Any?, requiresAll: Bool) throws
              -> Qualifier
  {
    guard let v = self.variable else { return self } /* nothing to replace */
    
    /* check if the value was found */
    
    guard let vv = KeyValueCoding.value(forKeyPath: v.key, inObject: bindings)
     else {
      if requiresAll { throw QualifierBindingNotFound(binding: v.key) }
      return self
     }
    
    return KeyValueQualifier(keyExpr, operation, vv)
  }

  
  // MARK: - Equality
  
  @inlinable
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
  
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? KeyValueQualifier else { return false }
    return self == other
  }
  
  
  // MARK: - Description
  
  @inlinable
  public func appendToDescription(_ ms: inout String) {
    // TODO: improve
    if let key = keyExpr as? StringKey {
      ms += " \(key.key) \(operation) \(value as Optional)"
    }
    else {
      ms += " \(keyExpr) \(operation) \(value as Optional)"
    }
  }

  public func appendToStringRepresentation(_ ms: inout String) {
    ms += keyExpr.key
    
    switch ( value, operation ) {
      case ( nil, .equalTo ):    ms += " IS NULL";     return
      case ( nil, .notEqualTo ): ms += " IS NOT NULL"; return
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
