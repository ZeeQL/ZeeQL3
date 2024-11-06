//
//  Key.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * The `Key` protocol represents "keys" within qualifiers, like the left
 * and right side of a ``KeyComparisonQualifier``.
 *
 * ``Attribute`` names, or directly ``Attribute``'s, or a ``KeyPath``.
 *
 * It has two main things:
 * - ``key``: The key in the model, usually the name of an attribute,
 *            but a `.` separated keypath for ``KeyPath`` keys.
 * - ``append``: A method to form KeyPath'es (like `person.home.street`).
 *
 * Implementors:
 * - ``StringKey``    (just wraps the plain string)
 * - ``AttributeKey`` (has direct reference to the ``Attribute``)
 * - ``KeyPath``
 */
public protocol Key : Expression, ExpressionEvaluation, EquatableType,
                      CustomStringConvertible
{
  
  var key : String { get }
  
  // MARK: - building keys
  
  func append(_ key: Key) -> Key
}

public extension Key {
  
  // MARK: - value
  
  func rawValue(in object: Any?) -> Any? {
    guard let object = object else { return nil }
    return KeyValueCoding.value(forKeyPath: key, inObject: object)
  }

  func valueFor(object: Any?) -> Any? {
    return rawValue(in: object)
  }
  
  
  // TODO: Add convenience methods

  
  // MARK: - Equality
  
  func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Key else { return false }
    return self.key == other.key // Hm.
  }
  
  
  // MARK: - building keys
  
  func append(_ key: Key)    -> Key { return KeyPath(self, key)     }
  func append(_ key: String) -> Key { return append(StringKey(key)) }
  func dot   (_ key: Key)    -> Key { return KeyPath(self, key)     }
  func dot(_ key: String) -> Key { // Key("persons").dot("name")
    return append(StringKey(key))
  }
}

public struct StringKey : Key, Equatable {

  public let key : String

  @inlinable
  public init(_ key: String) { self.key = key }

  @inlinable
  public static func ==(lhs: StringKey, rhs: StringKey) -> Bool {
    return lhs.key == rhs.key
  }
}

public struct KeyPath : Key, Equatable {
  
  public var keys : [ Key ]
  
  /// Combines the keys into a `.` separated KeyPath.
  @inlinable
  public var key  : String { return keys.map { $0.key }.joined(separator: ".") }
  
  @inlinable
  public init(_ keys: Key...) { self.keys = keys }
  @inlinable
  public init(keys: Key...)   { self.keys = keys }
  
  @inlinable
  public static func ==(lhs: KeyPath, rhs: KeyPath) -> Bool {
    // TODO: just compare the arrays
    guard lhs.keys.count == rhs.keys.count else { return false }
    return lhs.key == rhs.key
  }

  public var description : String {
    return "<KeyPath: \(key)>"
  }
}

public extension Key {
  var description : String { return "<Key: \(key)>" }
}

extension StringKey : ExpressibleByStringLiteral {

  @inlinable
  public init(stringLiteral value: String) {
    self.key = value
  }
  
  @inlinable
  public init(extendedGraphemeClusterLiteral value: StringLiteralType) {
    self.key = value
  }
  
  @inlinable
  public init(unicodeScalarLiteral value: StringLiteralType) {
    self.key = value
  }
}
