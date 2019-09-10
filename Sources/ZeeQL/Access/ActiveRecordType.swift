//
//  ActiveRecordType.swift
//  ZeeQL3
//
//  Created by Helge Heß on 03.09.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

/**
 * This type of object tracks the snapshot inside the object itself.
 * Which is different to CD, which tracks the snapshot in the database context.
 * A disadvantage is that we cannot map to POSOs but objects need to be
 * subclasses of ActiveRecord to implement change tracking.
 *
 * See `ActiveRecord` for a concrete implementation of the protocol.
 */
public protocol ActiveRecordType : DatabaseObject,
                                   DatabaseBoundObject, SnapshotHoldingObject,
                                   ObjectWithGlobalID
{
  init()

  static var database : Database? { get }
  
  var database : Database  { get }
  var entity   : Entity    { get }
  var isNew    : Bool      { get }
  
  var values   : [ String : Any ] { get }
  var snapshot : Snapshot?        { get set }
  
  func save()   throws
  func delete() throws
}

public extension ActiveRecordType {
  var globalID: GlobalID? {
    return entity.globalIDForRow(self)
  }
}

public protocol DatabaseBoundObject {
  // TBD: this may be superfluous ...
  
  func bind(to db: Database, entity: Entity?)
  
}

public extension ActiveRecordType { // default imp

  func value(forKey k: String) -> Any? {
    // first check extra properties
    if let v = values[k] { return v }
    
    // then fallback to KVC
    if let v = KeyValueCoding.defaultValue(forKey: k, inObject: self) {
      return v
    }
    
    return nil
  }
  
  
  // MARK: - Convenience Subscripts
  
  subscript(key: String) -> Any? {
    set {
      do {
        if let v = newValue { // hm, necessary?
          try takeValue(v, forKey: key)
        }
        else {
          try takeValue(newValue, forKey: key)
        }
      }
      catch {
        globalZeeQLLogger.warn("attempt to set unbound key:", key,
                               "value:", newValue)
      }
    }
    get {
      return value(forKey: key)
    }
  }
  
  subscript(int key: String) -> Int? {
    guard let v = self[key] else { return nil }
    if let i = v as? Int { return i }
    return Int("\(v)")
  }
  subscript(string key: String) -> String? {
    guard let v = self[key] else { return nil }
    if let i = v as? String { return i }
    return "\(v)"
  }
  
}

#if TBD
public extension ActiveRecordType { // finders
  
  static func findBy<T>(id: T) -> Self? {
    // FIXME: this doesn't invoke the actual type `database` method
    guard let db = Self.database else { return nil }
    
    log.error("DB:", db)
    // TODO: Well, what?
    // - get a datasource for 'Self'
    // - invoke findBy method, return?
    
    return nil
  }
  
}
#endif
