//
//  DatabaseChannel.swift
//  ZeeQL
//
//  Created by Helge Hess on 27/02/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

/**
 * A ``DatabaseChannelBase`` that returns type erased ``DatabaseObject``'s.
 */
open class DatabaseChannel : DatabaseChannelBase, IteratorProtocol, Sequence {
  // NOTE: This is (almost) an EXACT copy of the TypedDatabaseChannel due to 
  //       Swift:
  // Using some protocol as a concrete type conforming to another protocol is
  // not supported
  // http://stackoverflow.com/questions/33503602/using-some-protocol-as-a-concrete-type-conforming-to-another-protocol-is-not-sup
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
  override open func selectObjectsWithFetchSpecification
    (_ fs: FetchSpecification, _ ec: ObjectTrackingContext? = nil)
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
    
    while let o = fetchObject() {
      baseObjects.append(o)
      // TBD: already extract something?
    }
    cancelFetch()
    
    /* Then we fetch relationships for the 'baseObjects' we just fetched. */
    
    guard let entityName = fs.entityName else {
      throw Error.MissingEntity(nil)
    }

    // This recurses in the generic variant, different to the
    // TypedDatabaseChannel.
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
