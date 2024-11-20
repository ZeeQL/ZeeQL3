//
//  SQLQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

public struct SQLQualifier : Qualifier, Hashable {
  // TBD: maybe rename to 'RawQualifier'?
  
  public enum Part: Hashable {
    // TODO: lowercase cases for modern Swift
    
    case RawSQLValue(String)
    case QualifierVariable(String)
    
    @inlinable
    public static func ==(lhs: Part, rhs: Part) -> Bool {
      switch ( lhs, rhs ) {
        case ( RawSQLValue(let a), RawSQLValue(let b) ):
          return a == b
        
        case ( QualifierVariable(let a), QualifierVariable(let b) ):
          return a == b
        
        default: return false
      }
    }
  }
  
  public let parts : [ Part ]
  
  @inlinable
  public init(parts: [ Part ]) {
    self.parts = parts // TODO: compact?
  }

  // MARK: - Bindings
  
  @inlinable
  public func addBindingKeys(to set: inout Set<String>) {
    for part in parts {
      if case .QualifierVariable(let key) = part {
        set.insert(key)
      }
    }
  }
  
  @inlinable
  public var hasUnresolvedBindings : Bool {
    for part in parts {
      if case .QualifierVariable = part { return true }
    }
    return false
  }

  @inlinable
  public func qualifierWith(bindings: Any?, requiresAll: Bool) throws
              -> Qualifier?
  {
    guard hasUnresolvedBindings else { return self }
    
    var sql = ""
    for part in parts {
      switch part {
        case .RawSQLValue(let s): sql += s
        case .QualifierVariable(let key):
          guard let vv = KeyValueCoding.value(forKeyPath: key,
                                              inObject: bindings)
           else {
            if requiresAll { throw QualifierBindingNotFound(binding: key) }
            return nil
           }
          sql += "\(vv)" // hm, hm :-)
      }
    }
    return SQLQualifier(parts: [ .RawSQLValue(sql) ])
  }
  
  
  // MARK: - Equality
  
  @inlinable
  public static func ==(lhs: SQLQualifier, rhs: SQLQualifier) -> Bool {
    return lhs.parts == rhs.parts
  }
    
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? SQLQualifier else { return false }
    return self == other
  }
  
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    // TODO: Improve
    ms += " \(parts)"
  }

  public func appendToStringRepresentation(_ ms: inout String) {
    guard !parts.isEmpty else { return }
    
    ms += "SQL["
    for part in parts {
      switch part {
        case .RawSQLValue(let s):       ms += s
        case .QualifierVariable(let k): ms += "$\(k)"
      }
    }
    ms += "]"
  }
}

#if swift(>=5.5)
extension SQLQualifier      : Sendable {}
extension SQLQualifier.Part : Sendable {}
#endif
