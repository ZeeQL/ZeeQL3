//
//  DatabaseChannel.swift
//  ZeeQL
//
//  Created by Helge Hess on 27/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

open class DatabaseChannelBase {
  
  public enum Error : Swift.Error {
    case TransactionInProgress
    case CouldNotAcquireChannel(Swift.Error?)
    case CouldNotBeginTX       (Swift.Error?)
    case CouldNotFinishTX      (Swift.Error?)
    
    case MissingEntity(String?)
    case MissingRelationship(Entity, String)
    case IncompleteJoin(Join)
    
    case CouldNotBuildPrimaryKeyQualifier
    case MissingAttributeUsedForLocking(Attribute)
    case RefetchReturnedNoRow
    
    case TODO
  }
  
  open   var log            : ZeeQLLogger { return database.log }
  public let database       : Database
  public var adaptorChannel : AdaptorChannel?
  
  var currentEntity    : Entity? = nil
  var currentClass     : DatabaseObject.Type? = nil
  var isLocking        = false
  var fetchesRawRows   = false
  var makesNoSnapshots = false
  var refreshObjects   = false
  
  var objectContext : ObjectTrackingContext? = nil
  
  public var recordCount = 0
  public var records     : IndexingIterator<[AdaptorRecord]>?
  
  public init(database: Database) {
    self.database = database
  }
  deinit {
    releaseChannel()
  }
  
  
  // MARK: - Transactions
  
  public var isInTransaction : Bool {
    return adaptorChannel?.isTransactionInProgress ?? false
  }
  
  /**
   * Begins a database transaction. This allocates an adaptor channel which will
   * be shared by subsequent fetches/operations. The channel is checked back
   * into the pool on the next rollback/commit.
   *
   * Be sure to always commit or rollback the transaction!
   */
  @usableFromInline
  func begin() throws {
    guard !isInTransaction else { throw Error.TransactionInProgress }
    
    if adaptorChannel == nil {
      do {
        adaptorChannel = try acquireChannel()
      }
      catch {
        throw Error.CouldNotAcquireChannel(error)
      }
    }
    assert(adaptorChannel != nil,
           "got no adaptor channel, but no error thrown?")
    guard let ac = adaptorChannel
     else { throw Error.CouldNotAcquireChannel(nil) }
    
    do {
      try ac.begin()
    }
    catch {
      releaseChannel()
      throw Error.CouldNotBeginTX(error)
    }
  }
  
  @usableFromInline
  func commitOrRollback(doRollback: Bool = false) throws {
    guard let ac = adaptorChannel else { return } // noop
      // not considered an error, nothing happened
  
    do {
      if doRollback {
        try ac.rollback()
      }
      else {
        try ac.commit()
      }
    }
    catch {
      releaseChannel()
      throw Error.CouldNotFinishTX(error)
    }
    
    releaseChannel()
  }
  
  /**
   * Commits a database transaction. This also releases the associated adaptor
   * channel back to the connection pool.
   */
  @inlinable
  open func commit() throws {
    try commitOrRollback(doRollback: false)
  }
  
  /**
   * Rolls back a database transaction. This also releases the associated
   * adaptor channel back to the connection pool.
   */
  @inlinable
  func rollback() throws {
    try commitOrRollback(doRollback: true)
  }
  
  
  // MARK: - Adaptor Channel
  
  func acquireChannel() throws -> AdaptorChannel {
    return try database.adaptor.openChannelFromPool()
  }
  func releaseChannel() {
    guard let ac = adaptorChannel else { return }
    adaptorChannel = nil
    
    database.adaptor.releaseChannel(ac)
  }
  
  
  // MARK: - Fecth Specification

  /**
   * Creates a map where the keys are level-1 relationship names and the values
   * are subpathes. The method also resolves flattened relationships (this is,
   * if a relationship is a flattened one, the keypath of the relationship
   * will get processed).
   *
   * Pathes:
   *
   *     toCompany.toProject
   *     toCompany.toEmployment
   *     toProject
   *
   * Will result in:
   *
   *     [ "toCompany" = [ "toProject", "toEmployment" ],
   *       "toProject" = [] ]
   *
   * Note that the keys are never flattened relationships.
   */
  func levelPrefetchSpecificiation(_ entity: Entity, _ pathes: [ String ])
       -> [ String : [ String ] ]
  {
    // TODO: should this throw?
    guard !pathes.isEmpty else { return [:] }
    
    var level = [ String : [ String ] ]()

    for originalPath in pathes {
      var path = originalPath
      
      /* split off first part of relationship */
      
      var relname : String
      #if swift(>=5.0)
        var dotidx  = path.firstIndex(of: ".")
      #else
        var dotidx  = path.index(of: ".")
      #endif
      if let dotidx = dotidx {
        relname = String(path[path.startIndex..<dotidx])
      }
      else { relname = path } // no dot
      
      /* lookup relationship */
      
      guard var rel = entity[relationship: relname] else {
        // TBD: throw? ignore? what?
        log.error("did not find specified prefetch relationship '\(path)' " +
                  "in entity: '\(entity.name)'")
        continue
      }
      
      /* process flattened relationships */
      
      if rel.isFlattened {
        // dupe, same thing again
        path   = rel.relationshipPath ?? ""
        #if swift(>=5.0)
          dotidx = path.firstIndex(of: ".")
        #else
          dotidx = path.index(of: ".")
        #endif
        if let dotidx = dotidx {
          relname = String(path[path.startIndex..<dotidx])
        }
        else { relname = path } // no dot
        
        /* lookup relationship */
        
        guard let frel = entity[relationship: relname] else {
          // TBD: throw? ignore? what?
          log.error("did not find specified first relationship '\(path)' " +
                    "of flattened prefetch: \(path) " +
                    "in entity: '\(entity.name)'")
          continue
        }
        rel = frel
      }
      
      /* process relationship */
      
      if rel.joins.isEmpty {
        log.error("prefetch relationship has no joins, ignoring: \(rel)")
        continue
      }
      if rel.joins.count > 1 {
        log.error("prefetch relationship has multiple joins (unsupported), " +
                  "ignoring: \(rel)")
        continue
      }
      
      /* add relation names to map */
      
      var sublevels = level[relname] ?? []
      
      if let dotidx = dotidx {
        let idx = path.index(after: dotidx)
        sublevels.append(String(path[idx..<path.endIndex]))
        level[relname] = sublevels
      }
      else if level[relname] == nil {
        level[relname] = []
      }
    }
    
    return level
  }

