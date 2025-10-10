//
//  EquatableType.swift
//  ZeeQL
//
//  Created by Helge Heß on 17.02.17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * Dynamic comparison of values. The thing you know from Objective-C or Java ...
 */
public protocol EquatableType {
  func isEqual(to object: Any?) -> Bool
}

/**
* Dynamic comparison of values. The thing you know from Objective-C or Java ...
*/
public protocol ComparableType {
  func isSmaller(than object: Any?) -> Bool
}

/**
* Dynamic comparison of values. The thing you know from Objective-C or Java ...
*/
public protocol ContainsComparisonType {
  func contains(other object: Any?) -> Bool
}
/**
* Dynamic comparison of values. The thing you know from Objective-C or Java ...
*/
public protocol LikeComparisonType {
  func isLike(other object: Any?, caseInsensitive: Bool) -> Bool
}


@inlinable
public func eq<T: Equatable>(_ a: T?, _ b: T?) -> Bool {
  if let a = a, let b = b {
    return a == b
  }
  else {
    return a == nil && b == nil
  }
}
@inlinable
public func isSmaller<T: Comparable>(_ a: T?, _ b: T?) -> Bool {
  if let a = a, let b = b {
    return a < b
  }
  else if a == nil && b == nil {
    return false
  }
  else {
    return a == nil
  }
}

@inlinable
public func eq(_ a: Any?, _ b: Any?) -> Bool {
  if let a = a, let b = b {
    guard let a = a as? EquatableType else {
      #if swift(>=5.5)
      // Unwrapping dance
      func _isEqual<T: Equatable>(lhs: T, rhs: Any) -> Bool {
        guard let rhs = rhs as? T else { return false }
        return lhs == rhs
      }
      guard let lhs = a as? any Equatable else { return false }
      return _isEqual(lhs: lhs, rhs: b)
      #else
      return false
      #endif
    }
    return a.isEqual(to: b)
  }
  else {
    return a == nil && b == nil
  }
}
@inlinable
public func isSmaller(_ a: Any?, _ b: Any?) -> Bool {
  if let a = a, let b = b {
    guard let a = a as? ComparableType else {
      #if swift(>=5.5)
      // Unwrapping dance
      func _isSmaller<T: Comparable>(lhs: T, rhs: Any) -> Bool {
        guard let rhs = rhs as? T else { return false }
        return lhs < rhs
      }
      guard let lhs = a as? any Comparable else { return false }
      return _isSmaller(lhs: lhs, rhs: b)
      #else
      return false
      #endif
    }
    return a.isSmaller(than: b)
  }
  else if a == nil && b == nil {
    return false
  }
  else {
    return a == nil
  }
}


// MARK: - Implementations

// TBD: is there a betta way? :-)

public extension FixedWidthInteger {
  
  @inlinable
  func isEqual(to object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as Int:     return self == other
      case let other as Decimal: return other.isEqual(to: self)
      case let other as Int64:   return self == other
      case let other as Int32:   return self == other
      case let other as Int16:   return self == other
      case let other as Int8:    return self == other
      case let other as UInt:    return self == other
      case let other as UInt64:  return self == other
      case let other as UInt32:  return self == other
      case let other as UInt16:  return self == other
      case let other as UInt8:   return self == other
      default: return false
    }
  }
  
  @inlinable
  func isSmaller(than object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as Int:     return self < other
      case let other as Decimal: return !other.isSmaller(than: self)
      case let other as Int64:   return self < other
      case let other as Int32:   return self < other
      case let other as Int16:   return self < other
      case let other as Int8:    return self < other
      case let other as UInt:    return self < other
      case let other as UInt64:  return self < other
      case let other as UInt32:  return self < other
      case let other as UInt16:  return self < other
      case let other as UInt8:   return self < other
      default: return false
    }
  }
}

