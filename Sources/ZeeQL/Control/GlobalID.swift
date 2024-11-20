//
//  GlobalID.swift
//  ZeeQL
//
//  Created by Helge Hess on 17/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

#if !GLOBALID_AS_OPEN_CLASS

import Foundation

// For ZeeQL we only really need this.
// Avoid the overdesign of arbitrary GIDs. At least for now.
// This could also be a protocol, but again, this just overcomplicates the thing
// and right now we only really need KeyGlobalID's for ZeeQL.
public typealias GlobalID = KeyGlobalID

public typealias SingleIntKeyGlobalID = KeyGlobalID // compact to object version

public struct KeyGlobalID: Hashable, @unchecked Sendable {
  // unchecked Sendable for AnyHashable, but those will only contain base types.
  
  public enum Value: Hashable {
    // This is a little more complicated than it seems, because values may be
    // `nil`. Consider this: `id INTEGER NULL PRIMARY KEY`.
    // The `[AnyHashable?]` `init` actually normalizes those values.,
    // careful w/ assigning such manually.
    
    case int      (Int)
    case string   (String)
    case uuid     (UUID)
    case singleNil
    
    case values([ AnyHashable? ]) // TBD: issue for Sendable
      // maybe this should be `any Hashable & Sendable`, but restricts Swift
      // version.
    
    @inlinable
    public var count: Int {
      switch self {
        case .int, .string, .uuid, .singleNil: return 1
        case .values(let values): return values.count
      }
    }
    
    @inlinable // legacy
    public var keyCount: Int { return count }
    
    @inlinable
    public subscript(i: Int) -> Any? {
      guard i >= 0 && i < count else { return nil }
      switch self {
        case .singleNil             : return Optional.none // vs `nil`?
        case .int      (let value)  : return value
        case .string   (let value)  : return value
        case .uuid     (let value)  : return value
        case .values   (let values) : return values[i]
      }
    }
  }
  
  public let entityName : String
  public let value      : Value

  @inlinable
  public var count: Int { return value.count }
  @inlinable // legacy
  public var keyCount: Int { return count }

  @inlinable
  public subscript(i: Int) -> Any? { return value[i] }
}

public extension KeyGlobalID.Value { // Initializers and Factory

  @inlinable
  init(_ values: [ AnyHashable? ]) {
    if values.count == 1, let opt = values.first {
      if let v = opt {
        switch v { // TBD: `as any BinaryInteger`, but requires 5.5+?
          case let v as Int    : self = .int(v)
          case let v as Int64  : self = .int(Int(v))
          case let v as Int32  : self = .int(Int(v))
          case let v as UInt32 : self = .int(Int(v)) // assumes 64-bit
          case let v as String : self = .string(v)
          case let v as UUID   : self = .uuid(v)
          default:
            assert(!(v.base is any BinaryInteger), "Unexpected BinaryInteger")
            self = .values(values)
        }
      }
      else {
        self = .singleNil
      }
    }
    else { self = .values(values) }
  }
}

public extension KeyGlobalID { // Initializers and Factory
  
  @inlinable
  init<I: BinaryInteger>(entityName: String, value: I) {
    self.entityName = entityName
    self.value = .int(Int(value))
  }
  @inlinable
  init(entityName: String, value: String) {
    self.entityName = entityName
    self.value = .string(value)
  }
  @inlinable
  init(entityName: String, value: UUID) {
    self.entityName = entityName
    self.value = .uuid(value)
  }
  
  @inlinable
  init(entityName: String, values: [ AnyHashable? ]) {
    self.entityName = entityName
    self.value      = Value(values)
  }

  @inlinable // legacy
  static func make(entityName: String, values: [ Any? ]) -> KeyGlobalID
  {
    if values.isEmpty { return KeyGlobalID(entityName: entityName, values: []) }

    if values.count == 1, let opt = values.first {
      if let v = opt {
        switch v { // TBD: `as any BinaryInteger`, but requires 5.5+?
          case let v as Int    :
            return KeyGlobalID(entityName: entityName, value: v)
          case let v as Int64  :
            return KeyGlobalID(entityName: entityName, value: Int(v))
          case let v as Int32  :
            return KeyGlobalID(entityName: entityName, value: Int(v))
          case let v as UInt32 :
            return KeyGlobalID(entityName: entityName, value: Int(v)) // assumes 64-bit
          case let v as String :
            return KeyGlobalID(entityName: entityName, value: v)
          case let v as UUID   :
            return KeyGlobalID(entityName: entityName, value: v)
          default:
            assert(!(v is any BinaryInteger), "Unexpected BinaryInteger")
            assertionFailure("Custom key value type, add explicit check")
            if let v = v as? AnyHashable {
              return KeyGlobalID(entityName: entityName, values: [ v ])
            }
            fatalError("Unsupported key type \(type(of: v))")
        }
      }
      else {
        return KeyGlobalID(entityName: entityName,
                           values: [ Optional<AnyHashable>.none ])
      }
    }
    let hashables : [ AnyHashable? ] = values.compactMap {
      guard let value = $0 else { return nil }
      guard let h = value as? any Hashable else {
        fatalError("Key value must be Hashable \(entityName) \(values)")
      }
      return AnyHashable(h)
    }
    assert(hashables.count == values.count)
    return KeyGlobalID(entityName: entityName, values: hashables)
  }
}

extension KeyGlobalID: EquatableType {
  