  /**
   * Given a list of relationship pathes this method extracts the set of
   * level-1 flattened relationships.
   * 
   * Example:
   *
   *     customers.address
   *     phone.number
   *
   * where customers is a flattened but phone is not, will return:
   *
   *     customers
   * 
   */
  func flattenedRelationships(_ entity: Entity, _ pathes: [ String ])
       -> [ String ]
  {
    // TODO: should this throw?
    guard !pathes.isEmpty else { return [] }
    
    var flattened = [ String ]()
    for path in pathes {
      /* split off first part of relationship */
      
      var relname : String
      #if swift(>=5.0)
        let dotidx  = path.firstIndex(of: ".")
      #else
        let dotidx  = path.index(of: ".")
      #endif
      if let dotidx = dotidx {
        relname = String(path[path.startIndex..<dotidx])
      }
      else { relname = path } // no dot
      
      /* split off fetch parameters (recursive fetches like parent*) */
      
      relname = relationshipNameWithoutParameters(relname)
        
      /* lookup relationship */
      
      guard let rel = entity[relationship: relname], rel.isFlattened
       else { continue }
      
      flattened.append(relname) // TBD: do we need the name with parameters?
    }
    
    return flattened
  }

  /**
   * Cleans the name of the relationship from parameters, eg the name contain
   * repeaters like '*' (eg parent* => repeat relationship 'parent' until no
   * objects are found anymore).
   *
   * - parameter name: name of the relationship, eg 'employments' or 'parent*'
   * - returns: cleaned relationship name, eg 'employments' or 'parent'
   */
  func relationshipNameWithoutParameters(_ name: String) -> String {
    /* cut off '*' (relationship fetch repeaters like parent*) */
    if name.hasSuffix("*") {
      let endIdx = name.index(before: name.endIndex)
      return String(name[name.startIndex..<endIdx])
    }
    return name
  }
  
  
  func selectListForFetchSpecification(_ entity: Entity?,
                                       _ fs: FetchSpecification?)
    -> [ Attribute ]?
  {
    if let fetchKeys = fs?.fetchAttributeNames {
      if let entity = entity {
        return entity.attributesWithNames(fetchKeys)
      }
      else {    // TBD: generate Attrs for fetchKeys
        return nil
      }
    }
    else if let entity = entity {
      return entity.attributes
    }
    else {
      return nil
    }
  }
  
  
  // MARK: - Fetching
  
  /**
   * Whether or not a fetch is in progress (a select was done and objects can
   * be retrieved using a sequence of fetchObject() calls).
   *
   * - returns: true if objects can be fetched, false if no fetch is in progress
   */
  public var isFetchInProgress : Bool {
    return records != nil
  }
  
  /**
   * Finishes a fetch by resetting transient fetch state in the channel. This
   * is automatically called when fetchRow() returns no object and should
   * always be called if a fetch is stopped before all objects got retrieved.
   */
  func cancelFetch() {
    /* Note: do not release the adaptor channel in here! */
    objectContext  = nil // TBD: TODO: this does not record fetched assocs?
    records        = nil
    currentEntity  = nil
    recordCount    = 0
    isLocking      = false
    fetchesRawRows = false
    currentClass   = nil
  }
  
