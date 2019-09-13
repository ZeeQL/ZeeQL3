//
//  AttributeValue.swift
//  ZeeQL3
//
//  Created by Helge Heß on 13.09.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.Decimal

// marker interface for types that can be used as columns
public protocol AttributeValue {
  
  static var  isOptional : Bool { get }
  
  static func shouldUseBindVariable(for attribute: Attribute) -> Bool
  
  /// Returns the type wrapped by the Optional, e.g. `Int` for `Int?`
  static var optionalBaseType : AttributeValue.Type? { get }
  
  /// Returns an Optional type for the AttributeValue. If it is already an
  /// optional, this is the same. E.g. `Int?` is returned for `Int`
  static var optionalType     : AttributeValue.Type? { get }

  // TBD: static var attributeValueType: Enum
  //        Enum { int(width), float(width), string, url, decimal }
  //               var isStringRepresentable:..,
}

public extension AttributeValue {
  static var isOptional : Bool { return false }
  static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return false
  }
  
  static var optionalBaseType : AttributeValue.Type? { return nil }
  static var optionalType     : AttributeValue.Type? { return nil }
  
  // TBD: do we even need this?
  var optionalBaseType : Any.Type? { return type(of: self).optionalBaseType }
}

extension String : AttributeValue {
  public static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return true
  }
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<String>.self
  }
}
extension Data   : AttributeValue {
  public static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return true
  }
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Data>.self
  }
}

extension Int     : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int>.self
  }
}
extension Int8    : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int8>.self
  }
}
extension Int16   : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int16>.self
  }
}
extension Int32   : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int32>.self
  }
}
extension Int64   : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int64>.self
  }
}

extension UInt    : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt>.self
  }
}
extension UInt8   : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt8>.self
  }
}
extension UInt16  : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt16>.self
  }
}
extension UInt32  : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt32>.self
  }
}
extension UInt64  : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt64>.self
  }
}

extension Float   : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Float>.self
  }
}
extension Double  : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Double>.self
  }
}
extension Bool    : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Bool>.self
  }
}

extension Date    : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Date>.self
  }
}
extension URL     : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<URL>.self
  }
}
extension Decimal : AttributeValue {
  public static var optionalBaseType : AttributeValue.Type? { return self }
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Decimal>.self
  }
}

extension Optional : AttributeValue {
  public static var isOptional : Bool { return true }

  public static var optionalBaseType : AttributeValue.Type? {
    return Wrapped.self as? AttributeValue.Type
  }
  public static var optionalType : AttributeValue.Type? { return self }
}
