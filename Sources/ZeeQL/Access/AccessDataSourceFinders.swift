//
//  AccessDataSourceFinders.swift
//  ZeeQL
//
//  Created by Helge Heß on 22.08.19.
//  Copyright © 2019-2024 ZeeZide GmbH. All rights reserved.
//

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
    try _primaryFetchObjects(fs, yield: cb)
  }
  func fetchObjects(_ fs: FetchSpecification, cb: ( Object ) -> Void) throws {
    try _primaryFetchObjects(fs, yield: cb)
  }
  
  func fetchObjectsFor(sql: String) throws -> [ Object ] {
    var objects = [ Object ]()
    try fetchObjectsFor(sql: sql) { objects.append($0) }
    return objects
  }
  
  func fetchObjectsFor(sql: String, cb: ( Object ) -> Void) throws {
    var fs = ModelFetchSpecification(entityName: entityName)
    fs[hint: CustomQueryExpressionHintKey] = sql
    try _primaryFetchObjects(fs, yield: cb)
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
    try _primaryFetchObjects(fs, yield: cb)
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
      throw AccessDataSourceError
              .CannotConstructFetchSpecification(.invalidPrimaryKey)
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
      throw AccessDataSourceError
              .CannotConstructFetchSpecification(.invalidPrimaryKey)
    }
    
    var objects = [ Object ]()
    try fetchObjectsFor(attribute: pkeys[0], with: values) { objects.append($0)}
    return objects
  }
}

public extension AccessDataSource { // GIDs
  
  func fetchGlobalIDs(_ fs: FetchSpecification, yield: ( GlobalID ) -> Void)
         throws
  {
    try _primaryFetchGlobalIDs(fs, yield: yield)
  }
  func fetchGlobalIDs(_ fs: FetchSpecification) throws -> [ GlobalID ] {
    var objects = [ GlobalID ]()
    try fetchGlobalIDs(fs) { objects.append($0) }
    return objects
  }
  func fetchGlobalIDs() throws -> [ GlobalID ] {
    var objects = [ GlobalID ]()
    try fetchGlobalIDs() { objects.append($0) }
    return objects
  }

  func fetchObjects<S: Sequence>(with globalIDs: S,
                                 yield: ( Object ) throws -> Void) throws
         //where S.Element : GlobalID
         where S.Element == KeyGlobalID
  {
    guard let entity = entity else { throw AccessDataSourceError.MissingEntity }
    let gidQualifiers = globalIDs.map { entity.qualifierForGlobalID($0) }
    let fs = ModelFetchSpecification(entity: entity,
                                     qualifier: gidQualifiers.or())
    try fetchObjects(fs, cb: yield)
  }
  func fetchObjects<S: Sequence>(with globalIDs: S) throws -> [ Object ]
         //where S.Element : GlobalID
         where S.Element == KeyGlobalID
  {
    var objects = [ Object ]()
    try fetchObjects(with: globalIDs) { objects.append($0) }
    return objects
  }
  func fetchObjects<S: Collection>(with globalIDs: S) throws -> [ Object ]
         //where S.Element : GlobalID
         where S.Element == KeyGlobalID
  {
    var objects = [ Object ]()
    objects.reserveCapacity(globalIDs.count)
    try fetchObjects(with: globalIDs) { objects.append($0) }
    return objects
  }
}

public extension AccessDataSource { // Finders
  
  /**
   * Returns a FetchSpecification which qualifies by the given primary key
   * values.
   *
   * Example:
   * ```swift
   * let ds = DatabaseDataSource(oc, "Persons")
   * let fs = ds.fetchSpecificationForFind(10000)
   * ```
   *
   * This returns a fetchspec which will return the `Person` with primary key
   * '10000'.
   *
   * This method acquires a fetchspec by calling fetchSpecificationForFetch(),
   * it then applies the primarykey qualifier and the auxiliaryQualifier if
   * one is set. Finally it resets sorting and pushes a fetch limit of 1.
   *
   * - Parameters:
   *   - primaryKeyValues: the primary key value(s)
   * - Returns: a ``FetchSpecification`` to fetch the record with the given key
   */
  @inlinable
  func fetchSpecificationForFind(_ primaryKeyValues : [ Any ]) throws
       -> FetchSpecification?
  {
    guard !primaryKeyValues.isEmpty else { return nil }
    
    guard let findEntity = entity else {
      throw AccessDataSourceError
              .CannotConstructFetchSpecification(.missingEntity)
    }
    
    guard let pkeys = findEntity.primaryKeyAttributeNames, !pkeys.isEmpty else{
      // TODO: hm, should we invoke a 'primary key find' policy here? (like
      //       matching 'id' or 'tablename_id')
      throw AccessDataSourceError
              .CannotConstructFetchSpecification(.invalidPrimaryKey)
     }
    
    /* build qualifier for primary keys */

    // TBD: should we require attribute mappings? I don't think so, might be
    //      other keys
    let q : Qualifier
    if pkeys.count == 1 {
      let key = findEntity.keyForAttributeWith(name: pkeys[0])
      q = KeyValueQualifier(key, .EqualTo, primaryKeyValues[0])
    }
    else {
      var qualifiers = [ Qualifier ]()
      for i in 0..<pkeys.count {
        let key = findEntity.keyForAttributeWith(name: pkeys[i])
        let q = KeyValueQualifier(key, .EqualTo, primaryKeyValues[i])
        qualifiers.append(q)
      }
      q = CompoundQualifier(qualifiers: qualifiers, op: .And)
    }
    
    /* construct fetch specification */
    
    var fs = try fetchSpecificationForFetch()
    fs.qualifier     = and(q, auxiliaryQualifier)
    fs.sortOrderings = [] /* no sorting, makes DB faster */
    fs.fetchLimit    = 1  /* we just want to find one record */
    return fs
  }
  