extension Int    : EquatableType, ComparableType {}
extension Int8   : EquatableType, ComparableType {}
extension Int32  : EquatableType, ComparableType {}
extension Int64  : EquatableType, ComparableType {}
extension UInt   : EquatableType, ComparableType {}
extension UInt8  : EquatableType, ComparableType {}
extension UInt32 : EquatableType, ComparableType {}
extension UInt64 : EquatableType, ComparableType {}

extension Float : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Float else { return false }
    return self == v
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Float else { return false }
    return self < v
  }
}
extension Double : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Double else { return false }
    return self == v
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Double else { return false }
    return self < v
  }
}

extension String : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as String:    return self == other
      case let other as Substring: return self == other
      default: return false
    }
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as String:    return self < other
      case let other as Substring: return self < other
      default: return false
    }
  }
}

extension Bool : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Bool else { return false }
    return self == v
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Bool else { return false }
    return self == v ? false : !self
  }
}

#if canImport(Foundation)
import struct Foundation.UUID
import struct Foundation.URL
import struct Foundation.Decimal
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.DateComponents

extension Date : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Date else { return false }
    return self == v
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Date else { return false }
    return self < v
  }
}

extension UUID : EquatableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? UUID else { return false }
    return self == v
  }
}
extension URL : EquatableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? URL else { return false }
    return self == v
  }
}
extension Data : EquatableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Data else { return false }
    return self == v
  }
}
extension DateComponents : EquatableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? DateComponents else { return false }
    return self == v
  }
}

import struct Foundation.DateInterval
@available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
extension DateInterval : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? DateInterval else { return false }
    return self == v
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? DateInterval else { return false }
    return self < v
  }
}

import struct Foundation.Measurement
@available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
extension Measurement : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Measurement else { return false }
    return self == v
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Measurement else { return false }
    return self < v
  }
}

import struct Foundation.PersonNameComponents
@available(OSX 10.11, iOS 9.0, *)
extension PersonNameComponents : EquatableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? PersonNameComponents else { return false }
    return self == v
  }
}

extension Decimal : EquatableType, ComparableType {
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    switch object {
      case let other as Decimal: return self == other
      case let other as Int:     return Decimal(other) == self
      case let other as Int64:   return Decimal(other) == self
      case let other as Int32:   return Decimal(other) == self
      case let other as Int16:   return Decimal(other) == self
      case let other as Int8:    return Decimal(other) == self
      case let other as UInt:    return Decimal(other) == self
      case let other as UInt64:  return Decimal(other) == self
      case let other as UInt32:  return Decimal(other) == self
      case let other as UInt16:  return Decimal(other) == self
      case let other as UInt8:   return Decimal(other) == self
      default: return false
    }
  }
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    guard let object = object else { return false }
    switch object {
      case let other as Decimal: return self < other
      case let other as Int:     return self < Decimal(other)
      case let other as Int64:   return self < Decimal(other)
      case let other as Int32:   return self < Decimal(other)
      case let other as Int16:   return self < Decimal(other)
      case let other as Int8:    return self < Decimal(other)
      case let other as UInt:    return self < Decimal(other)
      case let other as UInt64:  return self < Decimal(other)
      case let other as UInt32:  return self < Decimal(other)
      case let other as UInt16:  return self < Decimal(other)
      case let other as UInt8:   return self < Decimal(other)
      default: return false
    }
  }
}
#endif // canImport(Foundation)


// MARK: - Optional Implementation

extension Optional where Wrapped : EquatableType {
  // this is not picked
  // For this: you’ll need conditional conformance. Swift 4, hopefully
  
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    // TBD: do we want to compare optionals against non-optionals? In ObjC we
    //      do, right?
    if let object = object { // other is non-optional
      switch self {
        case .none: return false
        case .some(let value): return value.isEqual(to: object)
      }
    }
    else { // other is nil
      if case .none = self { return true }
      return false
    }
  }
  
}
extension Optional where Wrapped : ComparableType {
  // this is not picked
  // For this: you’ll need conditional conformance. Swift 4, hopefully
  
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    // TBD: do we want to compare optionals against non-optionals? In ObjC we
    //      do, right?
    if let object = object { // other is non-optional
      switch self {
        case .none: return true // we are nil, other not
        case .some(let value): return value.isSmaller(than: object)
      }
    }
    else { // other is nil
      switch self {
        case .none: return true
        case .some: return false // other is nil, hence smaller
      }
    }
  }
  
}

