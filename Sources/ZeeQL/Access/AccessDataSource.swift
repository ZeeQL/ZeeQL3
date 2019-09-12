//
//  AccessDataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * This class has a set of operations targetted at SQL based applications. It
 * has three major subclasses with specific characteristics:
 *
 * - DatabaseDataSource
 * - ActiveDataSource
 * - AdaptorDataSource
 *
 * All of those datasources are very similiar in the operations they provide,
 * but they differ in the feature set and overhead.
 *
 * DatabaseDataSource works on top of an EditingContext. It has the biggest
 * overhead but provides features like object uniquing/registry. Eg if you need
 * to fetch a bunch of objects and then perform subsequent processing on them
 * (for example permission checks), it is convenient because the context
 * remembers the fetched objects. This datasource returns DatabaseObject's as
 * specified in the associated Model.
 *
 * ActiveDataSource is similiar to DatabaseDataSource, but it directly works
 * on a channel. It has a reasonably small overhead and still provides a good
 * feature set, like object mapping or prefetching.
 *
 * Finally AdaptorDataSource. This datasource does not perform object mapping,
 * that is, it returns Map objects and works directly on top of an
 * AdaptorChannel.
 */
open class AccessDataSource<Object: SwiftObject> : DataSource<Object> {
  
  open var log : ZeeQLLogger = globalZeeQLLogger
  var _fsname  : String?
  
  override open var fetchSpecification : FetchSpecification? {
    set {
      super.fetchSpecification = newValue
      _fsname = nil
    }
    get {
      if let fs = super.fetchSpecification { return fs }
      if let name = _fsname, let entity = entity {
        return entity[fetchSpecification: name]
      }
      return nil
    }
  }
  open var fetchSpecificationName : String? {
    set {
      _fsname = newValue
      if let name = _fsname, let entity = entity {
        super.fetchSpecification = entity[fetchSpecification: name]
      }
      else {
        super.fetchSpecification = nil
      }
    }
    get { return _fsname }
  }
  
  var _entityName : String? = nil
  open var entityName : String? {
    set { _entityName = newValue }
    get {
      if let entityName = _entityName { return entityName  }
      if let entity     = entity      { return entity.name }
      if let fs = fetchSpecification, let ename = fs.entityName { return ename }
      return nil
    }
  }
  
  open var auxiliaryQualifier     : Qualifier?
  open var isFetchEnabled         = true
  open var qualifierBindings      : Any? = nil
  
  
  // MARK: - Abstract Base Class
  
  open var entity : Entity? {
    fatalError("implement in subclass: \(#function)")
  }
  
  open func _primaryFetchObjects(_ fs: FetchSpecification,
                                 yield: ( Object ) throws -> Void) throws
  {
    fatalError("implement in subclass: \(#function)")
  }
  open func _primaryFetchCount(_ fs: FetchSpecification) throws -> Int {
    fatalError("implement in subclass: \(#function)")
  }
  open func _primaryFetchGlobalIDs(_ fs: FetchSpecification,
                                   yield: ( GlobalID ) throws -> Void) throws {
    fatalError("implement in subclass: \(#function)")
  }

  override open func fetchObjects(cb yield: ( Object ) -> Void) throws {
    try _primaryFetchObjects(try fetchSpecificationForFetch(), yield: yield)
  }
  override open func fetchCount() throws -> Int {
    return try _primaryFetchCount(try fetchSpecificationForFetch())
  }
  open func fetchGlobalIDs(yield: ( GlobalID ) throws -> Void) throws {
    try _primaryFetchGlobalIDs(try fetchSpecificationForFetch(), yield: yield)
  }

  
  // MARK: - Bindings
  
  var qualifierBindingKeys : [ String ] {
    let q   = fetchSpecification?.qualifier
    let aux = auxiliaryQualifier
    
    guard q != nil || aux != nil else { return [] }
    
    var keys = Set<String>()
    q?.addBindingKeys(to: &keys)
    aux?.addBindingKeys(to: &keys)
    return Array(keys)
  }
  
  
  // MARK: - Fetch Specification
  
  func fetchSpecificationForFetch() throws -> FetchSpecification {
    /* copy fetchspec */
    var fs : FetchSpecification
    if let ofs = fetchSpecification {
      fs = ofs // a copy, it is a struct
    }
    else if let e = entity {
      fs = ModelFetchSpecification(entity: e)
    }
    else if let entityName = entityName {
      fs = ModelFetchSpecification(entityName: entityName)
    }
    else {
      throw AccessDataSourceError.CannotConstructFetchSpecification
    }
    
    let qb  = qualifierBindings
    let aux = auxiliaryQualifier
    if qb == nil && aux == nil { return fs }
    
    /* merge in aux qualifier */
    if let aux = aux {
      let combined = and(aux, fs.qualifier)
      fs.qualifier = combined
    }
    
    /* apply bindings */
    if let qb = qb {
      guard let fs = try fs.fetchSpecificiationWith(bindings: qb) else {
        throw AccessDataSourceError.CannotConstructFetchSpecification
      }
      return fs
    }
    else { return fs }
  }

}