  @inlinable
  public func isEqual(to other: Any?) -> Bool {
    return self == (other as? GlobalID)
  }
  @inlinable
  public func isEqual(to other: Self) -> Bool { self == other }
}

extension KeyGlobalID: CustomStringConvertible {
  
  public var description: String {
    var ms = "<GID: \(entityName)"
    switch value {
      case .int   (let value)  : ms += " \(value)"
      case .string(let value)  : ms += " \(value)"
      case .uuid  (let value)  : ms += " \(value.uuidString)"
      case .singleNil          : ms += " <nil>"
      case .values(let values) :
        for value in values {
          if let value = value { ms += " \(value)"  }
          else                 { ms += " <nil>"     }
        }
    }
    ms += ">"
    return ms
  }
}

#else // GLOBALID_AS_OPEN_CLASS

open class GlobalID : EquatableType, Hashable {
  // Note: cannot be a protocol because Hashable (because Equatable)
  // hh(2024-11-19):
  // Explanation: This is often used as a key. And Equality does NOT depend on
  // the type, e.g. a `ComplexKeyGlobalID<[Int]>` can match
  // `SingleIntKeyGlobalID`
  // - In modern Swift it can? Even in old using AnyHashable?
  
  public init() {}
  
  open func isEqual(to object: Any?) -> Bool {
    guard let gid = object as? GlobalID else { return false }
    return gid === self
  }
  
  @inlinable
  open func hash(into hasher: inout Hasher) {
    // well, what?? :-)
  }
  
  @inlinable
  public static func ==(lhs: GlobalID, rhs: GlobalID) -> Bool {
    return lhs.isEqual(to: rhs)
  }
}

/**
 * This GlobalID class is usually used to represent primary keys in a database
 * context. It contains the name of the entity (the database table) plus the
 * values which make up the key. Note that the ordering of the values is
 * important and must be preserved for proper matching.
 *
 * Note: this is an abstract class, when building new keys using
 * globalIDWithEntityName(), you will get private subclasses.
 */
public class KeyGlobalID : GlobalID, CustomStringConvertible {
  
  public let entityName : String
  
  @inlinable
  public init(entityName: String) {
    self.entityName = entityName
  }
  
  @inlinable
  open var keyCount : Int { return 0 }
  
  @inlinable
  open subscript(i: Int) -> Any? { return nil }

  static func make(entityName: String, values: [ Any? ]) -> KeyGlobalID {
    if values.count == 1, let v = values.first {
      switch v {
        case let i as Int:
          return SingleIntKeyGlobalID(entityName: entityName, value: i)
        case let i as Int64:
          return SingleIntKeyGlobalID(entityName: entityName, value: Int(i))
        case let i as Int32:
          return SingleIntKeyGlobalID(entityName: entityName, value: Int(i))
        case let i as UInt32: // assumes 64-bit
          return SingleIntKeyGlobalID(entityName: entityName, value: Int(i))
        default:
          break
      }
    }
    return ComplexKeyGlobalID(entityName: entityName, values: values)
  }

  public var description: String {
    var ms = "<GID: \(entityName)"
    for i in 0..<keyCount {
      if let v = self[i] { ms += " \(v)"  }
      else               { ms += " <nil>" }
    }
    ms += ">"
    return ms
  }
}

public final class ComplexKeyGlobalID : KeyGlobalID {
  // TODO: FIXME: Any? should be EquatableType?
  
  public let values : [ Any? ]
  
  public init(entityName: String, values: [ Any? ]) {
    assert(values.count > 0, "a key needs to have at least one value ...")
    self.values = values
    super.init(entityName: entityName)
  }
  
  @inlinable
  override public var keyCount : Int { return values.count }
  
  @inlinable
  override public subscript(i: Int) -> Any? {
    guard i < values.count else { return nil }
    return values[i]
  }
  
  @inlinable
  override public func hash(into hasher: inout Hasher) {
    entityName.hash(into: &hasher)
    String(describing: values[0]).hash(into: &hasher)
  }
  
  @inlinable
  override public func isEqual(to object: Any?) -> Bool {
    // TODO: compare against SingleIntKeyGlobalID
    guard let gid = object as? ComplexKeyGlobalID else { return false }
    guard gid.values.count == values.count else { return false }
    for i in 0..<values.count {
      // very nice, how to do this ...
      let a = values[i] as EquatableType
      if !a.isEqual(to: gid.values[i]) { return false }
    }
    return entityName == gid.entityName
  }
}

public final class SingleIntKeyGlobalID : KeyGlobalID {
  
  public let value : Int
  
  @inlinable
  public init(entityName: String, value: Int) {
    self.value = value
    super.init(entityName: entityName)
  }

  @inlinable
  override public var keyCount : Int { return 1 }

  @inlinable
  override public subscript(i: Int) -> Any? {
    guard i == 0 else { return nil }
    return value
  }
  
  @inlinable
  override public func hash(into hasher: inout Hasher) {
    entityName.hash(into: &hasher)
    value     .hash(into: &hasher)
  }
  
  @inlinable
  override public func isEqual(to object: Any?) -> Bool {
    guard let gid = object as? SingleIntKeyGlobalID else {
      if let complex = object as? ComplexKeyGlobalID {
        return complex.isEqual(to: self)
      }
      return false
    }
    return value == gid.value && entityName == gid.entityName
  }

  override public var description: String {
    return "<GIDi: \(entityName) \(value)>"
  }
}

#endif // GLOBALID_AS_OPEN_CLASS
