//
//  TypedDatabaseChannel.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/04/25.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//


open class TypedDatabaseChannel<ObjectType> : DatabaseChannelBase,
                                              IteratorProtocol, Sequence
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
   * results can be retrieved using ``DatabaseChannelBase/fetchObject()``
   * or ``DatabaseChannelBase/fetchRow()``.
   *
   * This is the primary method for fetches and has additional handling for
   * prefetched relationships.
   * 
   * - Parameters:
   *   - fs: The ``FetchSpecification`` which outlines how objects are being
   *         fetched.
   *   - ec: The ``ObjectTrackingContext`` that is used to register objects
   *         under their global ID.
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
    
    while let object = fetchObject() {
      if let typed = object as? ObjectType {
        baseObjects.append(typed)
      }
      else {
        globalZeeQLLogger.error(
          "Could not map fetched object of type \(type(of: object))",
          "to type of typed datasource \(ObjectType.self)!"
        )
        assertionFailure(
          "Could not map fetched object of type \(type(of: object)) " +
          "to \(ObjectType.self)"
        )
      }
      // TBD: already extract something?
    }
    cancelFetch()
    
    /* Then we fetch relationships for the 'baseObjects' we just fetched. */
    
    guard let entityName = fs.entityName else {
      assertionFailure("FetchSpecification misses entityName \(fs)")
      throw Error.MissingEntity(nil)
    }

    // This CANNOT recurse in a TypedFetchSpecification, because the
    // Typed one will try to assign it to its `ObjectType`, which will be
    // wrong for relationship targets (unless those are the same).
    let genericChannel = DatabaseChannel(database: database)
    genericChannel.adaptorChannel = adaptorChannel // run in same TX!
    do {
      try genericChannel
        .fetchRelationships(fs.entity, entityName,
                            fs.prefetchingRelationshipKeyPathes,
                            baseObjects, ec)
    }
    catch {
      genericChannel.cancelFetch()
      throw error
    }
    
    /* set the result */
    objects = baseObjects.makeIterator()
  }
  
  
  // MARK: - Iterator
  
  public func next() -> ObjectType? {
    // `fetchObject` can be called recursively on other entities. This one not.
    guard let object = fetchObject() else { return nil } // end
    guard let typed = object as? ObjectType else {
      globalZeeQLLogger.error(
        "Could not map fetched object of type \(type(of: object))",
        "to type of typed datasource \(ObjectType.self)!"
      )
      assertionFailure(
        "Could not map fetched object of type \(type(of: object)) " +
        "to \(ObjectType.self)"
      )
      return nil
    }
    return typed
  }
  
}
