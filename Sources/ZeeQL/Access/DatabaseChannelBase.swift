//
//  DatabaseChannel.swift
//  ZeeQL
//
//  Created by Helge Heß on 28.04.25.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * A database channels wraps around an ``AdaptorChannel`` and produces
 * ``DatabaseObject``'s for them, and registers those objects w/ the
 * ``Database`` / ``ObjectTrackingContext``.
 *
 * This is a base class for:
 * - ``DatabaseChannel``     : A generic database channel that fetches type
 *                             erased records (i.e. ``DatabaseObject``'s).
 * - ``TypedDatabaseChannel``: A database channel the returns objects that are
 *                             bound to a static type.
 */
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
    
    case UnsupportedDatabaseOperator(DatabaseOperation.Operator)
    
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
  
  
  // MARK: - Fetch Specification

  /**
   * Creates a map where the keys are level-1 relationship names and the values
   * are subpathes. The method also resolves flattened relationships (this is,
   * if a relationship is a flattened one, the keypath of the relationship
   * will get processed).
   *
   * Pathes:
   * ```
   * toCompany.toProject
   * toCompany.toEmployment
   * toProject
   * ```
   * Will result in:
   * ```
   * [ "toCompany" = [ "toProject", "toEmployment" ],
   *   "toProject" = [] ]
   * ```
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
   * ```
   * customers.address
   * phone.number
   * ```
   * where customers is a flattened but phone is not, will return:
   * ```
   * customers
   * ```
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
      if let dotidx = path.firstIndex(of: ".") {
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
   * repeaters like '*' (e.g. `parent*` => repeat relationship 'parent' until no
   * objects are found anymore).
   *
   * - Parameters:
   *   - name:  Name of the relationship, e.g. 'employments' or 'parent*'
   * - Returns: cleaned relationship name, e.g. 'employments' or 'parent'
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
      // TBD: generate Attrs for fetchKeys
      return entity?.attributesWithNames(fetchKeys)
    }
    return entity?.attributes
  }
  
  
  // MARK: - Fetching
  
  /**
   * Whether or not a fetch is in progress (a select was done and objects can
   * be retrieved using a sequence of fetchObject() calls).
   *
   * - Returns: true if objects can be fetched, false if no fetch is in progress
   */
  public var isFetchInProgress : Bool { return records != nil }
  
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
   * - Parameters:
   *   - fs: The ``FetchSpecification`` which outlines how objects are being
   *         fetched.
   *   - ec: The ``ObjectTrackingContext`` for the fetch (optional).
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
    
    // TODO (2025-04-28: todo what? :-) )
    if let entity = fs.entity {
      currentEntity = entity
    }
    else if let entityName = fs.entityName {
      currentEntity = database[entity: entityName]
    }
    guard currentEntity != nil || fetchesRawRows else {
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
  
  func selectObjectsWithFetchSpecification(_ fs: FetchSpecification,
                                           _ ec: ObjectTrackingContext? = nil)
       throws
  {
    // This is the subclass responsibility
    assertionFailure(
      "DCB subclass did not override `selectObjectsWithFetchSpecification`")
    throw Error.TODO
  }

  /**
   * Prefetches a set of related objects.
   * 
   * - Parameters:
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
      assert(!relName.contains("."))
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
    guard let rel = entity[relationship: relName] else {
      throw Error.MissingRelationship(entity, relName)
    }
    guard let join = rel.joins.first else {
      // just skip, no joins
      assertionFailure(
        "Relationship w/o joins? \(entity.name) \(type(of: rel)) \(rel)")
      return
    }
    
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
      guard let rv = relObject.value(forKey: targetName) else {
        continue
      }

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
   * The method converts the database operations into a set of
   * ``AdaptorOperation``'s,
   * which are then performed using the associated ``AdaptorChannel``.
   */
  public func performDatabaseOperations(_ ops: [ DatabaseOperation ]) throws {
    guard !ops.isEmpty else { return } /* nothing to do */
    
    defer {
      // This will call the completion handlers!
      for op in ops { op.didPerformAdaptorOperations() }
    }
    
    /* turn db ops into adaptor ops */
    
    var aops = try adaptorOperationsForDatabaseOperations(ops)
    guard !aops.isEmpty else { return } /* nothing to do */
    
    /* perform adaptor ops */
    
    let didOpenChannel : Bool
    let adaptorChannel : AdaptorChannel
    if let c = self.adaptorChannel {
      didOpenChannel = false
      adaptorChannel = c
    }
    else {
      adaptorChannel = try acquireChannel()
      self.adaptorChannel = adaptorChannel
      didOpenChannel = true
    }
    defer {
      if didOpenChannel { releaseChannel() }
    }
    
    // Transactions: The `AdaptorChannel` opens a transaction if there is more
    // than one operation. Also: the `Database` embeds it into a TX too.
    try adaptorChannel.performAdaptorOperations(&aops)
    
    
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
          if let ar = op.object as? ActiveRecordBase {
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
          if let ar = op.object as? ActiveRecordBase {
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
          
          if let ar = op.object as? ActiveRecordType {
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
            if let ar = op.object as? ActiveRecordType {
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
   * This method creates the necessary ``AdaptorOperation``'s for the given
   * ``DatabaseOperation``'s and attaches them to the respective database-op
   * objects.
   *
   * Side effects: the AdOps are added to the DB ops.
   *
   * - Parameters:
   *   - ops:   array of ``DatabaseOperation``'s
   * - Returns: array of ``AdaptorOperation``'s
   */
  func adaptorOperationsForDatabaseOperations(_ ops: [ DatabaseOperation ])
         throws -> [ AdaptorOperation ]
  {
    guard !ops.isEmpty else { return [] } /* nothing to do */
    
    var aops = [ AdaptorOperation ]()

    for op in ops {
      guard let aop = try op.primaryAdaptorOperation() else { continue }
      aops.append(aop)
      op.addAdaptorOperation(aop) // TBD: do we really need this?
    }
    return aops
  }
}
