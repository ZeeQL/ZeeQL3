//
//  ActiveDataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 27/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Used to query `DatabaseObject`s from a `Database`.
 *
 * W/o it you usually create an
 * Database object with an Adaptor and then use that database object to
 * acquire an DatabaseChannel.
 *  
 * Naming convention:
 * - `find...`     - a method which returns a single object and uses LIMIT 1
 * - `fetch..`     - a method which returns a List of objects
 * - `iteratorFor` - a method which returns an Iterator of fetched objects
 * - `perform...`  - a method which applies a change to the database
 *
 * Example:
 *
 *     let persons = db.datasource(Person.self)
 */
open class ActiveDataSource<Object: ActiveRecordType> : AccessDataSource<Object>
{
  
  open var database : Database
  let _entity  : Entity
  
  public init(database: Database, entity: Entity) {
    self.database = database
    self._entity  = entity
    
    super.init()
    
    self.log = database.log
  }
  
  public convenience init(database: Database) {
    if let t = Object.self as? EntityType.Type {
      self.init(database: database, entity: t.entity)
    }
    else {
      fatalError("Could not determine entity from object")
    }
  }
  
  
  // MARK: - Create
  
  open func createObject() -> Object {
    let object = Object()
    object.bind(to: database, entity: entity)
    return object
  }
  
  open func insertObject(_ object: Object) throws {
    object.bind(to: database, entity: entity)
    try object.save()
  }
  
  
  // MARK: - Required Overrides
  
  override open var entity : Entity? { return _entity }
  
  override open func _primaryFetchObjects(_ fs: FetchSpecification,
                                          cb: ( Object ) throws -> Void) throws
  {
    let channel = TypedDatabaseChannel<Object>(database: database)

    try channel.selectObjectsWithFetchSpecification(fs, nil)
    
    while let object = channel.fetchObject() {
      guard let o = object as? Object else {
        log.error("unexpected object type: \(object) \(type(of: object))")
        continue
      }
      
      try cb(o)
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
    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    
    let expr = adaptor.expressionFactory
      .selectExpressionForAttributes([ countAttr ], lock: false, cfs,
                                     fs.entity ?? entity)
    
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
  
  func datasource<Object>(_ type: Object.Type) -> ActiveDataSource<Object> {
    // use type argument to capture, is there a nicer way?
    return ActiveDataSource<Object>(database: self)
  }
  
}