  /**
   * This method prepares the channel for a fetch and initiates the fetch. Once
   * called, the channel has various instance variables configured and the
   * results can be retrieved using fetchObject() or fetchRow().
   *
   * This is different to selectObjectsWithFetchSpecification(), which has
   * additional handling for prefetched relationships.
   * 
   * - parameter fs: The FetchSpecification which outlines how objects are being
   *                 fetched.
   * - parameter ec: The ObjectTrackingContext for the fetch
   */
  func primarySelectObjectsWithFetchSpecification(_ fs: FetchSpecification,
                                                  _ ec: ObjectTrackingContext?
                                                          = nil)
       throws
  {
    /* tear down */
    cancelFetch()
    
    /* prepare */

    isLocking          = fs.locksObjects
    fetchesRawRows     = fs.fetchesRawRows
    self.objectContext = ec
    
    // TODO
    if let entity = fs.entity {
      currentEntity = entity
    }
    else if let entityName = fs.entityName {
      currentEntity = database[entity: entityName]
    }
    guard currentEntity != nil || fetchesRawRows
     else {
      throw Error.MissingEntity(fs.entityName)
    }
    
    #if false // unused?!
      let selectList = selectListForFetchSpecification(currentEntity, fs)
    #endif

    makesNoSnapshots = false
    if let entity = currentEntity, entity.isReadOnly {
      makesNoSnapshots = true
    }
    else if fs.fetchesReadOnly {
      makesNoSnapshots = true
    }
    
    /* determine object class */
    
    if !fetchesRawRows {
      // TBD: support per-object classes by setting this to null if the
      //      entity says its multi-class
      currentClass = database.classForEntity(currentEntity)
    }
    
    
    /* open channel if necessary */
    
    var didOpenChannel = false
    if adaptorChannel == nil {
      do {
        adaptorChannel = try acquireChannel()
        didOpenChannel = true
      }
      catch { throw Error.CouldNotAcquireChannel(error) }
    }
    assert(adaptorChannel != nil,
           "got no adaptor channel, but no error thrown?")
    guard let ac = adaptorChannel
     else { throw Error.CouldNotAcquireChannel(nil) }
    
    defer { if didOpenChannel { releaseChannel() } }
    
    
    /* perform fetch */
    
    var results = [ AdaptorRecord ]()
    
    /* Note: custom queries are detected by the adaptor */
    try ac.selectAttributes(
      nil, // selectList, /* was null to let the channel do the work, why? */
      fs, lock: isLocking, currentEntity
    ) {
      results.append($0)
    }
    
    // TODO: improve this and replace the iterator?
    recordCount = results.count
    records     = results.makeIterator()
  }
  
  // TODO: selectObjectsWithFetchSpecification, uses ObjectType
  func selectObjectsWithFetchSpecification(_ fs: FetchSpecification,
                                           _ ec: ObjectTrackingContext? = nil)
       throws
  {
    throw Error.TODO
  }

  /**
   * Prefetches a set of related objects.
   * 
   * - parameters:
   *   - entityName:         entity this fetch is relative to
   *   - prefetchRelPathes:  the pathes we want to prefetch
   *   - baseObjects:        the set of objects we want to prefetch for
   *   - ec:                 the active tracking context
   */
  func fetchRelationships(_ entity            : Entity?,
                          _ entityName        : String,
                          _ prefetchRelPathes : [ String ],
                          _ baseObjects       : [ DatabaseObject ],
                          _ ec                : ObjectTrackingContext?) throws
  {
    guard !prefetchRelPathes.isEmpty else { return } // noop
    guard !baseObjects.isEmpty       else { return } // noop
    
    /* entity */

    guard let entity = entity ?? database[entity: entityName] else {
      throw Error.MissingEntity(entityName)
    }


    /* process relationships (key is a level1 name, value are the subpaths) */

    let leveledPrefetches =
          levelPrefetchSpecificiation(entity, prefetchRelPathes)

    /*
     * Maps/caches Lists of values for a given attribute in the base result.
     * Usually the key is the primary key.
     * 
     * We cache this because its most likely reused when we have multiple
     * prefetches. The fetch will most usually go against the primary key ...
     */
    let helper = DatabaseChannelFetchHelper(baseObjects: baseObjects)
    
    for ( relName, values ) in leveledPrefetches {
      /* The relName is never a path, its a level-1 key. the value in
       * leveledPrefetches contains 'subpathes'.
       */
      do {
        try fetchRelationship(entity, relName, baseObjects, values, helper, ec)
      }
      catch {
        log.error("Could not fetch relationship", relName, values, error)
        throw error
      }
    }

    /* fetch flattened relationships (NOT IMPLEMENTED) */

    let flattened = flattenedRelationships(entity, prefetchRelPathes)
    for rel in flattened {
      let flattenedRel = entity[relationship: rel]

      // TBD: process flattened relationships (walk over initial set)
      log.error("not processing flattened relationship: " +
                "\(flattenedRel as Optional)")
    }
  }
  
