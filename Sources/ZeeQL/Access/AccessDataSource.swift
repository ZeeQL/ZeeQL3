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
                                 cb: ( Object ) throws -> Void) throws
  {
    fatalError("implement in subclass: \(#function)")
  }
  open func _primaryFetchCount(_ fs: FetchSpecification) throws -> Int {
    fatalError("implement in subclass: \(#function)")
  }
  
  override open func fetchObjects(cb: ( Object ) -> Void) throws {
    try _primaryFetchObjects(try fetchSpecificationForFetch(), cb: cb)
  }
  override open func fetchCount() throws -> Int {
    return try _primaryFetchCount(try fetchSpecificationForFetch())
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
    if let aux = aux { fs.qualifier = and(aux, fs.qualifier) }
    
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

public extension AccessDataSource {
  
  // MARK: - Convenience Fetch Ops
  
  func fetchObjects(_ fs: FetchSpecification) throws -> [ Object ] {
    var objects = [ Object ]()
    try fetchObjects(fs) { objects.append($0) }
    return objects
  }
  func fetchObjects(_ fs: FetchSpecification, cb: ( Object ) throws -> Void)
       throws
  {
    try _primaryFetchObjects(fs, cb: cb)
  }
  func fetchObjects(_ fs: FetchSpecification, cb: ( Object ) -> Void) throws {
    try _primaryFetchObjects(fs, cb: cb)
  }
  
  func fetchObjectsFor(sql: String) throws -> [ Object ] {
    var objects = [ Object ]()
    try fetchObjectsFor(sql: sql) { objects.append($0) }
    return objects
  }
  
  func fetchObjectsFor(sql: String, cb: ( Object ) -> Void) throws {
    var fs = ModelFetchSpecification(entityName: entityName)
    fs[hint: CustomQueryExpressionHintKey] = sql
    try _primaryFetchObjects(fs, cb: cb)
  }
  
  func fetchObjectsFor(attribute name: String, with values: [Any]) throws
       -> [ Object ]
  {
    var objects = [ Object ]()
    try fetchObjectsFor(attribute: name, with: values) { objects.append($0) }
    return objects
  }

  func fetchObjectsFor(attribute name: String, with values: [ Any ],
                       cb: ( Object ) -> Void) throws
  {
    guard !values.isEmpty else { return } // nothing to do
    var fs = try fetchSpecificationForFetch()
    
    // override qualifier, but merge in AUX
    let q  = KeyValueQualifier(StringKey(name), .Contains, values)
    fs.qualifier = and(q, auxiliaryQualifier)
    try _primaryFetchObjects(fs, cb: cb)
  }
  
  /**
   * Fetches objects where the primary key matches the given IDs.
   * Example:
   *
   *     ds.fetchObjectsFor(ids: pkeys) { object in ... }
   *
   * @param values - primary keys to fetch
   */
  func fetchObjectsFor(ids values: Any..., cb: ( Object ) -> Void) throws {
    guard let pkeys = entity?.primaryKeyAttributeNames, pkeys.count == 1 else {
      throw AccessDataSourceError.CannotConstructFetchSpecification
    }
    
    try fetchObjectsFor(attribute: pkeys[0], with: values, cb: cb)
  }
  
  /**
   * Fetches objects where the primary key matches the given IDs.
   * Example:
   *
   *     ds.fetchObjectsFor(ids: pkeys)
   *
   * @param values - primary keys to fetch
   * @return a List of objects
   */
  func fetchObjectsFor(ids values: Any...) throws -> [ Object ] {
    guard let pkeys = entity?.primaryKeyAttributeNames, pkeys.count == 1 else {
      throw AccessDataSourceError.CannotConstructFetchSpecification
    }
    
    var objects = [ Object ]()
    try fetchObjectsFor(attribute: pkeys[0], with: values) { objects.append($0)}
    return objects
  }
}

public extension AccessDataSource { // Finders
  
  /**
   * Returns a FetchSpecification which qualifies by the given primary key
   * values. Example:
   *
   *     DatabaseDataSource ds = DatabaseDataSource(oc, "Persons")
   *     FetchSpecification fs = ds.fetchSpecificationForFind(10000)
   *
   * This returns a fetchspec which will return the Person with primary key
   * '10000'.
   *
   * This method acquires a fetchspec by calling fetchSpecificationForFetch(),
   * it then applies the primarykey qualifier and the auxiliaryQualifier if
   * one is set. Finally it resets sorting and pushes a fetch limit of 1.
   * 
   * @param _pkeyVals - the primary key value(s)
   * @return a FetchSpecification to fetch the record with the given key
   */
  func fetchSpecificationForFind(_ _pkeyVals : [ Any ]) throws
       -> FetchSpecification?
  {
    guard !_pkeyVals.isEmpty else { return nil }
    
    guard let findEntity = entity else {
      throw AccessDataSourceError.CannotConstructFetchSpecification
    }
    
    guard let pkeys = findEntity.primaryKeyAttributeNames, !pkeys.isEmpty else{
      // TODO: hm, should we invoke a 'primary key find' policy here? (like
      //       matching 'id' or 'tablename_id')
      throw AccessDataSourceError.CannotConstructFetchSpecification
     }
    
    /* build qualifier for primary keys */

    // TBD: should we require attribute mappings? I don't think so, might be
    //      other keys
    let q : Qualifier
    if pkeys.count == 1 {
      let key = findEntity.keyForAttributeWith(name: pkeys[0])
      q = KeyValueQualifier(key, .EqualTo, _pkeyVals[0])
    }
    else {
      var qualifiers = [ Qualifier ]()
      for i in 0..<pkeys.count {
        let key = findEntity.keyForAttributeWith(name: pkeys[i])
        let q = KeyValueQualifier(key, .EqualTo, _pkeyVals[i])
        qualifiers.append(q)
      }
      q = CompoundQualifier(qualifiers: qualifiers, op: .And)
    }
    
    /* construct fetch specification */
    
    var fs = try fetchSpecificationForFetch()
    fs.qualifier     = and(q, auxiliaryQualifier)
    fs.sortOrderings = nil /* no sorting, makes DB faster */
    fs.fetchLimit    = 1   /* we just want to find one record */
    return fs
  }
  
  /**
   * Calls _primaryFetchObjects() with the given fetch specification. If the
   * fetch specification has no limit of 1, this copies the spec and sets that
   * limit.
   * 
   * @param _fs - the fetch specification
   * @return the first record matching the fetchspec
   */
  func find(_ _fs: FetchSpecification) throws -> Object? {
    var fs = _fs // copies, struct
    fs.fetchLimit = 1
    
    var object: Object? = nil
    try _primaryFetchObjects(fs) { object = $0 }
    return object
  }
  
  /**
   * This method locates a named FetchSpecification from a Model associated
   * with this datasource. It then fetches the object according to the
   * specification.
   *
   * Example:
   *
   *     let a = personDataSource.find("firstCustomer")
   *
   * or:
   *
   *     let authToken = tokenDataSource.find("findByToken",
   *                       [ "token": "12345", "login": "donald" ])
   *
   * @param _fname the name of the fetch specification in the Model
   * @return an object which matches the named specification 
   */
  func find(_ name: String, _ bindings: Any? = nil) throws -> Object? {
    guard let entity = entity else { return nil }
    guard var fs = entity[fetchSpecification: name] else { return nil }
    
    if let bindings = bindings {
      guard let cfs = try fs.fetchSpecificiationWith(bindings: bindings) else {
        return nil
      }
      fs = cfs
    }
    
    return try find(fs)
  }
  
  /**
   * This method locates objects using their primary key(s). Usually you have
   * just one primary key, but technically compound keys are supported as well.
   *
   * Example:
   *
   *     let account = ds.findBy(id: 10000)
   * 
   * The primary key column(s) is(are) specified in the associated Entity
   * model object.
   *
   * @param _pkeys the primary key value(s) to locate.
   * @return the object matching the primary key (or null if none was found)
   */
  func findBy(id: Any...) throws -> Object? {
    guard let fs = try fetchSpecificationForFind(id) else {
      return nil
    }
    return try find(fs)
  }
  
  /**
   * This method works like fetch() with the difference that it just accepts
   * one or no object as a result.
   * 
   * @return an object matching the fetch specification of the datasource.
   */
  func find() throws -> Object? {
    return try find(try fetchSpecificationForFetch())
  }

  /**
   * This method locates an object using a raw SQL expression. In general you
   * should avoid raw SQL and rather specify the SQL in a named fetch
   * specification of an Model.
   *
   * Example:
   *
   *     let account = ds.findBy(
   *       sql: "SELECT * FROM Account WHERE ID=10000 AND IsActive=TRUE")
   * 
   * @param _sql the SQL used to locate the object
   * @return an object matching the SQL
   */
  func findBy(sql: String) throws -> Object? {
    // TBD: shouldn't we support bindings?
    guard !sql.isEmpty else { return nil }
    
    var fs = ModelFetchSpecification(entityName: entityName)
    fs.fetchLimit = 1
    fs[hint: CustomQueryExpressionHintKey] = sql
    return try find(fs)
  }
  
  /**
   * Locate an object which matches all the specified key/value combinations.
   *
   * Example:
   *
   *     let donald = ds.findBy(matchingAll: [ "lastname": "Duck",
   *                                           "firstname": "Donald"])
   * 
   * This will construct an AndQualifier containing KeyValueQualifiers to
   * perform the matches.
   */
  func findBy(matchingAll values: [ String : Any ]) throws -> Object? {
    var fs = try fetchSpecificationForFetch()
    fs.qualifier = qualifierToMatchAllValues(values)
    return try find(fs)
  }
  
  /**
   * Locate an object which matches any of the specified key/value combinations.
   *
   * Example:
   *
   *     let donaldOrMickey = ds.findBy(matchingAny: ["firstname": "Mickey",
   *                                                  "firstname", "Donald"])
   * 
   * This will construct an OrQualifier containing KeyValueQualifiers to
   * perform the matches.
   */
  func findBy(matchingAny values: [ String : Any ]) throws -> Object? {
    var fs = try fetchSpecificationForFetch()
    fs.qualifier = qualifierToMatchAnyValue(values)
    return try find(fs)
  }
  
}


// MARK: - Error Object

public enum AccessDataSourceError : Swift.Error { // cannot nest in generic
  case CannotConstructFetchSpecification
  case CannotConstructCountFetchSpecification
  case CountFetchReturnedNoResults
}
