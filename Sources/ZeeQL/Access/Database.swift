//
//  Database.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
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
open class Database {
  
  open   var log               : ZeeQLLogger = globalZeeQLLogger
  public let adaptor           : Adaptor
  public let typeLookupContext : ObjectTypeLookupContext?
  
  public init(adaptor: Adaptor, objectTypes: ObjectTypeLookupContext? = nil) {
    self.adaptor           = adaptor
    self.typeLookupContext = objectTypes
  }
  
  public var model : Model? { return adaptor.model }
  
  // TODO
  
  public subscript(entity n: String) -> Entity? {
    return model?[entity:n ]
  }

  /**
   * Returns the Entity object associated with a given object. If the object
   * is an instance of ActiveRecord, the record itself will be asked. If it
   * isn't (eg a POSO), the model will be asked whether one of the entities is
   * mapped to the given object.
   */
  func entityForObject(_ object: Any?) -> Entity? {
    guard let object = object else { return nil }
    
    if let ar = object as? ActiveRecordType { return ar.entity }
    
    guard let model = model else { return nil }
    return model.entityForObject(object)
  }
  
  func classForEntity(_ entity: Entity?) -> DatabaseObject.Type? {
    if let t = entity?.objectType { return t }
    
    if let n = entity?.className, let ctx = typeLookupContext {
      return ctx.lookupObjectType(name: n)
    }
    
    return nil
  }
  
  
  // MARK: - Operations
  
  public func performDatabaseOperation(_ op: DatabaseOperation) throws {
    let channel = DatabaseChannel(database: self)
    try channel.performDatabaseOperations([ op ])
  }
  
  /**
   * Performs the set of database operations in a single database transaction.
   */
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
}

// Essentially: NSClassFromString() ...
public protocol ObjectTypeLookupContext {
  
  func lookupObjectType(name: String) -> DatabaseObject.Type?
  
}

// A way to easily register a set of types
public struct StaticObjectTypeLookupContext : ObjectTypeLookupContext {

  let types : [ String : DatabaseObject.Type ]
  
  public init(_ types: [ String : DatabaseObject.Type ]) {
    self.types = types
  }
  
  public init(_ types: [ DatabaseObject.Type ]) {
    var map = [ String : DatabaseObject.Type ]()
    
    for type in types {
      map["\(type)"] = type
    }
    
    self.types = map
  }

  public func lookupObjectType(name: String) -> DatabaseObject.Type? {
    return types[name]
  }
}
