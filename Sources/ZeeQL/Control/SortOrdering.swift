//
//  SortOrdering.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

/**
 * Represents a sort ordering of a key.
 *
 * Note: Be careful with using CompareCaseInsensitiveXYZ against SQL
 *       databases! Some databases cannot use an index for a query if the
 *       WHERE contains UPPER(lastname) like stuff.
 *       Instead you might want to use an Attribute 'writeformat' to
 *       convert values to upper or lowercase on writes.
 */
public struct SortOrdering : Expression, Equatable, EquatableType,
                             SmartDescription
{
  
  public enum Selector : Equatable {

    case CompareAscending
    case CompareDescending
    case CompareCaseInsensitiveAscending
    case CompareCaseInsensitiveDescending
    case Other(String)
    
    var stringRepresentation : String {
      switch self {
        case .CompareAscending:                 return "ASC"
        case .CompareDescending:                return "DESC"
        case .CompareCaseInsensitiveAscending:  return "IASC"
        case .CompareCaseInsensitiveDescending: return "IDESC"
        case .Other(let op):                    return op
      }
    }
    
    public static func ==(lhs: Selector, rhs: Selector) -> Bool {
      switch ( lhs, rhs ) {
        case ( .CompareAscending,  .CompareAscending  ):  return true
        case ( .CompareDescending, .CompareDescending ): return true
        case ( .CompareCaseInsensitiveAscending,
               .CompareCaseInsensitiveAscending  ): return true
        case ( .CompareCaseInsensitiveDescending,
               .CompareCaseInsensitiveDescending ): return true
        case ( .Other(let lhsV), .Other(let rhsV) ): return lhsV == rhsV
        default: return false
      }
    }
  }

  public let keyExpr  : Key
  public let selector : Selector
  
  public var key      : String { return keyExpr.key }
  
  public init(key: String, selector: Selector) {
    self.keyExpr  = StringKey(key)
    self.selector = selector
  }
  public init(key: Key, selector: Selector) {
    self.keyExpr  = key
    self.selector = selector
  }
  
  public func addReferencedKeys(to set: inout Set<String>) {
    set.insert(key)
  }
  
  
  // MARK: - Equatable
  
  public static func ==(lhs: SortOrdering, rhs: SortOrdering) -> Bool {
    guard lhs.key      == rhs.key      else { return false }
    guard lhs.selector == rhs.selector else { return false }
    return true
  }

  public func isEqual(to object: Any?) -> Bool {
    guard let rhs = object as? SortOrdering else { return false }
    return self == rhs
  }
  
  // MARK: - Description
  
  public var stringRepresentation : String {
    return key + " " + selector.stringRepresentation
  }

  public func appendToDescription(_ ms: inout String) {
    ms += " "
    ms += stringRepresentation
  }
}

public extension SortOrdering {
  
  /**
   * Parse orderings from a simple string syntax, e.g.:
   *
   *     name,-balance
   *
   * @param text - the text to parse
   * @return an array of sort orderings
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
        
        let op : Selector = (c0 == "-") ? .CompareDescending : .CompareAscending
        so = SortOrdering(key: String(key), selector: op)
      }
      else {
        so = SortOrdering(key: trimmedPart, selector: .CompareAscending)
      }
      
      orderings.append(so)
    }
    
    return orderings
  }
  
}
