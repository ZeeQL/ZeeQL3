//
//  GlobalID.swift
//  ZeeQL
//
//  Created by Helge Hess on 17/02/17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

open class GlobalID : EquatableType, Hashable {
  // Note: cannot be a protocol because Hashable (because Equatable)
  
  public func isEqual(to object: Any?) -> Bool {
    guard let gid = object as? GlobalID else { return false }
    return gid === self
  }
  
  public func hash(into hasher: inout Hasher) {
    // well, what?? :-)
  }
  
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
public class KeyGlobalID : GlobalID {
  
  public let entityName : String
  
  public init(entityName: String) {
    self.entityName = entityName
  }
  
  public var keyCount : Int { return 0 }
  
  public subscript(i: Int) -> Any? { return nil }

  static func make(entityName: String, values: [ Any? ]) -> KeyGlobalID {
    if values.count == 1, let i = values[0] as? Int {
      return SingleIntKeyGlobalID(entityName: entityName, value: i)
    }
    return ComplexKeyGlobalID(entityName: entityName, values: values)
  }
}

public class ComplexKeyGlobalID : KeyGlobalID {
  // TODO: FIXME: Any? should be EquatableType?
  
  public let values : [ Any? ]
  
  public init(entityName: String, values: [ Any? ]) {
    assert(values.count > 0, "a key needs to have at least one value ...")
    self.values = values
    super.init(entityName: entityName)
  }
  
  override public var keyCount : Int { return values.count }
  
  override public subscript(i: Int) -> Any? {
    guard i < values.count else { return nil }
    return values[i]
  }
  
  override public func hash(into hasher: inout Hasher) {
    entityName.hash(into: &hasher)
    String(describing: values[0]).hash(into: &hasher)
  }
  
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

public class SingleIntKeyGlobalID : KeyGlobalID {
  
  public let value : Int
  
  public init(entityName: String, value: Int) {
    self.value = value
    super.init(entityName: entityName)
  }

  override public var keyCount : Int { return 1 }

  override public subscript(i: Int) -> Any? {
    guard i == 0 else { return nil }
    return value
  }
  
  override public func hash(into hasher: inout Hasher) {
    entityName.hash(into: &hasher)
    value     .hash(into: &hasher)
  }
  
  override public func isEqual(to object: Any?) -> Bool {
    // TODO: compare against ComplexKeyGlobalID
    guard let gid = object as? SingleIntKeyGlobalID else { return false }
    return value == gid.value && entityName == gid.entityName
  }
}
