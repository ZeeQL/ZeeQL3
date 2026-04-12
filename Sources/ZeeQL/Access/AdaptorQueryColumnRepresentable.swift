//
//  AdaptorQueryColumnRepresentable.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

#if canImport(Foundation)
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.TimeInterval
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/**
 * A helper protocol that is used to convert ``AdaptorRecord`` columns into
 * Swift typed values.
 */
public protocol AdaptorQueryColumnRepresentable: Sendable {

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
      case let typedValue as Int32:  return Self(typedValue)
      case let typedValue as Int64:  return Self(typedValue)
      case let typedValue as String:
        guard let i = Int(typedValue) else {
          throw AdaptorQueryTypeError.cannotConvertValue(Self.self, value)
         }
        return Self(i)
      default:
        // ERROR: VALUE: 9999 Int32
        globalZeeQLLogger
          .error("Cannot convert value to Int: \(value) \(type(of: value))")
        throw AdaptorQueryTypeError.cannotConvertValue(Self.self, value)
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

#if canImport(Foundation)
extension Date: AdaptorQueryColumnRepresentable {

  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws -> Date {
    guard let value = value else {
      throw AdaptorQueryTypeError.nullInNonOptionalType(Date.self)
    }
    if let date = value as? Date { return date }

    if #available(macOS 15, iOS 13, *) {
      if let v = value as? any BinaryInteger {
        return Date(timeIntervalSince1970: TimeInterval(v))
      }
      if let v = value as? any BinaryFloatingPoint {
        return Date(timeIntervalSince1970: TimeInterval(v))
      }
    }

    // Fallback for older runtimes
    if let v = value as? Int64 {
      return Date(timeIntervalSince1970: TimeInterval(v))
    }
    if let v = value as? Double {
      return Date(timeIntervalSince1970: v)
    }

    if let s = value as? String {
      if let date = DateParser.parseISO8601(s) { return date }
      throw AdaptorQueryTypeError
        .cannotConvertValue(Date.self, value)
    }

    throw AdaptorQueryTypeError
      .cannotConvertValue(Date.self, value)
  }
}

/**
 * Parses ISO 8601 date strings as commonly returned by SQLite and PostgreSQL
 * text mode.
 *
 * Supported formats:
 * - `"2024-05-08T12:00:00Z"`
 * - `"2024-05-08 12:00:00"`
 * - `"2024-05-08"`
 */
@usableFromInline
internal enum DateParser {

  private static let formats = [ "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S",
                                 "%Y-%m-%d %H:%M:%S",  "%Y-%m-%d" ]

  @usableFromInline
  static func parseISO8601(_ string: String) -> Date? {
    var tm = tm()
    for fmt in formats {
      memset(&tm, 0, MemoryLayout<tm>.size)
      if strptime(string, fmt, &tm) != nil {
        let time = timegm(&tm)
        if time != -1 { return Date(timeIntervalSince1970: TimeInterval(time)) }
      }
    }
    return nil
  }
}

extension Data: AdaptorQueryColumnRepresentable {

  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws -> Data {
    guard let value = value else {
      throw AdaptorQueryTypeError.nullInNonOptionalType(Self.self)
    }
    if let data  = value as? Self       { return data }
    if let bytes = value as? [ UInt8 ]  { return Self(bytes) }
    if let s     = value as? String     { return Self(s.utf8) }
    throw AdaptorQueryTypeError.cannotConvertValue(Self.self, value)
  }
}
#endif // canImport(Foundation)

extension Array: AdaptorQueryColumnRepresentable where Element == UInt8 {

  @inlinable
  public static func fromAdaptorQueryValue(_ value: Any?) throws -> [ UInt8 ] {
    guard let value = value else {
      throw AdaptorQueryTypeError.nullInNonOptionalType([ UInt8 ].self)
    }
    if let bytes = value as? Self { return bytes }
    #if canImport(Foundation)
    if let data = value as? Data { return Self(data) }
    #endif
    if let s = value as? String { return Self(s.utf8) }
    throw AdaptorQueryTypeError.cannotConvertValue([ UInt8 ].self, value)
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
    
    guard let c = Wrapped.self as? AdaptorQueryColumnRepresentable.Type else {
      throw AdaptorQueryTypeError.cannotConvertValue(Int.self, value)
    }
    
    return try c.fromAdaptorQueryValue(value) as? Wrapped
  }
  
}