extension Optional : EquatableType {
  
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    // TBD: do we want to compare optionals against non-optionals? In ObjC we
    //      do, right?
    if let object = object { // other is non-optional
      switch self {
        case .none: return false
        case .some(let value):
          if let eqv = value as? EquatableType {
            return eqv.isEqual(to: object)
          }
          else if let eqv = object as? EquatableType {
            return eqv.isEqual(to: value)
          }
          return false
      }
    }
    else { // other is nil
      if case .none = self { return true }
      return false
    }
  }
  
}
extension Optional : ComparableType {
  
  @inlinable
  public func isSmaller(than object: Any?) -> Bool {
    // TBD: do we want to compare optionals against non-optionals? In ObjC we
    //      do, right?
    if let object = object { // other is non-optional
      switch self {
        case .none: return false // nil is smaller than non-nil
        case .some(let value):
          if let eqv = value as? ComparableType {
            return eqv.isSmaller(than: object)
          }
          else if let eqv = object as? ComparableType {
            return eqv.isSmaller(than: value)
          }
          return false
      }
    }
    else { // other is nil
      switch self {
        case .none: return false // both nil
        case .some: return false // other is nil, we are not
      }
    }
  }
  
}

extension Range: EquatableType where Bound : EquatableType {
  // TODO: add containment?
  
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Self else { return false }
    return self == other
  }
}

// MARK: - Containment

public extension Collection where Element : EquatableType {
  @inlinable
  func contains(other object: Any?) -> Bool {
    return contains { $0.isEqual(to: object) }
  }
}
extension Array : ContainsComparisonType where Element : EquatableType {}
extension Range : ContainsComparisonType where Element : EquatableType {}

#if swift(>=5)
  extension Slice : ContainsComparisonType where Element : EquatableType {}
#else
  extension Slice : ContainsComparisonType where Base.Element : EquatableType {}
#endif

public extension StringProtocol {

  @inlinable
  func contains(other object: Any?) -> Bool {
    switch object {
      case .none: return false
      case .some(let v as String):    return contains(v)
      case .some(let v as Substring): return contains(v)
      default:
        return false
    }
  }
  
  @inlinable
  func isLike(other object: Any?, caseInsensitive ci: Bool) -> Bool {
    guard let other = object else { return false } // String not like nil
    if !ci {
      switch other {
        case let other as String:    return self.likePatternMatch(other)
        case let other as Substring: return self.likePatternMatch(other)
        default: return false
      }
    }
    else {
      switch other {
        case let other as String:
          return lowercased().likePatternMatch(other.lowercased())
        case let other as Substring:
          return lowercased().likePatternMatch(other.lowercased())
        default: return false
      }
    }
  }
  
  /// A simple (and incomplete) * pattern matcher.
  /// Can only do prefix/suffix/contains
  @inlinable
  func likePatternMatch<P: StringProtocol>(_ pattern: P) -> Bool {
    guard pattern.contains("*") else { return self == pattern }
    let starPrefix = pattern.hasPrefix("*")
    let starSuffix = pattern.hasSuffix("*")
    if !starPrefix && !starSuffix { return self == pattern }
    if starPrefix {
      let v1 = pattern.dropFirst()
      return starSuffix ? contains(v1.dropLast()) : hasSuffix(v1)
    }
    else if starSuffix {
      return hasPrefix(pattern.dropLast())
    }
    else { // stupid fallback ignoring inner stars
      return self == pattern
    }
  }
}

extension String    : ContainsComparisonType, LikeComparisonType {}
extension Substring : ContainsComparisonType, LikeComparisonType {}
