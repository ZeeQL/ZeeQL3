//
//  AccessDataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

public protocol AccessDataSourceType: DataSourceType {
  
  var log : ZeeQLLogger { get }
  
  var entityName             : String?    { get set }
  var entity                 : Entity?    { get }
  var fetchSpecificationName : String?    { get set }

  var auxiliaryQualifier     : Qualifier? { get set }
  var isFetchEnabled         : Bool       { get set }
  var qualifierBindings      : Any?       { get set }
  
  var qualifierBindingKeys   : [ String ] { get }
  
  func fetchGlobalIDs(yield: ( GlobalID ) throws -> Void) throws
  
  // TODO: remove `_`
  func _primaryFetchObjects  (_ fs: FetchSpecification,
                              yield: ( Object ) throws -> Void) throws
  func _primaryFetchCount    (_ fs: FetchSpecification) throws -> Int
  func _primaryFetchGlobalIDs(_ fs: FetchSpecification,
                              yield: ( GlobalID ) throws -> Void) throws
}

/**
 * This class has a set of operations targetted at SQL based applications. It
 * has three major subclasses with specific characteristics:
 *
 * - ``DatabaseDataSource``
 * - ``ActiveDataSource``
 * - ``AdaptorDataSource``
 *
 * All of those datasources are very similiar in the operations they provide,
 * but they differ in the feature set and overhead.
 *
 * ``DatabaseDataSource`` works on top of an ``ObjectTrackingContext``.
 * It has the biggest overhead but provides features like object
 * uniquing/registry.
 * Eg if you need to fetch a bunch of objects and then perform subsequent
 * processing on them (for example permission checks), it is convenient because
 * the context remembers the fetched objects.
 * This datasource returns ``DatabaseObject``'s as specified in the associated
 * Model.
 *
 * ``ActiveDataSource`` is similiar to ``DatabaseDataSource``, but it directly
 * works on an ``DatabaseChannel``.
 * It has a reasonably small overhead and still provides a good feature set,
 * like object mapping or prefetching.
 *
 * Finally ``AdaptorDataSource``. This datasource does not perform object
 * mapping, that is, it returns ``AdaptorRecord`` objects and works directly on
 * top of an ``AdaptorChannel``.
 */
open class AccessDataSource<Object: SwiftObject> : DataSource<Object>,
                                                   AccessDataSourceType
{
  // TODO: Both DataSource and AccessDataSource should be protocols w/ PATs now,
  //       generics are good enough in Swift now.
  
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

  
  // MARK: - Fetch Convenience

  override open func fetchObjects(yield: ( Object ) -> Void) throws {
    // `iteratorForObjects` in GETobjects
    try _primaryFetchObjects(try fetchSpecificationForFetch(), yield: yield)
  }
  open func fetchCount() throws -> Int {
    return try _primaryFetchCount(try fetchSpecificationForFetch())
  }
  open func fetchGlobalIDs(yield: ( GlobalID ) throws -> Void) throws {
    try _primaryFetchGlobalIDs(try fetchSpecificationForFetch(), yield: yield)
  }
}

public extension AccessDataSourceType {
  
  /**
   * This method takes the name of a fetch specification. It looks up the fetch
   * spec in the `Entity` associated with the datasource and then binds the
   * spec with the given key/value pairs.
   *
   * Example:
   * ```swift
   * let persons = try ds.fetchObjects("myContacts", "contactId", 12345)
   * ```
   *
   * This will lookup the `FetchSpecification` named "myContacts" in
   * the `Entity` of the datasource. It then calls
   * `fetchSpecificationWithQualifierBindings()`
   * and passes in the given key/value pair (contactId=12345).
   *
   * Finally the fetch will be performed using
   * ``_primaryFetchObjects``.
   *
   * - Parameters:
   *   - fetchSpecificationName: The name of the fetch specification to use.
   *   - keysAndValues: The key/value pairs to apply as bindings.
   * - Returns: The fetched objects.
   */
  func fetchObjects(_ fetchSpecificationName: String,
                    _ keysAndValues: Any...) throws -> [ Object ]
  {
    guard let findEntity = entity else {
      // TBD: improve exception
      log.error("did not find entity, cannot construct fetchspec");
      throw AccessDataSourceError.MissingEntity
    }
     
    guard let fs = findEntity[fetchSpecification: fetchSpecificationName] else {
      throw AccessDataSourceError
        .DidNotFindFetchSpecification(name: fetchSpecificationName,
                                      entity: findEntity)
    }
     
    let binds   = [ String: Any ].createArgs(keysAndValues)
    var results = [ Object ]()
    if !binds.isEmpty {
      guard let fs = try fs.fetchSpecificiationWith(bindings: binds) else {
        throw AccessDataSourceError
          .CouldNotResolveBindings(fetchSpecification: fs, bindings: binds)
      }
      try _primaryFetchObjects(fs) { results.append($0) }
    }
    else {
      try _primaryFetchObjects(fs) { results.append($0) }
    }
    return results
  }
  
  // MARK: - Bindings
  
  @inlinable
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
  
  /**
   * Takes the configured fetch specification and applies the auxiliary
   * qualifier and qualifier bindings on it.
   *
   * This method always returns a copy of the fetch specification object,
   * so callers are free to modify the result of this method.
   *
   * - Returns: A new fetch specification with bindings/qualifier applied.
   */
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
      throw AccessDataSourceError
              .CannotConstructFetchSpecification(.missingEntity)
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
        throw AccessDataSourceError
                .CannotConstructFetchSpecification(.bindingFailed)
      }
      return fs
    }
    
    return fs
  }

}
