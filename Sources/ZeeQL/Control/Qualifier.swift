//
//  Qualifier.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol Qualifier : Expression, EquatableType, SmartDescription {
  // TBD: A protocol because there are multiple different, and extendable versions
  //      of this. You cannot add new qualifiers to an enum. 
  //      (Apart from .Other(Any))
  
  var isEmpty : Bool { get }

  func qualifierWith(bindings: Any?, requiresAll: Bool) throws
                     -> Qualifier?

  // MARK: - String Representation
  
  func appendToStringRepresentation(_ ms: inout String)

  // MARK: - Convenience
  
  var  not : Qualifier { get }
  func or (_ q: Qualifier?) -> Qualifier
  func and(_ q: Qualifier?) -> Qualifier
  
}

public extension Qualifier { // default imp

  func isEqual(to object: Any?) -> Bool { return false }
  
  var isEmpty : Bool { return false }
  
  func qualifierWith(bindings: Any?, requiresAll: Bool) throws -> Qualifier? {
    return self
  }
  func qualifierWith(bindings: Any?) throws -> Qualifier? {
    return try qualifierWith(bindings: bindings, requiresAll: false)
  }
  
  
  // MARK: - String Representation
  
  var stringRepresentation : String {
    var ms = ""
    appendToStringRepresentation(&ms)
    return ms
  }
  
  
  // MARK: - Convenience

  var not : Qualifier { return NotQualifier(qualifier: self) }
  
  func or(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    if let bq = q as? BooleanQualifier {
      return bq.value ? BooleanQualifier.trueQualifier : self
    }
    return CompoundQualifier(qualifiers: [ self, q ], op: .Or)
  }
  func and(_ q: Qualifier?) -> Qualifier {
    guard let q = q else { return self }
    if let bq = q as? BooleanQualifier {
      return bq.value ? self : BooleanQualifier.falseQualifier
    }
    return CompoundQualifier(qualifiers: [ self, q ], op: .And)
  }

}

// TODO: can we add Equatable to Qualifier or does it make it generic?
public func ==(lhs: Qualifier, rhs: Qualifier) -> Bool {
  return lhs.isEqual(to: rhs)
}


// MARK: - Comparison Operation

public enum ComparisonOperation : Equatable, SmartDescription {
  // Cannot nest in Qualifier protocol in Swift 3.0, maybe later

  case Unknown(String)
  
  case EqualTo, NotEqualTo, GreaterThan, GreaterThanOrEqual
  case LessThan, LessThanOrEqual, Contains
  
  /**
   * Compare the left hand side against a pattern. The `*` is used as the
   * pattern character (and replaced with the database specific pattern
   * operator when run against the database, e.g. `%` in most SQL databases).
   *
   * Example:
   *
   *     name LIKE 'Zee*'
   *
   * Note: `.Like` coalesces nil values with the empty string. This
   *       can have performance implications in SQL databases. You may choose
   *       to use `.SQLLike` instead. See `.SQLLike` for a discussion why.
   */
  case Like
  
  /**
   * Compare the left hand side against a pattern w/o considering case. The `*`
   * is used as the pattern character, see `.Like` for details.
   *
   * Example:
   *
   *     name ILIKE 'zee*'
   *
   * Not all databases support a SQL case insensitive like. The adaptor may
   * rewrite such queries to `LOWER(name) LIKE 'zee*'`.
   */
  case CaseInsensitiveLike
  
  /**
   * .SQLLike differs to .Like in that it doesn't coalesce nil/NULL values.
   *
   * In SQL databases a LIKE against a NULL column may have unexpected
   * behaviour. If the column `street` is NULL, *neither* of the two queries
   * match the row:
   *
   *     SELECT * FROM address WHERE street LIKE '%way%'
   *     SELECT * FROM address WHERE NOT street LIKE '%way%'
   *
   * Using `.SQLLike` can be faster than `.Like` as the database is more likely
   * able to use an index. Regular `.Like` has the additional processing step
   * where `NULL` values are converted to the empty string.
   */
  case SQLLike
  
  /// Check `.SQLLike` for a discussion and the difference to `.Like`.
  case SQLCaseInsensitiveLike
  
  
  public init(string: String) {
    switch string {
      case "=", "==":  self = .EqualTo
      case ">":        self = .GreaterThan
      case "<":        self = .LessThan
      case "!=":       self = .NotEqualTo
      case ">=", "=>": self = .GreaterThanOrEqual
      case "<=", "=<": self = .LessThanOrEqual
      case "IN":       self = .Contains
      case "LIKE", "like": self = .Like
      case "ILIKE", "ilike", "caseInsensitiveLike:", "caseInsensitiveLike":
        self = .CaseInsensitiveLike
      case "SQLLIKE":  self = .SQLLike
      case "SQLILIKE": self = .SQLCaseInsensitiveLike
      default:
        self = .Unknown(string)
    }
  }
  