  /**
   * This is the master of desaster which performs the actual fetch of the
   * relationship for a given set of `baseObjects`.
   *
   * Note: relationship names can contain a repeat `*` parameter,
   *       eg `parentDocument*`
   *
   * - parameters:
   *   - entity:                     the entity of the *base* objects
   *   - relationNameWithParameters: the name of the relationship
   *   - baseObjects:    the objects which we want to fetch the relship for
   *   - prefetchPathes: subpathes we want to prefetch
   *   - helper:         a fetch context to track objects during the fetch
   *   - ec:             the associated editing-context, if there is one
   */
  func fetchRelationship(_ entity                     : Entity,
                         _ relationNameWithParameters : String,
                         _ baseObjects                : [ DatabaseObject ],
                         _ originalPrefetchPathes     : [ String ],
                         _ helper : DatabaseChannelFetchHelper,
                         _ ec     : ObjectTrackingContext?) throws
  {
    var prefetchPathes = originalPrefetchPathes
    /* Note: DatabaseContext.batchFetchRelationship */
    
    /* first we check whether the relationship contains a repeat-parameter,
     * eg:
     *   parent*
     * This means that we prefetch 'parent' again and again (until it returns
     * no 'baseObjects' for a subsequent fetch).
     */
    
    let relName : String
    if relationNameWithParameters.hasSuffix("*") {
      relName = relationshipNameWithoutParameters(relationNameWithParameters)
      
      /* fixup prefetch patches to include our tree-depth fetch */
      if !prefetchPathes.contains(relationNameWithParameters) {
        prefetchPathes.append(relationNameWithParameters)
      }
    }
    else {
      relName = relationNameWithParameters
    }
    
    /* Note: we filter out non-1-join relationships in the levelXYZ() method */
    guard let rel = entity[relationship: relName]
     else { throw Error.MissingRelationship(entity, relName)}
    guard let join = rel.joins.first else { return } // just skip, no joins
    
    /* extract values of source object list for IN query on target */

    guard let srcName = join.source?.name ?? join.sourceName else {
      throw Error.IncompleteJoin(join)
    }
    
    let srcValues = helper.getSourceValues(srcName)
    
    /* This is a Map which maps the join target-value to matching
     * DatabaseObjects. Usually its just one.
     */
    let valueToObjects = helper.getValueToObjects(srcName)
    
    // TBD: srcValues could be empty?! Well, values could be NULL (for non-pkey
    //      source attributes).

    /* construct fetch specification */
    // Note: uniquing should be done in fetchObject using an object tracking
    //       context which is passed around

    // TBD: we also need to include the join. Otherwise we might fetch
    //      values from other entities using the same join table.
    //      (OGo: company_assignment used for team->account + e->person)
    //      hm, wouldn't that be toSource.id IN ?!
    //      TBD: do we really need that? The example is crap because the
    //           join uses 'company' as a base. (properly modelled the
    //           two would be stored in different tables!)
    //        Update: Same issue with project_company_assignment
    // TBD: we should only fetch INs which we do not already have cached
    //      .. in a per transaction uniquer
    //      TBD: well, this is the editing context. we have this now, but we
    //           refetch objects which is stupid
    //      TBD: do we really need to support arbitrary targets or can we
    //           use KeyGlobalID?
    guard let targetAttr = join.destination else {
      log.error("did not find target-attr of relationship join: \(rel):", join)
      return // TBD: hm ... (eg if the model is b0rked)
    }
    let targetName = targetAttr.name
    
    // This does things like:
    // `companyId in [ 1, 2, 3, 4 ]`
    let joinQualifier = KeyValueQualifier(targetName, .Contains, srcValues)
    
    guard let destEntity = rel.destinationEntity else {
      // TODO: what error
      assertionFailure("Missing destination Entity for relationship \(rel)")
      return
    }
    
    // TBD: we should batch?
    // TBD: if we have the Entity object, create the fetch-spec with it? To 
    //      avoid subsequent lookups.
    var fs =
      ModelFetchSpecification(entity: destEntity, qualifier: joinQualifier)
    
    if !prefetchPathes.isEmpty {
      /* apply nested prefetches */
      fs.prefetchingRelationshipKeyPathes = prefetchPathes
    }
    
    /* run nested query */
    
    do {
      try selectObjectsWithFetchSpecification(fs, ec)
    }
    catch {
      cancelFetch() /* better be sure ;-) */
      throw error
    }
    
    while let relObject = fetchObject() {
      /* targetName is the target attribute in the join */
      guard let rv = relObject.value(forKey: targetName) else { continue }

      guard let v = hackValueHolder(rv) else {
        continue
      }
      
      /* this is the list of join source objects which have that value
       * in the source attribute of the join.
       */
      guard let srcObjects = valueToObjects[v] else {
        /* I think this can only happen when concurrent transactions
         * delete items.
         * Hm, which would be an error, because the source object would
         * have a key, but wouldn't be hooked up?!
         */
        log.error("found no objects to hook up for foreign key:", v)
        continue
      }
      
      /* Hook up the fetched relationship target objects with the objects which
       * link to it.
       */
      for srcObject in srcObjects {
        srcObject.addObject(relObject,
                            toBothSidesOfRelationshipWithKey: relName)
      }
    }
    
    /* fetch done */
  }
  
  
  // MARK: - Fetch Iterators
  
  /**
   * Fetches the next row from the database. Currently we fetch all rows once
   * and then step through the resultset ...
   *
   * - returns: the next record, or nil if there are no more
   */
  func fetchRow() -> AdaptorRecord? {
    guard records != nil else { return nil }
    guard let next = self.records!.next() else {
      cancelFetch() // done
      return nil
    }
    return next
  }
  
  /**
   * This is called when `currentClass` is not set. It to support
   * different classes per entity where the class will be selected based on
   * the row.
   *
   * - parameter row: database record
   * - returns:       the class to instantiate for the row
   */
  func objectTypeForRow(_ row: AdaptorRecord) -> DatabaseObject.Type? {
    // TBD: implement. Add additional class information to Entity ...
    return nil
  }
  
  var hasObjectIterator : Bool {
    fatalError("override in subclass: \(#function)")
  }
  func fetchObjectFromIterator() -> DatabaseObject? {
    fatalError("override in subclass: \(#function)")
  }

