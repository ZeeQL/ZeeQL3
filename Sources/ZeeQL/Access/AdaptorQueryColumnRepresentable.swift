//
//  AdaptorQueryColumnRepresentable.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * A helper protocol that is used to convert ``AdaptorRecord`` columns into
 * Swift typed values.
 */
public protocol AdaptorQueryColumnRepresentable {

  static func fromAdaptorQueryValue(_ value: Any?) throws -> Self
}

public enum AdaptorQueryTypeError : Swift.Error {
  case nullInNonOptionalType(Any.Type)
  case cannotConvertValue(Any.Type, Any)
}

extension String : AdaptorQueryColumnRepresentable {
  
  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws -> String {
    guard let value = value else {
      throw AdaptorQueryTypeError.nullInNonOptionalType(String.self)
    }

    if let value = value as? String { return value }
    return "\(value)"
  }

}

extension Int     : AdaptorQueryColumnRepresentable {}
extension Int16   : AdaptorQueryColumnRepresentable {}
extension Int32   : AdaptorQueryColumnRepresentable {}
extension Int64   : AdaptorQueryColumnRepresentable {}
extension UInt    : AdaptorQueryColumnRepresentable {}
extension UInt16  : AdaptorQueryColumnRepresentable {}
extension UInt32  : AdaptorQueryColumnRepresentable {}
extension UInt64  : AdaptorQueryColumnRepresentable {}
#if compiler(>=6)
@available(macOS 15, iOS 13, *)
extension Int128  : AdaptorQueryColumnRepresentable {}
@available(macOS 15, iOS 13, *)
extension UInt128 : AdaptorQueryColumnRepresentable {}
#endif

extension BinaryInteger {

  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws -> Self {
    guard let value = value else {
      throw AdaptorQueryTypeError.nullInNonOptionalType(Int.self)
    }
    
    if let value = value as? Self { return value }
    
    if #available(macOS 15, iOS 13, *) {
      if let value = value as? any BinaryInteger { return Self(value) }
    }
    
    switch value {
      case let typedValue as Int:    return Self(typedValue)
      case let typedValue as Int64:  return Self(typedValue)
      case let typedValue as Int32:  return Self(typedValue)
      case let typedValue as String:
        guard let i = Int(typedValue) else {
          throw AdaptorQueryTypeError.cannotConvertValue(Int.self, value)
         }
        return Self(i)
      default:
        // ERROR: VALUE: 9999 Int32
        globalZeeQLLogger.error("VALUE: \(value) \(type(of: value))")
        throw AdaptorQueryTypeError.cannotConvertValue(Int.self, value)
    }
  }
}

extension Float  : AdaptorQueryColumnRepresentable {}
extension Double : AdaptorQueryColumnRepresentable {}

extension BinaryFloatingPoint {

  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws -> Self {
    guard let value = value else {
      throw AdaptorQueryTypeError.nullInNonOptionalType(Int.self)
    }
    
    if let value = value as? Self { return value }
    
    if #available(macOS 15, iOS 13, *) {
      if let value = value as? any BinaryFloatingPoint { return Self(value) }
      if let value = value as? any BinaryInteger       { return Self(value) }
    }
    
    switch value {
      case let typedValue as Double : return Self(typedValue)
      case let typedValue as Float  : return Self(typedValue)
      case let typedValue as Int    : return Self(typedValue)
      case let typedValue as Int64  : return Self(typedValue)
      case let typedValue as Int32  : return Self(typedValue)
      case let typedValue as String:
        guard let i = Double(typedValue) else {
          throw AdaptorQueryTypeError.cannotConvertValue(Int.self, value)
         }
        return Self(i)
      default:
        // ERROR: VALUE: 9999 Int32
        globalZeeQLLogger.error("VALUE: \(value) \(type(of: value))")
        throw AdaptorQueryTypeError.cannotConvertValue(Int.self, value)
    }
  }
}

extension Optional where Wrapped : AdaptorQueryColumnRepresentable {
  // this is not picked
  // For this: you’ll need conditional conformance. Swift 4, hopefully

  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws
                     -> Optional<Wrapped>
  {
    guard let value = value else { return .none }
    return try Wrapped.fromAdaptorQueryValue(value)
  }
  
}

extension Optional : AdaptorQueryColumnRepresentable {
  
  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws
                     -> Optional<Wrapped>
  {
    guard let value = value else { return .none }
    
    guard let c = Wrapped.self as? AdaptorQueryColumnRepresentable.Type
     else {
      throw AdaptorQueryTypeError.cannotConvertValue(Int.self, value)
     }
    
    return try c.fromAdaptorQueryValue(value) as? Wrapped
  }
  
}
