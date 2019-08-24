//
//  EquatableType.swift
//  ZeeQL
//
//  Created by Helge Heß on 17.02.17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
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


public func eq<T: Equatable>(_ a: T?, _ b: T?) -> Bool {
  if let a = a, let b = b {
    return a == b
  }
  else {
    return a == nil && b == nil
  }
}
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

public func eq(_ a: Any?, _ b: Any?) -> Bool {
  if let a = a, let b = b {
    guard let a = a as? EquatableType else { return false }
    return a.isEqual(to: b)
  }
  else {
    return a == nil && b == nil
  }
}
public func isSmaller(_ a: Any?, _ b: Any?) -> Bool {
  if let a = a, let b = b {
    guard let a = a as? ComparableType else { return false }
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
  func isEqual(to object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as Int:    return self == other
      case let other as Int64:  return self == other
      case let other as Int32:  return self == other
      case let other as Int16:  return self == other
      case let other as Int8:   return self == other
      case let other as UInt:   return self == other
      case let other as UInt64: return self == other
      case let other as UInt32: return self == other
      case let other as UInt16: return self == other
      case let other as UInt8:  return self == other
      default: return false
    }
  }
  func isSmaller(than object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as Int:    return self < other
      case let other as Int64:  return self < other
      case let other as Int32:  return self < other
      case let other as Int16:  return self < other
      case let other as Int8:   return self < other
      case let other as UInt:   return self < other
      case let other as UInt64: return self < other
      case let other as UInt32: return self < other
      case let other as UInt16: return self < other
      case let other as UInt8:  return self < other
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
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Float else { return false }
    return self == v
  }
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Float else { return false }
    return self < v
  }
}
extension Double : EquatableType, ComparableType {
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Double else { return false }
    return self == v
  }
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Double else { return false }
    return self < v
  }
}

extension String : EquatableType, ComparableType {
  public func isEqual(to object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as String:    return self == other
      case let other as Substring: return self == other
      default: return false
    }
  }
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
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Bool else { return false }
    return self == v
  }
  public func isSmaller(than object: Any?) -> Bool {
    guard let v = object as? Bool else { return false }
    return self == v ? false : !self
  }
}


// MARK: - Optional Implementation

extension Optional where Wrapped : EquatableType {
  // this is not picked
  // For this: you’ll need conditional conformance. Swift 4, hopefully
  
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
