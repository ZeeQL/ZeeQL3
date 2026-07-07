//
//  AttributeValue.swift
//  ZeeQL3
//
//  Created by Helge Heß on 13.09.19.
//  Copyright © 2019-2026 ZeeZide GmbH. All rights reserved.
//

#if canImport(Foundation)
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.Decimal
#endif

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

  @inlinable
  static var isOptional : Bool { return false }
  @inlinable
  static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return false
  }
  
  @inlinable
  static var optionalBaseType : AttributeValue.Type? { return nil }
  @inlinable
  static var optionalType     : AttributeValue.Type? { return nil }
  
  // TBD: do we even need this?
  @inlinable
  var optionalBaseType : Any.Type? { return type(of: self).optionalBaseType }
}


extension Optional : AttributeValue {

  @inlinable
  public static var isOptional : Bool { return true }

  @inlinable
  public static var optionalBaseType : AttributeValue.Type? {
    return Wrapped.self as? AttributeValue.Type
  }
  @inlinable
  public static var optionalType : AttributeValue.Type? { return self }
}

extension String : AttributeValue {

  @inlinable
  public static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return true
  }
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<String>.self
  }
}

extension Int     : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int>.self
  }
}
extension Int8    : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int8>.self
  }
}
extension Int16   : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int16>.self
  }
}
extension Int32   : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int32>.self
  }
}
extension Int64   : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Int64>.self
  }
}

extension UInt    : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt>.self
  }
}
extension UInt8   : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt8>.self
  }
}
extension UInt16  : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt16>.self
  }
}
extension UInt32  : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt32>.self
  }
}
extension UInt64  : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<UInt64>.self
  }
}

extension Float   : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
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
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Bool>.self
  }
}

#if canImport(Foundation)
extension Data   : AttributeValue {
  @inlinable
  public static func shouldUseBindVariable(for attribute: Attribute) -> Bool {
    return true
  }
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Data>.self
  }
}

extension Date    : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Date>.self
  }
}
extension URL     : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<URL>.self
  }
}
extension Decimal : AttributeValue {
  @inlinable
  public static var optionalBaseType : AttributeValue.Type? { return self }
  @inlinable
  public static var optionalType     : AttributeValue.Type? {
    return Optional<Decimal>.self
  }
}
  }
  public static var optionalType : AttributeValue.Type? { return self }
}
#endif
