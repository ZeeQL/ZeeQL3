//
//  Created by Helge Heß.
//  Copyright © 2023-2025 ZeeZide GmbH.
//

/**
 * An internal type eraser for the `Optional` enum.
 *
 * Note that `Optional` is not a protocol, so `any Optional` doesn't fly.
 *
 * To check whether a type is an optional type:
 * ```swift
 * Int.self  is any AnyOptional.Type // false
 * Int?.self is any AnyOptional.Type // true
 * ```
 */
public protocol AnyOptional<Wrapped> {
  
  associatedtype Wrapped
  
  /// Returns `true` if the optional has a value attached, i.e. is not `nil`
  var isSome : Bool { get }
  
  /// Returns the attached value as an `Wrapped`, or `nil`.
  var value  : Wrapped? { get }
  
  /// Returns the dynamic type of the `Wrapped` value of the optional.
  static var wrappedType : Wrapped.Type { get }
  
  static var noneValue : Self { get }
}

extension Optional : AnyOptional {

  @inlinable
  public static var noneValue : Self { .none }

  @inlinable
  public var isSome : Bool {
    switch self {
      case .none: return false
      case .some: return true
    }
  }
  
  @inlinable
  public var value : Wrapped? {
    switch self {
      case .none: nil
      case .some(let unwrapped): unwrapped
    }
  }
  
  @inlinable
  public static var wrappedType : Wrapped.Type { Wrapped.self }
}