  /**
   * This is the primary method to retrieve an object after a select().
   *
   * - returns: null if there are no more objects, or the fetched object/record
   */
  public func fetchObject() -> DatabaseObject? {
    /* use iterator if the objects are already fetched in total */
    // TODO: make the function throws
    
    if hasObjectIterator { return fetchObjectFromIterator() }
    
    /* fetch raw row from adaptor channel */
    
    guard let row = fetchRow() else {
      // TBD: should we cancel?
      return nil
    }
    /* can't do this w/o resorting to 'Any'
    if fetchesRawRows {
      if (isDebugOn) log.debug("    return raw row: " + row);
      return row;
    }
    */
    if fetchesRawRows {
      fatalError("cannot fetch raw rows with typed channel")
    }
    
    // TBD: other way around?
    let objectType = currentClass ?? objectTypeForRow(row)
    
    // TODO: we might want to do uniquing here ..
    
    let gid = currentEntity?.globalIDForRow(row)
    
    if !refreshObjects, let tc = objectContext, let gid = gid {
      // TBD: we could ask some delegate whether we should refresh
      if let oldEO = tc.objectFor(globalID: gid) as? DatabaseObject {
        return oldEO /* was already fetched/registered */
      }
    }
    // TBD: we might still want to *reuse* the object (might have additional
    //      non-persistent information attached)
    
    /* instantiate new object */
    
    let dbo : DatabaseObject
    if let arType = objectType as? ActiveRecordType.Type,
       let entity = currentEntity
    {
      dbo = arType.init()
      if let boundObject = dbo as? DatabaseBoundObject { // TBD: done in awake?!
        boundObject.bind(to: database, entity: entity)
      }
    }
    else {
      // TODO: Hm, what should we do :-) More protocols?
      log.error("Cannot construct this type")
      return nil // TODO: make the function throws
    }
    
    /* apply row values */
    
    // TBD: rather use one compound method? takeStoredValues(row)!
    let attrNames = row.schema.attributeNames
    for i in 0..<attrNames.count {
      // TODO: support for ( key, value ) in row
      dbo.takeStoredValue(row[i], forKey: attrNames[i])
    }
    
    
    /* register in editing context */
    
    if let gid = gid, let tc = objectContext {
      tc.record(object: dbo, with: gid)
    }
    
    /* awake objects */
    
    // TBD: this might be a bit early since relationships are not yet fetched
    dbo.awakeFromFetch(database)
    
    /* make snapshot */

    if !makesNoSnapshots {
      /* Why don't we just reuse the row? Because applying the row on the object
       * might have changed or coerced values which would be incorrectly
       * reported as changes later on.
       * 
       * We make the snapshot after the awake for the same reasons.
       */
      
      let snapshot  = makeSnapshot(attributes: row.schema.attributeNames,
                                   object: dbo)
      
      /* record snapshot */
      
      if let ar = dbo as? ActiveRecordType {
        ar.snapshot = snapshot
        // else: do record a snapshot in the editing or database context
        //       TBD: done by tc.record, right?
      }
    }
    
    return dbo
  }
  
  func makeSnapshot(attributes: [String], object: DatabaseObject) -> Snapshot {
    var snapshot = Snapshot()
    for attributeName in attributes {
      if let v = object.storedValue(forKey: attributeName) {
        snapshot[attributeName] = v
      }
      else { // TBD
        snapshot[attributeName] = nil
      }
    }
    return snapshot
  }
  
  // MARK: - Operations
  
  /**
   * The method converts the database operations into a set of adaptor
   * operations which are then performed using the associated
   * AdaptorChannel.
   */
  public func performDatabaseOperations(_ ops: [ DatabaseOperation ]) throws {
    guard !ops.isEmpty else { return } /* nothing to do */
    
    defer {
      for op in ops { op.didPerformAdaptorOperations() }
    }
    
    /* turn db ops into adaptor ops */
    
    let aops = try adaptorOperationsForDatabaseOperations(ops)
    guard !aops.isEmpty else { return } /* nothing to do */
    
    /* perform adaptor ops */
    
    var didOpenChannel = false
    if adaptorChannel == nil {
      adaptorChannel = try acquireChannel()
      didOpenChannel = true
    }
    defer {
      if didOpenChannel {
        releaseChannel()
      }
    }
    
    // Transactions: The `AdaptorChannel` opens a transaction if there is more
    // than one operation. Also: the `Database` embeds it into a TX too.
    try adaptorChannel!.performAdaptorOperations(aops)
    
    
    // OK, the database operations have been successful. Now we need to handle
    // the side effects.
    
    for op in ops {
      let entity = op.entity
      let dbop   = op.databaseOperator
      
      switch dbop {
        case .delete:
          if let tc = objectContext {
            tc.forget(object: op.object)
          }
          if let ar = op.object as? ActiveRecord {
            // TODO: remove primary key
            ar.isNew    = true
            ar.snapshot = nil
          }
        
        case .insert:
          if let rr = op.newRow {
            for ( key, value ) in rr {
              op.object.takeStoredValue(value, forKey: key)
            }
          }
          if let ar = op.object as? ActiveRecord {
            ar.isNew = false
          }
          
          // yes! *not* awakeFromInsertion, which is called when an object
          // is added to an editing context, i.e. is NOT yet saved to the DB.
          op.object.awakeFromFetch(database)
          
          /* Why don't we just reuse the row? Because applying the row on the object
           * might have changed or coerced values which would be incorrectly
           * reported as changes later on.
           *
           * We make the snapshot after the awake for the same reasons.
           */
          let snapshot =
            makeSnapshot(attributes: entity.attributes.map { $0.name },
                         object: op.object)
          
          if let ar = op.object as? ActiveRecord {
            ar.snapshot = snapshot
          }
          
          if let tc = objectContext {
            if let gid = entity.globalIDForRow(snapshot) {
              // TODO: unregister a potential temporary gid!
              tc.record(object: op.object, with: gid)
            }
          }
        
        case .update:
          // TBD: do we need to make an explicit snapshot like above?
          // Note: We could do updates on partials, doesn't have to be a full
          //       object!
          if let snapshot = op.dbSnapshot {
            if let ar = op.object as? ActiveRecord {
              ar.snapshot = snapshot
              assert(!ar.isNew)
            }
          }
        
        default:
          break
      }
    }
  }
  