  /**
   * Calls _primaryFetchObjects() with the given fetch specification. If the
   * fetch specification has no limit of 1, this copies the spec and sets that
   * limit.
   *
   * - Parameters:
   *   - _fs:   The fetch specification.
   * - Returns: The first record matching the fetchspec.
   */
  @inlinable
  func find(_ _fs: FetchSpecification) throws -> Object? {
    var fs = _fs // copies, struct
    fs.fetchLimit = 2
    
    var object: Object? = nil
    try _primaryFetchObjects(fs) {
      guard object == nil else {
        throw AccessDataSourceError
          .FetchReturnedMoreThanOneResult(fetchSpecification: fs,
                                          firstObject: object!)
      }
      object = $0
    }
    return object
  }
  
  /**
   * This method locates a named ``FetchSpecification`` from a ``Model``
   * associated with this datasource. It then fetches the object according to
   * the specification.
   *
   * Example:
   * ```swift
   * let a = personDataSource.find("firstCustomer")
   * ```
   * or:
   * ```swift
   * let authToken = tokenDataSource.find("findByToken",
   *                   [ "token": "12345", "login": "donald" ])
   * ```
   *
   * - Parameters:
   *   - _fname: the name of the fetch specification in the Model
   * - Returns: an object that matches the named specification
   */
  @inlinable
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
   * This method locates a named ``FetchSpecification`` from a ``Model``
   * associated with this datasource. It then fetches the object according to
   * the specification.
   *
   * Example:
   * ```swift
   * let authToken = tokenDataSource.find("findByToken",
   *                   "token", "12345", "login", "donald")
   * ```
   *
   * - Parameters:
   *   - _fname: the name of the fetch specification in the Model
   * - Returns: an object that matches the named specification
   */
  func find(_ name: String, _ firstBinding: String, _ firstValue: Any,
            _ bindings: Any...) throws -> Object?
  {
    var bindings = [ String: Any ].createArgs(bindings)
    assert(bindings[firstBinding] == nil, "Duplicate binding.")
    bindings[firstBinding] = firstValue
    return try find(name, bindings)
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
   * - Parameters:
   *   - _pkeys: The primary key value(s) to locate.
   * - Returns:  The object matching the primary key (or null if none was found)
   */
  @inlinable
  func findBy(id: Any...) throws -> Object? {
    guard let fs = try fetchSpecificationForFind(id) else {
      return nil
    }
    return try find(fs)
  }
  
  /**
   * This method works like ``fetchObjects(yield:)`` with the difference that it
   * just accepts one or no object as a result.
   *
   * - Returns: an object matching the fetch specification of the datasource.
   */
  @inlinable
  func find() throws -> Object? {
    return try find(try fetchSpecificationForFetch())
  }

  /**
   * This method locates an object using a raw SQL expression. In general you
   * should avoid raw SQL and rather specify the SQL in a named fetch
   * specification of an Model.
   *
   * Example:
   * ```swift
   * let account = ds.findBy(
   *   sql: "SELECT * FROM Account WHERE ID=10000 AND IsActive=TRUE")
   * ```
   *
   * - Parameters:
   *   - _sql: The SQL used to locate the object
   * - Returns: an object matching the SQL
   */
  @inlinable
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
   * ```swift
   * let donald = ds.findBy(matchingAll: [ "lastname"  : "Duck",
   *                                       "firstname" : "Donald"])
   * ```
   *
   * This will construct an AndQualifier containing KeyValueQualifiers to
   * perform the matches.
   *
   * - Returns: an object matching the values.
   */
  @inlinable
  func findBy(matchingAll values: [ String : Any? ]) throws -> Object? {
    var fs = try fetchSpecificationForFetch()
    fs.qualifier = qualifierToMatchAllValues(values)
    return try find(fs)
  }
  
  /**
   * Locate an object which matches any of the specified key/value combinations.
   *
   * Example:
   * ```
   * let donaldOrMickey = ds.findBy(matchingAny: ["firstname" : "Mickey",
   *                                              "firstname" : "Donald"])
   * ```
   *
   * This will construct an OrQualifier containing KeyValueQualifiers to
   * perform the matches.
   *
   * - Returns: an object matching the values.
   */
  func findBy(matchingAny values: [ String : Any? ]) throws -> Object? {
    var fs = try fetchSpecificationForFetch()
    fs.qualifier = qualifierToMatchAnyValue(values)
    return try find(fs)
  }
}
