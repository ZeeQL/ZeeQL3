//
//  GlobalID.swift
//  ZeeQL
//
//  Created by Helge Hess on 17/02/17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

open class GlobalID : EquatableType, Hashable {
  // Note: cannot be a protocol because Hashable (because Equatable)
  
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

