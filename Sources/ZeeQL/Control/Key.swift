//
//  Key.swift
//  ZeeQL
//
//  Created by Helge Hess on 15/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol Key : Expression, ExpressionEvaluation, EquatableType,
                      CustomStringConvertible
{
  
  var key : String { get }
  
  // MARK: - building keys
  
  func append(_ key: Key) -> Key
}

public extension Key {
  
  // MARK: - value
  
  public func rawValue(in object: Any?) -> Any? {
    guard let object = object else { return nil }
    return KeyValueCoding.value(forKeyPath: key, inObject: object)
  }

  public func valueFor(object: Any?) -> Any? {
    return rawValue(in: object)
  }
  
  
  // TODO: Add convenience methods

  
  // MARK: - Equality
  
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Key else { return false }
    return self.key == other.key // Hm.
  }
  
  
  // MARK: - building keys
  
  public func append(_ key: Key) -> Key {
    return KeyPath(self, key)
  }
  
  public func append(_ key: String) -> Key {
    return append(StringKey(key))
  }
  public func dot(_ key: Key) -> Key {
    return KeyPath(self, key)
  }
  public func dot(_ key: String) -> Key { // Key("persons").dot("name")
    return append(StringKey(key))
  }
}

public struct StringKey : Key, Equatable {

  public let key : String
  
  public init(_ key: String) {
    self.key = key
  }

  public static func ==(lhs: StringKey, rhs: StringKey) -> Bool {
    return lhs.key == rhs.key
  }
  
}

public struct KeyPath : Key, Equatable {
  
  public var keys : [ Key ]
  public var key  : String { return keys.map { $0.key }.joined(separator: ".") }
  
  public init(_ keys: Key...) {
    self.keys = keys
  }
  public init(keys: Key...) {
    self.keys = keys
  }
  
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
  public var description : String {
    return "<Key: \(key)>"
  }
}

extension StringKey : ExpressibleByStringLiteral {

  public init(stringLiteral value: String) {
    self.key = value
  }
  
  public init(extendedGraphemeClusterLiteral value: StringLiteralType) {
    self.key = value
  }
  
  public init(unicodeScalarLiteral value: StringLiteralType) {
    self.key = value
  }
  
}
