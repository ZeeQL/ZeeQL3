//
//  ComparisonOperation.swift
//  ZeeQLTests
//
//  Created by Helge Heß on 24.08.19.
//  Copyright © 2019-2025 ZeeZide GmbH. All rights reserved.
//

public enum ComparisonOperation: Hashable, RawRepresentable {
  // Cannot nest in Qualifier protocol in Swift 3.0, maybe later
  // TODO: lowercase cases (can use static vars for compat)

  case other(String)
  
  case equalTo, notEqualTo, greaterThan, greaterThanOrEqual
  case lessThan, lessThanOrEqual
  
  // An `IN` query, e.g. `id IN %@`, where the %@ resolves to a collection.
  case `in`
  
  /**
   * Compare the left hand side against a pattern. The `*` is used as the
   * pattern character (and replaced with the database specific pattern
   * operator when run against the database, e.g. `%` in most SQL databases).
   *
   * Example:
   * ```sql
   * name LIKE 'Zee*'
   * ```
   *
   * Note: `.Like` coalesces nil values with the empty string. This
   *       can have performance implications in SQL databases. You may choose
   *       to use `.SQLLike` instead. See `.SQLLike` for a discussion why.
   */
  case like
  
  /**
   * Compare the left hand side against a pattern w/o considering case. The `*`
   * is used as the pattern character, see `.Like` for details.
   *
   * Example:
   * ```sql
   * name ILIKE 'zee*'
   * ```
   *
   * Not all databases support a SQL case insensitive like. The adaptor may
   * rewrite such queries to `LOWER(name) LIKE 'zee*'`.
   */
  case caseInsensitiveLike
  
  /**
   * .SQLLike differs to .Like in that it doesn't coalesce nil/NULL values.
   *
   * In SQL databases a LIKE against a NULL column may have unexpected
   * behaviour. If the column `street` is NULL, *neither* of the two queries
   * match the row:
   * ```sql
   * SELECT * FROM address WHERE street LIKE '%way%'
   * SELECT * FROM address WHERE NOT street LIKE '%way%'
   * ```
   *
   * Using `.SQLLike` can be faster than `.Like` as the database is more likely
   * able to use an index. Regular `.Like` has the additional processing step
   * where `NULL` values are converted to the empty string.
   */
  case SQLLike
  
  /// Check `.SQLLike` for a discussion and the difference to `.Like`.
  case SQLCaseInsensitiveLike
}

public extension ComparisonOperation {
  @available(*, deprecated, message: "Use `.other` instead.")
  static func Unknown(_ value: String) -> Self { .other(value) }
  @available(*, deprecated, message: "Use `.equalTo` instead.")
  static let EqualTo             = Self.equalTo
  @available(*, deprecated, message: "Use `.notEqualTo` instead.")
  static let NotEqualTo          = Self.notEqualTo
  @available(*, deprecated, message: "Use `.greaterThan` instead.")
  static let GreaterThan         = Self.greaterThan
  @available(*, deprecated, message: "Use `.greaterThanOrEqual` instead.")
  static let GreaterThanOrEqual  = Self.greaterThanOrEqual
  @available(*, deprecated, message: "Use `.lessThan` instead.")
  static let LessThan            = Self.lessThan
  @available(*, deprecated, message: "Use `.lessThanOrEqual` instead.")
  static let LessThanOrEqual     = Self.lessThanOrEqual
  @available(*, deprecated, message: "Use `.in` instead.")
  static let Contains            = Self.in
  @available(*, deprecated, message: "Use `.like` instead.")
  static let Like                = Self.like
  @available(*, deprecated, message: "Use `.caseInsensitiveLike` instead.")
  static let CaseInsensitiveLike = Self.caseInsensitiveLike

}

public extension ComparisonOperation {
  @inlinable
  init(rawValue: String) { self.init(string: rawValue) }
  @inlinable
  var rawValue: String { self.stringRepresentation }
}

public extension ComparisonOperation {
  
  @inlinable
  init(string: String) {
    switch string {
      case "=", "==":  self = .equalTo
      case ">":        self = .greaterThan
      case "<":        self = .lessThan
      case "!=":       self = .notEqualTo
      case ">=", "=>": self = .greaterThanOrEqual
      case "<=", "=<": self = .lessThanOrEqual
      case "IN":       self = .in
      case "LIKE", "like": self = .like
      case "ILIKE", "ilike", "caseInsensitiveLike:", "caseInsensitiveLike":
        self = .caseInsensitiveLike
      case "SQLLIKE":  self = .SQLLike
      case "SQLILIKE": self = .SQLCaseInsensitiveLike
      default:         self = .other(string)
    }
  }
  @inlinable
  var stringRepresentation : String {
    switch self {
      case .other(let s):           return s
      case .equalTo:                return "="
      case .notEqualTo:             return "!="
      case .greaterThan:            return ">"
      case .greaterThanOrEqual:     return ">="
      case .lessThan:               return "<"
      case .lessThanOrEqual:        return "<="
      case .in:                     return "IN"
      case .like:                   return "LIKE"
      case .caseInsensitiveLike:    return "ILIKE"
      case .SQLLike:                return "SQLLIKE"
      case .SQLCaseInsensitiveLike: return "SQLILIKE"
    }
  }
}

extension ComparisonOperation: SmartDescription {
  
  @inlinable
  public var description: String { return stringRepresentation }

  @inlinable
  public func appendToDescription(_ ms: inout String) {
    ms += " "
    ms += stringRepresentation
  }
}

public extension ComparisonOperation {
  // TODO: Evaluation is a "little" harder in Swift, also coercion
  // Note: Had this as KeyValueQualifier<T>, but this makes class-checks harder.
  //       Not sure what the best Swift approach would be to avoid the Any

  @inlinable
  func compare(_ a: Any?, _ b: Any?) -> Bool {
    // Everytime you compare an Any, a 🐄 dies.
    switch self {
      case .equalTo:            return eq(a, b)
      case .notEqualTo:         return !eq(a, b)
      case .lessThan:           return isSmaller(a, b)
      case .greaterThan:        return isSmaller(b, a)
      case .lessThanOrEqual:    return isSmaller(a, b) || eq(a, b)
      case .greaterThanOrEqual: return isSmaller(b, a) || eq(a, b)
      
      case .in: // firstname in ["donald"] or firstname in "donald"
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
      
      case .like, .caseInsensitiveLike: // firstname like *Donald*
        let ci = self == .caseInsensitiveLike
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

#if swift(>=5.5)
extension ComparisonOperation: Sendable {}
#endif