  /**
   * This method creates the necessary AdaptorOperation's for the given
   * DatabaseOperation's and attaches them to the respective database-op
   * objects.
   *
   * Side effects: the AdOps are added to the DB ops.
   * 
   * - parameter ops: array of DatabaseOperation's
   * - returns:       array of AdaptorOperation's
   */
  func adaptorOperationsForDatabaseOperations(_ ops: [ DatabaseOperation ])
         throws -> [ AdaptorOperation ]
  {
    guard !ops.isEmpty else { return [] } /* nothing to do */
    
    var aops = [ AdaptorOperation ]()

    for op in ops {
      let entity = op.entity
      let aop    = AdaptorOperation(entity: entity)
      
      var dbop = op.databaseOperator
      if case .none = op.databaseOperator {
        if let ar = op.object as? ActiveRecordType {
          if ar.isNew { op.databaseOperator = .insert }
          else        { op.databaseOperator = .update }
          dbop = op.databaseOperator
        }
      }
      
      if case .none = dbop {
        log.warn("got no operator in db-op:", op)
      }
      aop.adaptorOperator = dbop
      
      switch dbop {
        case .delete:
          // TODO: add attrs used for locking
          let pq : Qualifier?
          if let snapshot = op.dbSnapshot {
            // The snapshot represents the last known database state. Which is
            // what we want here.
            pq = entity.qualifierForPrimaryKey(snapshot)
          }
          else {
            pq = entity.qualifierForPrimaryKey(op.object)
          }
          guard pq != nil else {
            log.error("could not calculate primary key qualifier for op:", op)
            throw Error.CouldNotBuildPrimaryKeyQualifier
          }
          aop.qualifier = pq
        
        case .insert:
          let props  = entity.classPropertyNames
                    ?? entity.attributes.map { $0.name }
          let values = KeyValueCoding.values(forKeys: props,
                                             inObject: op.object)
          aop.changedValues = values
          op.newRow         = values // TBD: don't
          
          // TBD: Not sure whether completionBlocks are the best way to 
          //      communicate up, maybe make this more formal.
          aop.completionBlock = { [weak op] in // op retains its aop's
            guard let op = op else { return }
            
            if let rr = aop.resultRow {
              for ( key, value ) in rr {
                op.newRow![key] = value
              }
            }
          }
          
        case .update:
          let snapshot = op.dbSnapshot
          var pq : Qualifier?

          /* calculate qualifier */
          
          if let snapshot = snapshot {
            // The snapshot represents the last known database state. Which is
            // what we want here.
            pq = entity.qualifierForPrimaryKey(snapshot)
          }
          else {
            pq = entity.qualifierForPrimaryKey(op.object)
          }
          guard pq != nil else {
            log.error("could not calculate primary key qualifier for op:", op)
            throw Error.CouldNotBuildPrimaryKeyQualifier
          }
          
          if let lockAttrs = entity.attributesUsedForLocking,
             !lockAttrs.isEmpty, let snapshot = snapshot
          {
            var qualifiers = [ Qualifier ]()
            qualifiers.reserveCapacity(lockAttrs.count + 1)
            if let pq = pq { qualifiers.append(pq) }
            
            for attr in lockAttrs {
              if let value = snapshot[attr.name] { // value is still an `Any?`!
                let q = KeyValueQualifier(attr.name, .EqualTo, value)
                qualifiers.append(q)
              }
              else {
                throw Error.MissingAttributeUsedForLocking(attr)
              }
            }
            
            pq = CompoundQualifier(qualifiers: qualifiers, op: .And)
          }
          
          aop.qualifier = pq

          /* calculate changed values */
          
          let values : Snapshot
          if let snapshot = snapshot {
            values = op.object.changesFromSnapshot(snapshot)
          }
          else {
            // no snapshot, need to update all
            let props  = entity.classPropertyNames
                      ?? entity.attributes.map { $0.name }
            values = KeyValueCoding.values(forKeys: props, inObject: op.object)
          }
          #if false
            // Could work on any KVC object:
            if let dbo = op.object as? DatabaseObject { /*.. code above ..*/ }
            else {
              // update all, no change tracking
              values = KeyValueCoding.values(forKeys: props, inObject: op.object)
              // TODO: changes might include non-class props (like assocs)
            }
          #endif
          
          guard !values.isEmpty else {
            // did not change, no need to update
            continue
          }

          aop.changedValues = values
          
          /* Note: we need to copy the snapshot because we might ignore it in
           *       case the dbop fails.
           */
          if let snapshot = snapshot {
            var newSnap = snapshot
            for ( key, value ) in values {
              newSnap[key] = value
            }
            op.dbSnapshot = newSnap
          }
          else {
            op.dbSnapshot = values
          }
        
        default:
          log.warn("unsupported database operation:", dbop)
          continue
      }
      
      aops.append(aop)
      
      op.addAdaptorOperation(aop) // TBD: do we really need this?
    }
    return aops
  }
}


// MARK: - Typed Concrete Class

