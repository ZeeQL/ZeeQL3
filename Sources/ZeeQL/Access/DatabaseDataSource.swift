//
//  DatabaseDataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

public protocol DatabaseDataSourceType<Object>: AccessDataSourceType
  where Object: DatabaseObject
{
  
  var objectContext : ObjectTrackingContext { get }
  var database      : Database?             { get }

  init(_ oc: ObjectTrackingContext, entityName: String)
}

/**
 * A datasource which works on top of an EditingContext. That is, the editing
 * context does all the fetching.
 */
open class DatabaseDataSource<Object: DatabaseObject>
             : AccessDataSource<Object>, DatabaseDataSourceType
{
  
  public let objectContext : ObjectTrackingContext
  
  required public init(_ oc: ObjectTrackingContext, entityName: String) {
    self.objectContext = oc
    
    super.init()
    
    self.entityName     = entityName
    self.isFetchEnabled = true
  }
  
  public var database : Database? {
    let os = objectContext.rootObjectStore
    guard let dc = os as? DatabaseContext else { return nil }
    return dc.database
  }

  /**
   * Attempts to retrieve the Entity associated with this datasource. This
   * first checks the 'entityName' of the DatabaseDataSource. If this fails
   * and a fetchSpecification is set, its entityName is retrieved.
   * 
   * @return the Entity managed by the datasource
   */
  override open var entity : Entity? {
    let ename : String
    
    if let entityName = entityName {
      ename = entityName
    }
    else if let fs = fetchSpecification {
      if let entity = fs.entity { return entity }
      guard let entityName = fs.entityName else { return nil }
      ename = entityName
    }
    else {
      return nil
    }
    
    guard let db = database else { return nil }
    return db[entity: ename]
  }

  @inlinable
  override open func _primaryFetchObjects(_ fs: FetchSpecification,
                                          yield: ( Object ) throws -> Void)
    throws
  {
    let results = try objectContext.objectsWith(fetchSpecification: fs)
    for result in results {
      assert(result is Object)
      guard let object = result as? Object else { continue }
      try yield(object)
    }
  }
}
