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

public func eq<T: Equatable>(_ a: T?, _ b: T?) -> Bool {
  if let a = a, let b = b {
    return a == b
  }
  else {
    return a == nil && b == nil
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


// MARK: - Implementations

// TBD: is there a betta way? :-)

extension FixedWidthInteger {
  public func isEqual(to object: Any?) -> Bool {
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
}

extension Int    : EquatableType {}
extension Int8   : EquatableType {}
extension Int32  : EquatableType {}
extension Int64  : EquatableType {}
extension UInt   : EquatableType {}
extension UInt8  : EquatableType {}
extension UInt32 : EquatableType {}
extension UInt64 : EquatableType {}

extension Float : EquatableType {
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Float else { return false }
    return self == v
  }
}
extension Double : EquatableType {
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Double else { return false }
    return self == v
  }
}

extension String : EquatableType {
  public  func isEqual(to object: Any?) -> Bool {
    guard let object = object else { return false } // other is nil
    switch object {
      case let other as String:    return self == other
      case let other as Substring: return self == other
      default: return false
    }
  }
}

extension Bool : EquatableType {
  public func isEqual(to object: Any?) -> Bool {
    guard let v = object as? Bool else { return false }
    return self == v
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
