//
//  AdaptorQueryColumnRepresentable.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.05.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol AdaptorQueryColumnRepresentable {

  static func fromAdaptorQueryValue(_ value: Any?) throws -> Self
  
}

enum AdaptorQueryTypeError : Swift.Error {
  case NullInNonOptionalType(Any.Type)
  case CannotConvertValue(Any.Type, Any)
}

extension String : AdaptorQueryColumnRepresentable {
  
  public static func fromAdaptorQueryValue(_ value: Any?) throws -> String {
    guard let value = value
     else {
      throw AdaptorQueryTypeError.NullInNonOptionalType(String.self)
    }

    if let value = value as? String { return value }
    return "\(value)"
  }

}
extension Int : AdaptorQueryColumnRepresentable {

  public static func fromAdaptorQueryValue(_ value: Any?) throws -> Int {
    guard let value = value
     else {
      throw AdaptorQueryTypeError.NullInNonOptionalType(Int.self)
    }
    switch value {
      case let typedValue as Int:    return typedValue
      case let typedValue as Int64:  return Int(typedValue)
      case let typedValue as Int32:  return Int(typedValue)
      case let typedValue as String:
        guard let i = Int(typedValue)
         else {
          throw AdaptorQueryTypeError.CannotConvertValue(Int.self, value)
         }
        return i
      default:
        // ERROR: VALUE: 9999 Int32
        globalZeeQLLogger.error("VALUE: \(value) \(type(of: value))")
        throw AdaptorQueryTypeError.CannotConvertValue(Int.self, value)
    }
  }
}

extension Optional where Wrapped : AdaptorQueryColumnRepresentable {
  // this is not picked
  // For this: you’ll need conditional conformance. Swift 4, hopefully

  public static func fromAdaptorQueryValue(_ value: Any?) throws
                     -> Optional<Wrapped>
  {
    guard let value = value else { return .none }
    return try Wrapped.fromAdaptorQueryValue(value)
  }
  
}

extension Optional : AdaptorQueryColumnRepresentable {
  
  public static func fromAdaptorQueryValue(_ value: Any?) throws
                     -> Optional<Wrapped>
  {
    guard let value = value else { return .none }
    
    guard let c = Wrapped.self as? AdaptorQueryColumnRepresentable.Type
     else {
      throw AdaptorQueryTypeError.CannotConvertValue(Int.self, value)
     }
    
    return try c.fromAdaptorQueryValue(value) as? Wrapped
  }
  
}
