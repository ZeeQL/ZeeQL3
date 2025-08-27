//
//  SortOrdering.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * Represents a sort ordering of a key.
 *
 * Note: Be careful with using .caseInsensitiveXYZ against SQL
 *       databases! Some databases cannot use an index for a query if the
 *       WHERE contains UPPER(lastname) like stuff.
 *       Instead you might want to use an Attribute 'writeformat' to
 *       convert values to upper or lowercase on writes.
 */
public struct SortOrdering : Expression, Equatable, EquatableType,
                             SmartDescription
{
  
  public enum Selector: RawRepresentable, Equatable {

    case ascending
    case descending
    case caseInsensitiveAscending
    case caseInsensitiveDescending
    case other(String)

    // backwards compat
    @available(*, deprecated, message: "Use `.ascending` instead.")
    public static let CompareAscending  = Selector.ascending
    @available(*, deprecated, message: "Use `.descending` instead.")
    public static let CompareDescending = Selector.descending
    @available(*, deprecated,
                message: "Use `.caseInsensitiveAscending` instead.")
    public static let CompareCaseInsensitiveAscending =
                        Selector.caseInsensitiveAscending
    @available(*, deprecated,
                message: "Use `.caseInsensitiveDescending` instead.")
    public static let CompareCaseInsensitiveDescending =
                        Selector.caseInsensitiveDescending
    @available(*, deprecated, message: "Use `.other(value)` instead.")
    @inlinable
    public static func Other(_ value: String) -> Selector { .other(value) }

    @inlinable
    public init(rawValue: String) {
      switch rawValue.uppercased() {
        case "ASC"                : self = .ascending
        case "DESC"               : self = .descending
        case "CASE ASC",  "IASC"  : self = .caseInsensitiveAscending
        case "CASE DESC", "IDESC" : self = .caseInsensitiveDescending
        default                   : self = .other(rawValue)
      }
    }
    
    @inlinable
    public var rawValue : String {
      switch self {
        case .ascending:                 return "ASC"
        case .descending:                return "DESC"
        case .caseInsensitiveAscending:  return "IASC"
        case .caseInsensitiveDescending: return "IDESC"
        case .other(let op):             return op
      }
    }
    @inlinable
    public var stringRepresentation : String { rawValue }

    @inlinable
    public static func ==(lhs: Selector, rhs: Selector) -> Bool {
      switch ( lhs, rhs ) {
        case ( .ascending,  .ascending  ):  return true
        case ( .descending, .descending ): return true
        case ( .caseInsensitiveAscending,
               .caseInsensitiveAscending  ): return true
        case ( .caseInsensitiveDescending,
               .caseInsensitiveDescending ): return true
        case ( .other(let lhsV), .other(let rhsV) ): return lhsV == rhsV
        default: return false
      }
    }
  }

  public let keyExpr  : Key
  public let selector : Selector
  
  @inlinable
  public var key      : String { return keyExpr.key }
  
  @inlinable
  public init(key: String, selector: Selector) {
    self.keyExpr  = StringKey(key)
    self.selector = selector
  }
  @inlinable
  public init(key: Key, selector: Selector) {
    self.keyExpr  = key
    self.selector = selector
  }
  
  @inlinable
  public func addReferencedKeys(to set: inout Set<String>) {
    set.insert(key)
  }
  
  
  // MARK: - Equatable
  
  @inlinable
  public static func ==(lhs: SortOrdering, rhs: SortOrdering) -> Bool {
    return lhs.key == rhs.key &&  lhs.selector == rhs.selector
  }

  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let rhs = object as? SortOrdering else { return false }
    return self == rhs
  }
  
  // MARK: - Description
  
  @inlinable
  public var stringRepresentation : String {
    return key + " " + selector.stringRepresentation
  }

  @inlinable
  public func appendToDescription(_ ms: inout String) {
    ms += " "
    ms += stringRepresentation
  }
}

public extension SortOrdering {
  
  /**
   * Parse orderings from a simple string syntax, e.g.:
   * ```
   * name,-balance
   * ```
   *
   * - Parameters:
   *   - text:  The string to parse
   * - Returns: An array of ``SortOrdering``'s, or nil
   */
  static func parse(_ text: String) -> [ SortOrdering ]? {
    guard !text.isEmpty else { return nil }
    
    let parts     = text.components(separatedBy: ",")
    var orderings = [ SortOrdering ]()
    orderings.reserveCapacity(parts.count)
    
    for part in parts {
      let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedPart.isEmpty else { continue }
      let idx = trimmedPart.startIndex
      let c0 = trimmedPart[idx]
      let so : SortOrdering
      if (c0 == "+" || c0 == "-") && trimmedPart.count > 1 {
        let key =
          trimmedPart[trimmedPart.index(after: idx)..<trimmedPart.endIndex]
        
        let op : Selector = (c0 == "-") ? .descending : .ascending
        so = SortOrdering(key: String(key), selector: op)
      }
      else {
        so = SortOrdering(key: trimmedPart, selector: .ascending)
      }
      
      orderings.append(so)
    }
    
    return orderings
  }
  
}
