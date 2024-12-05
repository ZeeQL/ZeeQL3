//
//  ActiveDataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 27/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

public protocol ActiveDataSourceType<Object>: AccessDataSourceType
  where Object: ActiveRecordType
{
  
  var database : Database { get set }

  init(database: Database, entity: Entity)
  
  func createObject() -> Object
  func insertObject(_ object: Object) throws
}

extension ActiveDataSourceType {
  
  @inlinable
  public init(database: Database) {
    if let t = Object.self as? EntityType.Type {
      self.init(database: database, entity: t.entity)
    }
    else {
      fatalError("Could not determine entity from object")
    }
  }
  
}

/**
 * Used to query `DatabaseObject`s from a `Database`.
 *
 * W/o it you usually create a
 * ``Database`` object with an ``Adaptor`` and then use that database object to
 * acquire an ``DatabaseChannel``.
 *
 * Naming convention:
 * - `find...`     - a method which returns a single object and uses LIMIT 1
 * - `fetch..`     - a method which returns a List of objects
 * - `iteratorFor` - a method which returns an Iterator of fetched objects
 * - `perform...`  - a method which applies a change to the database
 *
 * Example:
 * ```swift
 * let persons = db.datasource(Person.self)
 * ```
 */
open class ActiveDataSource<Object: ActiveRecordType>: AccessDataSource<Object>,
                                                       ActiveDataSourceType
{
  
  open var database : Database
  let _entity  : Entity
  
  required public init(database: Database, entity: Entity) {
    self.database = database
    self._entity  = entity
    
    super.init()
    
    self.log = database.log
  }
  
  
  // MARK: - Create
  
  @inlinable
  open func createObject() -> Object {
    let object = Object()
    object.bind(to: database, entity: entity)
    return object
  }
  
  @inlinable
  open func insertObject(_ object: Object) throws {
    object.bind(to: database, entity: entity)
    try object.save()
  }
  
  
  // MARK: - Required Overrides
  
  override open var entity : Entity? { return _entity }
  
  override open func _primaryFetchObjects(_ fs: FetchSpecification,
                                          yield: ( Object ) throws -> Void)
                     throws
  {
    let channel = TypedDatabaseChannel<Object>(database: database)

    try channel.selectObjectsWithFetchSpecification(fs, nil)
    
    while let object = channel.fetchObject() {
      guard let o = object as? Object else {
        log.error("unexpected object type: \(object) \(type(of: object))")
        continue
      }
      
      try yield(o)
    }
  }
  
  override open func _primaryFetchGlobalIDs(_ fs: FetchSpecification,
                                            yield: ( GlobalID ) throws -> Void)
                       throws
  {
    func lookupEntity() -> Entity? {
      if let entity = fs.entity { return entity }
      if let name = fs.entityName {
        if let dsEntity = entity, dsEntity.name == name {
          return dsEntity
        }
        if let entity = database.model?[entity: name] { return entity }
        globalZeeQLLogger.error("did not find fetchspec entity:", name, fs)
        return nil
      }
      if let entity = self.entity { return entity }
      if let name = self.entityName {
        if let entity = database.model?[entity: name] { return entity }
        globalZeeQLLogger.error("did not find datasource entity:", name, self)
        return nil
      }
      globalZeeQLLogger.error("no entity for GlobalID fetch:", fs, self)
      return nil
    }
    
    guard let entity = lookupEntity() else { return }
    guard let pkeys = entity.primaryKeyAttributeNames, !pkeys.isEmpty else {
      globalZeeQLLogger.error("entity has no primary keys for gid fetch:",
                              entity)
      throw AccessDataSourceError.MissingEntity
    }
    
    var cfs = fs
    cfs.fetchesReadOnly     = true
    cfs.fetchAttributeNames = pkeys
    cfs.prefetchingRelationshipKeyPathes = nil
    
    let pkeyAttrs = pkeys.compactMap { entity[attribute: $0] }
    assert(pkeyAttrs.count == pkeys.count, "could not lookup all pkeys!")
    
    let adaptor = database.adaptor
    let expr = adaptor.expressionFactory
      .selectExpressionForAttributes(pkeyAttrs,
                                     lock: false, cfs, entity)
    
    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    
    try channel.evaluateQueryExpression(expr, pkeyAttrs) { record in
      guard let gid = entity.globalIDForRow(record) else {
        globalZeeQLLogger.error("could not derive GID from row:", record,
                                "  entity:", entity,
                                "  pkeys: ", pkeys.joined(separator: ","))
        return // TBD: throw?
      }
      try yield(gid)
    }
  }
  
  override open func _primaryFetchCount(_ fs: FetchSpecification) throws
                      -> Int
  {
    #if false
      // this uses CustomQueryExpressionHintKey, which is not actually
      // required as we pass in the attributes to selectExpressionForAttrs...?
      // Hm.
      guard let cfs = fs.fetchSpecificationForCount else {
        throw AccessDataSourceError.CannotConstructCountFetchSpecification
      }
    #else
      // The idea is that this preserves the WHERE part of the query, including
      // relationships.
      var cfs = fs
      cfs.sortOrderings = nil // no need to sort
      
      // hm, well, OK.
      cfs.fetchLimit  = 1 // TBD: could use '2' to detect query issues
      cfs.fetchOffset = 0
    #endif
    
    let adaptor = database.adaptor
    let expr = adaptor.expressionFactory
      .selectExpressionForAttributes([ countAttr ], lock: false, cfs,
                                     fs.entity ?? entity)
    
    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    
    // TODO: improve, less overhead just for the count
    var fetchCount : Int? = nil
    try channel.evaluateQueryExpression(expr, nil) { record in
      guard let value = record[0] else {
        log.error("count fetch returned nil:", record)
        return
      }
      
      // FIXME: this is really lame, we should pass in an attribute with the
      //        desired type
      if      let c = value as? Int    { fetchCount = c }
      else if let c = value as? Int32  { fetchCount = Int(c) }
      else if let c = value as? Int64  { fetchCount = Int(c) }
      else if let c = value as? String { fetchCount = Int(c) } // Hm. Why?
      else {
        log.error("could not determine count from value:",
                  value, type(of: value))
      }
    }
    
    guard let result = fetchCount else {
      throw AccessDataSourceError.CountFetchReturnedNoResults
    }
    
    return result
  }

}

// Swift 3: static stored properties not supported in generic types
fileprivate let countAttr : Attribute = {
  let countAttr = ModelAttribute(name: "count", externalType: "INT")
  countAttr.readFormat = "COUNT(*)"
  countAttr.valueType  = Int.self
  return countAttr
}()


public extension Database {
  
  @inlinable
  func datasource<Object>(_ type: Object.Type = Object.self)
       -> ActiveDataSource<Object>
  {
    return ActiveDataSource<Object>(database: self)
  }
}


// MARK: - Query Runner

public extension DatabaseFetchSpecification where Object: ActiveRecordType {
  // hh(2024-12-04): This style probably doesn't make that much sense...
  
  /**
   * Evaluate the active record fetch specifiction in a ``Database``.
   *
   * ```swift
   * let _ = try Person.where("login like %@", "*he*")
   *                   .limit(4)
   *                   .fetch(in: db)
   * ```
   */
  @inlinable
  func fetch(in db: Database) throws -> [ Object ] {
    let ds = ActiveDataSource<Object>(database: db)
    ds.fetchSpecification = self
    return try ds.fetchObjects()
  }
}