open class TypedDatabaseChannel<ObjectType> : DatabaseChannelBase,
                                              IteratorProtocol
  where ObjectType: DatabaseObject
{
  
  public var objects : IndexingIterator<[ ObjectType ]>?
  
  override var hasObjectIterator : Bool { return objects != nil }

  override func fetchObjectFromIterator() -> DatabaseObject? {
    guard let next = objects!.next() else { // done
      cancelFetch()
      return nil
    }
    return next
  }

  override public var isFetchInProgress : Bool {
    return super.isFetchInProgress || objects != nil
  }
  override func cancelFetch() {
    super.cancelFetch()
    objects = nil
  }
  
  override func objectTypeForRow(_ row: AdaptorRecord) -> DatabaseObject.Type? {
    // TBD: implement. Add additional class information to Entity ...
    return ObjectType.self
  }

  func fetchObject<O>() -> O? {
    guard let o = super.fetchObject() else { return nil }
    guard let to = o as? O else {
      // throw something
      log.warn("fetchObject returned an unexpected type:", o, type(of: o))
      return nil
    }
    return to
  }

  
  // MARK: - Select
  
  /**
   * This method prepares the channel for a fetch and initiates the fetch. Once
   * called, the channel has various instance variables configured and the
   * results can be retrieved using fetchObject() or fetchRow().
   *
   * This is the primary method for fetches and has additional handling for
   * prefetched relationships.
   * 
   * - Parameters:
   *   - fs: The FetchSpecification which outlines how objects are being
   *         fetched.
   *   - ec: TODO
   */
  override public func selectObjectsWithFetchSpecification(
    _ fs: FetchSpecification,
    _ ec: ObjectTrackingContext? = nil
  ) throws
  {
    guard !fs.prefetchingRelationshipKeyPathes.isEmpty else {
      /* simple case, no prefetches */
      return try primarySelectObjectsWithFetchSpecification(fs, ec)
    }
    

    /* Prefetches were specified, process them. We open a channel and a 
     * transaction.
     */
    
    /* open channel if necessary */
    
    var didOpenChannel = false
    if adaptorChannel == nil {
      do {
        adaptorChannel = try acquireChannel()
        didOpenChannel = true
      }
      catch { throw Error.CouldNotAcquireChannel(error)}
    }
    assert(adaptorChannel != nil,
           "got no adaptor channel, but no error thrown?")
    guard adaptorChannel != nil else { throw Error.CouldNotAcquireChannel(nil) }
    
    defer { if didOpenChannel { releaseChannel() } }

    
    /* open TX */
    
    var didBeginTX = false
    do {
      if !isInTransaction {
        try begin()
        didBeginTX = true
      }
    }
    catch { throw error }
    defer {
      do {
        /* Note: We do not commit because we just fetched stuff and commits
         *       increase the likeliness that something fails. So: rollback in
         *       both ways.
         */
        if didBeginTX {
          try rollback()
        }
      }
      catch {
        // TBD: hm
        globalZeeQLLogger.warn("could not rollback transaction:", error)
      }
    }
    
    var baseObjects = [ ObjectType ]()

    /* First we fetch all primary objects and collect them in an Array */

    do {
      try primarySelectObjectsWithFetchSpecification(fs, ec)
    }
    catch {
      cancelFetch()
      throw error
    }
    
    if recordCount > 0 {
      baseObjects.reserveCapacity(recordCount)
    }
    
    while let o = fetchObject() as? ObjectType {
      baseObjects.append(o)
      // TBD: already extract something?
    }
    cancelFetch()
    
    /* Then we fetch relationships for the 'baseObjects' we just fetched. */
    
    guard let entityName = fs.entityName
     else {
      throw Error.MissingEntity(nil)
    }
      // TBD
    
    do {
      try fetchRelationships(fs.entity, entityName,
                             fs.prefetchingRelationshipKeyPathes,
                             baseObjects, ec)
    }
    catch {
      cancelFetch()
      throw error
    }
    
    /* set the result */
    objects = baseObjects.makeIterator()
  }
  
  
  // MARK: - Iterator
  
  public func next() -> ObjectType? {
    // `fetchObject` can be called recursively on other entities. This one not.
    return fetchObject() as? ObjectType
  }
  
}


// MARK: - Untyped Concrete Class

open class DatabaseChannel : DatabaseChannelBase, IteratorProtocol {
  // NOTE: This is (almost) an EXACT copy of the TypedDatabaseChannel due to 
  //       Swift:
  //   Using some protocol as a concrete type conforming to another protocol is
  //   not supported
  //   http://stackoverflow.com/questions/33503602/using-some-protocol-as-a-concrete-type-conforming-to-another-protocol-is-not-sup
  // http://stackoverflow.com/questions/33112559/protocol-doesnt-conform-to-itself
  public typealias ObjectType = DatabaseObject
  
  public var objects : IndexingIterator<[ObjectType]>?
  
  override var hasObjectIterator : Bool { return objects != nil }

  override func fetchObjectFromIterator() -> DatabaseObject? {
    guard let next = objects!.next() else { // done
      cancelFetch()
      return nil
    }
    return next
  }

  override public var isFetchInProgress : Bool {
    return super.isFetchInProgress || objects != nil
  }
  override func cancelFetch() {
    super.cancelFetch()
    objects = nil
  }
  
  
  // MARK: - Select
  
