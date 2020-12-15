//
//  Database.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017-2020 ZeeZide GmbH. All rights reserved.
//

/**
 * The database wraps an Adaptor and acts as a central entry point for
 * ORM based access to the database. That is, to database rows represented
 * as objects (e.g. subclasses of ActiveRecord).
 *
 * You usually aquire an ActiveDataSource from the central Database
 * object and then use that to perform queries against a specific table.
 *
 * Example:
 *
 *     let db = Database(adaptor)
 *     let ds = db.dataSourceForEntity("person")
 *     let donald = 
 *           ds.findByMatchingAll("lastname", "Duck", "firstname", "Donald")
 *
 */
open class Database : EquatableType, Equatable {
  
  open   var log               : ZeeQLLogger = globalZeeQLLogger
  public let adaptor           : Adaptor
  public let typeLookupContext : ObjectTypeLookupContext?
  
  @inlinable
  public init(adaptor: Adaptor, objectTypes: ObjectTypeLookupContext? = nil) {
    self.adaptor           = adaptor
    self.typeLookupContext = objectTypes
  }
  
  @inlinable
  public var model : Model? { return adaptor.model }
  
  // TODO
  
  @inlinable
  public subscript(entity n: String) -> Entity? {
    return model?[entity:n ]
  }

  /**
   * Returns the Entity object associated with a given object. If the object
   * is an instance of ActiveRecord, the record itself will be asked. If it
   * isn't (eg a POSO), the model will be asked whether one of the entities is
   * mapped to the given object.
   */
  @inlinable
  func entityForObject(_ object: Any?) -> Entity? {
    guard let object = object else { return nil }
    
    if let ar = object as? ActiveRecordType { return ar.entity }
    
    guard let model = model else { return nil }
    return model.entityForObject(object)
  }
  
  @inlinable
  func classForEntity(_ entity: Entity?) -> DatabaseObject.Type? {
    if let t = entity?.objectType { return t }
    
    if let n = entity?.className, let ctx = typeLookupContext {
      return ctx.lookupObjectType(name: n)
    }
    
    return nil
  }
  
  
  // MARK: - Operations
  
  @inlinable
  public func performDatabaseOperation(_ op: DatabaseOperation) throws {
    let channel = DatabaseChannel(database: self)
    try channel.performDatabaseOperations([ op ])
  }
  
  /**
   * Performs the set of database operations in a single database transaction.
   */
  @inlinable
  public func performDatabaseOperations(_ ops: [ DatabaseOperation ]) throws {
    guard !ops.isEmpty else { return } /* nothing to do */
    
    let channel = DatabaseChannel(database: self)
    try channel.begin()
    
    do {
      try channel.performDatabaseOperations(ops)
      try channel.commit()
    }
    catch {
      try? channel.rollback() // yes, ignore follow-up errors
      throw error
    }
  }
  
  
  // MARK: - Equatable
  
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Database else { return false }
    return other.isEqual(to: self)
  }
  @inlinable
  public func isEqual(to other: Database) -> Bool {
    if self === other { return true }
    return false
  }
  
  @inlinable
  public static func ==(lhs: Database, rhs: Database) -> Bool {
    return lhs.isEqual(to: rhs)
  }
}

/**
 * Essentially: NSClassFromString() ...
 *
 * In Swift we can't lookup classes by name yet, hence a mapping needs to
 * be provided. This protocol allows for that.
 *
 * A very simple dictionary based implementation is
 * `StaticObjectTypeLookupContext`.
 */
public protocol ObjectTypeLookupContext {
  
  func lookupObjectType(name: String) -> DatabaseObject.Type?
  
}

/**
 * A way to easily register a set of Entity name to Swift class mappings.
 * The classes need to conform to the `DatabaseObject` protocol.
 *
 * Example:
 *
 *    let db = Database(adaptor: adaptor,
 *                      objectTypes: StaticObjectTypeLookupContext([
 *        "Person"  : Person.self,
 *        "Address" : Address.self
 *    ]))
 *
 */
public struct StaticObjectTypeLookupContext : ObjectTypeLookupContext {

  @usableFromInline
  let types : [ String : DatabaseObject.Type ]
  
  @inlinable
  public init(_ types: [ String : DatabaseObject.Type ]) {
    self.types = types
  }
  
  @inlinable
  public init(_ types: [ DatabaseObject.Type ]) {
    var map = [ String : DatabaseObject.Type ]()
    
    for type in types {
      map["\(type)"] = type
    }
    
    self.types = map
  }

  @inlinable
  public func lookupObjectType(name: String) -> DatabaseObject.Type? {
    return types[name]
  }
}
