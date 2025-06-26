//
//  SQLQualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * A low level qualifier that is composed of raw SQL and optionally qualifier
 * variables.
 *
 * In a qualifier string version this may look like:
 * ```xml
 * <qualifier>
 *   (ownerId IN $authIds) OR (isPrivate IS NULL) OR (isPrivate = 0) OR
 *   SQL[
 *     EXISTS ( SELECT 1 FROM object_acl WHERE
 *       object_acl.auth_id::int IN $authIds
 *       AND
 *       object_acl.action = 'allowed'
 *       AND
 *       object_acl.object_id = BASE.company_id )
 *   ]
 * </qualifier>
 * ```
 * Notice the `SQL` pattern. This SQLQualifier becomes an array of those values:
 * - `EXISTS ( SELECT 1 FROM object_acl WHERE\n  object_acl.auth_id::int IN `
 * - QualifierVariable(authIds)
 * - `AND\n  object_acl.action = 'allowed'\n"
 *   "AND\n  object_acl.object_id = BASE.company_id )`
 */
public struct SQLQualifier : Qualifier, Hashable {
  // TBD: maybe rename to 'RawQualifier'?
  
  /**
   * One part of the qualifier
   */
  public enum Part: Hashable {
    // TODO: lowercase cases for modern Swift
    
    case rawValue(String)
    case variable(String)
    
    @inlinable
    public static func ==(lhs: Part, rhs: Part) -> Bool {
      switch ( lhs, rhs ) {
        case ( rawValue(let a), rawValue(let b) ):
          return a == b
        
        case ( variable(let a), variable(let b) ):
          return a == b
        
        default: return false
      }
    }
  }
  
  public let parts : [ Part ]
  
  @inlinable
  public init(parts: [ Part ]) {
    // TODO: Compact? (i.e. merge `RawSQLValue` parts). Should be done by the
    //       parser, I suppose.
    self.parts = parts
  }

  // MARK: - Bindings
  
  @inlinable
  public func addBindingKeys(to set: inout Set<String>) {
    for part in parts {
      if case .variable(let key) = part {
        set.insert(key)
      }
    }
  }
  
  @inlinable
  public var hasUnresolvedBindings : Bool {
    for part in parts {
      if case .variable = part { return true }
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
        case .rawValue(let s): sql += s
        case .variable(let key):
          guard let vv = KeyValueCoding
            .value(forKeyPath: key, inObject: bindings) else
          {
            if requiresAll { throw QualifierBindingNotFound(binding: key) }
            return nil
          }
          
          // OK, this may need to interact w/ SQLExpression, or preserve the
          // value in here?
          
          let s = "\(vv)" // hm, hm :-)
          sql += s
      }
    }
    return SQLQualifier(parts: [ .rawValue(sql) ])
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
        case .rawValue(let s): ms += s
        case .variable(let k): ms += "$\(k)"
      }
    }
    ms += "]"
  }
}

#if swift(>=5.5)
extension SQLQualifier      : Sendable {}
extension SQLQualifier.Part : Sendable {}
#endif