  /**
   * This method prepares the channel for a fetch and initiates the fetch. Once
   * called, the channel has various instance variables configured and the
   * results can be retrieved using fetchObject() or fetchRow().
   *
   * This is the primary method for fetches and has additional handling for
   * prefetched relationships.
   * 
   * - parameters:
   *   - fs: The FetchSpecification which outlines how objects are being
   *         fetched.
   *   - ec: TODO
   */
  override func selectObjectsWithFetchSpecification(_ fs: FetchSpecification,
                                                    _ ec: ObjectTrackingContext?
                                                              = nil)
                throws
  {
    guard !fs.prefetchingRelationshipKeyPathes.isEmpty else {
      /* simple case, no prefetches */
      return try primarySelectObjectsWithFetchSpecification(fs, ec)
    }
    

    /* Prefetches were specified, process them. We open a channel and a 
     * transaction.
     */
    
    /* open channel if necessary */
    
    var didOpenChannel = false
    if adaptorChannel == nil {
      do {
        adaptorChannel = try acquireChannel()
        didOpenChannel = true
      }
      catch { throw Error.CouldNotAcquireChannel(error)}
    }
    assert(adaptorChannel != nil,
           "got no adaptor channel, but no error thrown?")
    guard adaptorChannel != nil else { throw Error.CouldNotAcquireChannel(nil) }
    
    defer { if didOpenChannel { releaseChannel() } }

    
    /* open TX */
    
    try begin()
    defer {
      do {
        /* Note: We do not commit because we just fetched stuff and commits
         *       increase the likeliness that something fails. So: rollback in
         *       both ways.
         */
        try rollback()
      }
      catch {
        // TBD: hm
        globalZeeQLLogger.warn("rollback failed!", error)
      }
    }
    
    var baseObjects = [ ObjectType ]()

    /* First we fetch all primary objects and collect them in an Array */

    do {
      try primarySelectObjectsWithFetchSpecification(fs, ec)
    }
    catch {
      cancelFetch()
      throw error
    }
    
    if recordCount > 0 {
      baseObjects.reserveCapacity(recordCount)
    }
    
    while let o = fetchObject() {
      baseObjects.append(o)
      // TBD: already extract something?
    }
    cancelFetch()
    
    /* Then we fetch relationships for the 'baseObjects' we just fetched. */
    
    guard let entityName = fs.entityName
     else {
      throw Error.MissingEntity(nil)
     }
      // TBD
    
    do {
      try fetchRelationships(fs.entity, entityName,
                             fs.prefetchingRelationshipKeyPathes,
                             baseObjects, ec)
    }
    catch {
      cancelFetch()
      throw error
    }
    
    /* set the result */
    objects = baseObjects.makeIterator()
  }
  
  
  // MARK: - Iterator
  
  public func next() -> ObjectType? {
    // `fetchObject` can be called recursively on other entities. This one not.
    return fetchObject()
  }
  
}


// MARK: - Helper

class DatabaseChannelFetchHelper {
  // TODO: fix abuse of GlobalID, workaround for Hashable-limitations
  
  let baseObjects             : [ DatabaseObject ]
  var sourceKeyToValues       = [ String : [ GlobalID ] ]()
  var sourceKeyToValueObjects = [ String : [ GlobalID : [DatabaseObject] ] ]()
  
  init(baseObjects: [ DatabaseObject ]) {
    self.baseObjects = baseObjects
  }
  
  func getSourceValues(_ srcName: String) -> [ GlobalID ] {
    if let result = sourceKeyToValues[srcName] { return result }

    fill(srcName)
    return sourceKeyToValues[srcName] ?? []
  }
  
  func getValueToObjects(_ srcName: String)
       -> [ GlobalID : [ DatabaseObject ] ]
  {
    if let result = sourceKeyToValueObjects[srcName] { return result }
    
    fill(srcName)
    return sourceKeyToValueObjects[srcName] ?? [:]
  }
  
  func fill(_ srcName: String) {
    guard !baseObjects.isEmpty else { return }
    
    /* not yet cached, calculate */
    var srcValues      = [ GlobalID ]()
    var valueToObjects = [ GlobalID : [ DatabaseObject ] ]()
    
    
    /* calculate */

    for baseObject in baseObjects {
      // TBD: which one?
      guard let rv = baseObject.storedValue(forKey: srcName) else { continue }
      // guard let rv = baseObject.value(forKey: srcName) else { continue }
      guard let v = hackValueHolder(rv) else {
        continue
      }
      
      /* Most often the source key is unique and we have just one
       * entry, but its not a strict requirement
       */
      var vobjects = valueToObjects[v] ?? []
      vobjects.append(baseObject)
      valueToObjects[v] = vobjects
      
      /* Note: we could also use vobjects.keySet() */
      if !srcValues.contains(v) {
        srcValues.append(v)
      }
    }
    
    sourceKeyToValues[srcName ]      = srcValues
    sourceKeyToValueObjects[srcName] = valueToObjects
  }
}


fileprivate func hackValueHolder(_ value : Any?) -> GlobalID? {
  // Swift GID hack
  guard let rv = value else { return nil }
  
  if let gid = rv as? GlobalID { return gid }
  if let i   = rv as? Int {
    return SingleIntKeyGlobalID(entityName: "<HACK>", value: i)
  }
  if let i   = rv as? Int64 {
    return SingleIntKeyGlobalID(entityName: "<HACK>", value: Int(i))
  }
  if let i   = rv as? Int32 {
    return SingleIntKeyGlobalID(entityName: "<HACK>", value: Int(i))
  }
  fatalError("cannot process join value: \(rv)")
}
