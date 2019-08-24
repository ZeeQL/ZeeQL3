//
//  ComparisonOperation.swift
//  ZeeQLTests
//
//  Created by Helge Heß on 24.08.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

// TODO: Update to modern Swift API standards (e.g. lowercase)

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

public extension ComparisonOperation {
  // TODO: Evaluation is a "little" harder in Swift, also coercion
  // Note: Had this as KeyValueQualifier<T>, but this makes class-checks harder.
  //       Not sure what the best Swift approach would be to avoid the Any

  func compare(_ a: Any?, _ b: Any?) -> Bool {
    // Everytime you compare an Any, a 🐄 dies.
    switch self {
      case .EqualTo:            return eq(a, b)
      case .NotEqualTo:         return !eq(a, b)
      case .LessThan:           return isSmaller(a, b)
      case .GreaterThan:        return isSmaller(b, a)
      case .LessThanOrEqual:    return isSmaller(a, b) || eq(a, b)
      case .GreaterThanOrEqual: return isSmaller(b, a) || eq(a, b)
      
      case .Contains: // firstname in ["donald"] or firstname in "donald"
        guard let b = b else { return false }
        guard let list = b as? ContainsComparisonType else {
          globalZeeQLLogger.error(
            "attempt to evaluate an ComparisonOperation dynamically:",
            self, a, b
          )
          assertionFailure("comparison not supported for dynamic evaluation")
          return false
        }
        return list.contains(other: a)
      
      case .Like, .CaseInsensitiveLike: // firstname like *Donald*
        let ci = self == .CaseInsensitiveLike
        if a == nil && b == nil { return true } // nil is like nil
        guard let value = a as? LikeComparisonType else {
          globalZeeQLLogger.error(
            "attempt to evaluate an ComparisonOperation dynamically:",
            self, a, b
          )
          assertionFailure("comparison not supported for dynamic evaluation")
          return false
        }
        return value.isLike(other: b, caseInsensitive: ci)

      // TODO: support many more, geez :-)
      
      default:
        globalZeeQLLogger.error(
          "attempt to evaluate an ComparisonOperation dynamically:",
          self, a, b
        )
        assertionFailure("comparison not supported for dynamic evaluation")
        return false
    }
  }
}