  public var stringRepresentation : String {
    switch self {
      case .Unknown(let s):         return s
      case .EqualTo:                return "="
      case .NotEqualTo:             return "!="
      case .GreaterThan:            return ">"
      case .GreaterThanOrEqual:     return ">="
      case .LessThan:               return "<"
      case .LessThanOrEqual:        return "<="
      case .Contains:               return "IN"
      case .Like:                   return "LIKE"
      case .CaseInsensitiveLike:    return "ILIKE"
      case .SQLLike:                return "SQLLIKE"
      case .SQLCaseInsensitiveLike: return "SQLILIKE"
    }
  }
  
  public func appendToDescription(_ ms: inout String) {
    ms += " "
    ms += stringRepresentation
  }
  
  public static func ==(lhs: ComparisonOperation, rhs: ComparisonOperation)
                     -> Bool
  {
    switch ( lhs, rhs ) {
      case ( EqualTo,                EqualTo                ): return true
      case ( NotEqualTo,             NotEqualTo             ): return true
      case ( GreaterThan,            GreaterThan            ): return true
      case ( GreaterThanOrEqual,     GreaterThanOrEqual     ): return true
      case ( LessThan,               LessThan               ): return true
      case ( LessThanOrEqual,        LessThanOrEqual        ): return true
      case ( Contains,               Contains               ): return true
      case ( Like,                   Like                   ): return true
      case ( CaseInsensitiveLike,    CaseInsensitiveLike    ): return true
      case ( SQLLike,                SQLLike                ): return true
      case ( SQLCaseInsensitiveLike, SQLCaseInsensitiveLike ): return true
      case ( Unknown(let lhsV),      Unknown(let rhsV) ): return lhsV == rhsV
      default: return false
    }
  }
}


// MARK: - Factory

// public extension Qualifier { }
//   Cannot nest in Qualifier protocol in Swift 3.0, maybe later
//   And static functions on protocol types do not work either.
  
public func and(_ a: Qualifier?, _ b: Qualifier?) -> Qualifier? {
  if let a = a, let b = b { return a.and(b) }
  if let a = a { return a }
  return b
}
public func or(_ a: Qualifier?, _ b: Qualifier?) -> Qualifier? {
  if let a = a, let b = b { return a.or(b) }
  if let a = a { return a }
  return b
}

/**
 * This method returns a set of KeyValueQualifiers combined with an
 * AndQualifier. The keys/values for the KeyValueQualifier are taken
 * from the record.
 *
 * Example:
 *
 *     { lastname = 'Duck'; firstname = 'Donald'; city = 'Hausen' }
 *
 * Results in:
 *
 *     lastname = 'Duck' AND firstname = 'Donald' AND city = 'Hausen'
 *   
 * - returns: a Qualifier for the given record, or null if the record was empty
 */
public func qualifierToMatchAllValues(_ values: [ String : Any? ]?,
                                      _ op: ComparisonOperation = .EqualTo)
            -> Qualifier?
{
  guard let values = values, !values.isEmpty else { return nil }
  let kvq = values.map { KeyValueQualifier(StringKey($0), op, $1) }
  if kvq.count == 1 { return kvq[0] }
  return CompoundQualifier(qualifiers: kvq, op: .And)
}

/**
 * This method returns a set of KeyValueQualifiers combined with an
 * OrQualifier. The keys/values for the KeyValueQualifier are taken
 * from the Map.
 *
 * Example:
 *
 *     { lastname = 'Duck'; firstname = 'Duck'; city = 'Duck' }
 *
 * Results in:
 *
 *     lastname = 'Duck' OR firstname = 'Duck' OR city = 'Duck'
 *   
 * - returns: an Qualifier for the given record, or null if the record was empty
 */
public func qualifierToMatchAnyValue(_ values: [ String : Any? ]?,
                                     _ op: ComparisonOperation = .EqualTo)
            -> Qualifier?
{
  guard let values = values, !values.isEmpty else { return nil }
  let kvq = values.map { KeyValueQualifier(StringKey($0), op, $1) }
  if kvq.count == 1 { return kvq[0] }
  return CompoundQualifier(qualifiers: kvq, op: .Or)
}
