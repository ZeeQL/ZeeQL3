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
 * Notice the `SQL` pattern. This ``SQLQualifier`` becomes an array of those
 * values:
 * - `EXISTS ( SELECT 1 FROM object_acl WHERE\n  object_acl.auth_id::int IN `
 *    (raw)
 * - ``QualifierVariable``(authIds)
 * - `AND\n  object_acl.action = 'allowed'\n"             (raw)
 *   "AND\n  object_acl.object_id = BASE.company_id )`    (raw)
 */
public struct SQLQualifier : Qualifier, Equatable {
  // TBD: maybe rename to 'RawQualifier'?

  public struct UnsupportedRawValueValue: Swift.Error {
    @inlinable
    public init() {}
  }

  /**
   * One part of the qualifier.
   */
  public enum Part: Equatable {
    
    public enum RawValueReplacement: Equatable {
      // Improve this, quite limited for now
      case int(Int)
      case double(Double)
      case string(String)
      case intArray([ Int ])
      case stringArray([ String ])
      
      @inlinable
      public init?(_ value: Any) {
        switch value {
          case let v as String                 : self = .string(v)
          case let v as Int                    : self = .int(v)
          case let v as any BinaryInteger      : self = .int(Int(v))
          case let v as Double                 : self = .double(v)
          case let v as Float                  : self = .double(Double(v))
          case let v as any Collection<Int>    : self = .intArray(Array(v))
          case let v as any Collection<String> : self = .stringArray(Array(v))
          case let v as any StringProtocol     : self = .string(String(v))
          default: return nil
        }
      }
    }
    
    /// A raw SQL string part, like `EXISTS ( SELECT 1 FROM object_acl WHERE`
    case rawValue(String)
    case variable(String)
    case value(RawValueReplacement?)
    
    @inlinable
    public static func ==(lhs: Part, rhs: Part) -> Bool {
      switch ( lhs, rhs ) {
        case ( rawValue(let a), rawValue(let b) ): return a == b
        case ( variable(let a), variable(let b) ): return a == b
        case ( value   (let a), value   (let b) ): return a == b
        default: return false
      }
    }
    
    @inlinable
    public static func RawSQLValue(_ s: String) -> Part { .rawValue(s) }
    @inlinable
    public static func QualifierVariable(_ key: String) -> Part {
      .variable(key)
    }
  }
  
  public let parts : [ Part ]
  
  @inlinable
  public init(parts: [ Part ]) {
    // TODO: Compact? (i.e. merge `RawSQLValue` parts). Should be done by the
    //       parser, I suppose.
    self.parts = parts
    assert(!parts.contains {
      if case .rawValue(let v) = $0 { return v == "authIds" }
      else { return false }
    })
  }

  // MARK: - Bindings
  
  @inlinable
  public func addBindingKeys(to set: inout Set<String>) {
    for part in parts {
      switch part {
        case .value, .rawValue: break
        case .variable(let key): set.insert(key)
      }
    }
  }
  
  @inlinable
  public var hasUnresolvedBindings : Bool {
    for part in parts {
      switch part {
        case .value, .rawValue: break
        case .variable: return true
      }
    }
    return false
  }

  @inlinable
  public func qualifierWith(bindings: Any?, requiresAll: Bool) throws
              -> Qualifier?
  {
    guard hasUnresolvedBindings else { return self }

    var newParts = [ Part ](); newParts.reserveCapacity(parts.count)
    for part in parts {
      switch part {
        case .rawValue(let s): newParts.append(.rawValue(s))
        case .value(let value): newParts.append(.value(value))
          
        case .variable(let key):
          guard let vv = KeyValueCoding
            .value(forKeyPath: key, inObject: bindings) else
          {
            if requiresAll { throw QualifierBindingNotFound(binding: key) }
            return nil
          }
          if let opt = vv as? any AnyOptional {
            if let vv = opt.value {
              guard let rawValue = Part.RawValueReplacement(vv) else {
                assertionFailure("Unsupported raw value type")
                throw UnsupportedRawValueValue()
              }
              newParts.append(.value(rawValue))
            }
            else {
              newParts.append(.value(nil))
            }
          }
          else {
            guard let rawValue = Part.RawValueReplacement(vv) else {
              assertionFailure("Unsupported raw value type")
              throw UnsupportedRawValueValue()
            }
            newParts.append(.value(rawValue))
          }
      }
    }
    return SQLQualifier(parts: newParts)
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
        case .rawValue(let s)        : ms += s
        case .variable(let k)        : ms += "$\(k)"
        case .value   (.some(let v)) : ms += "\(v)"
        case .value   (.none)        : ms += "NULL"
      }
    }
    ms += "]"
  }
}

#if swift(>=5.5)
extension SQLQualifier      : Sendable {}
extension SQLQualifier.Part : Sendable {}
extension SQLQualifier.Part.RawValueReplacement : Sendable {}
#endif
