//
//  DatabaseContext.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/2017.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

public enum DatabaseContextError : Swift.Error {
  case fetchSpecificationHasUnresolvedBindings(FetchSpecification)
}

/**
 * This is an ``ObjectStore`` which works on top of ``Database``. It just
 * manages the ``DatabaseChannel``'s to fetch objects.
 *
 * E.g. it can be wrapped in an ``ObjectTrackingContext`` which serves as an
 * object uniquer and keeps an actual registry of objects that have been
 * fetched.
 * The ``DatabaseContext`` itself does NOT keep track of the objects it fetches,
 * the tracking context is explicitly passed into its respective functions.
 */
open class DatabaseContext : ObjectStore, SmartDescription {
  
  public let database : Database

  public init(_ database: Database) {
    self.database = database
  }
  
  
  // MARK: - Fetching Objects
  
  /**
   * Fetch a set of objects using an untyped ``FetchSpecification``.
   *
   * The results are still typed based on the yield closure that is passed in.
   * This is the primary ``ObjectStore`` fetch method.
   *
   * - Parameters:
   *   - fetchSpecification: The description of what to fetch.
   *   - trackingContext:    The ``ObjectTrackingContext`` where fetched objects
   *                         are uniqued against.
   *   - yield:              A closure that receives all fetched objects.
   */
  @inlinable
  open func objectsWithFetchSpecification<O>(
    _  fetchSpecification : FetchSpecification,
    in    trackingContext : ObjectTrackingContext,
    _               yield : ( O ) throws -> Void
  ) throws
    where O: DatabaseObject
  {
    if fetchSpecification.requiresAllQualifierBindingVariables {
      if let keys = fetchSpecification.qualifier?.bindingKeys, !keys.isEmpty {
        throw DatabaseContextError
          .fetchSpecificationHasUnresolvedBindings(fetchSpecification)
      }
    }
    
    let ch = try createDatabaseChannel(for: O.self)
    try ch
      .selectObjectsWithFetchSpecification(fetchSpecification, trackingContext)
    
    while let o = ch.fetchObject() {
      assert(o is O)
      guard let typed = o as? O else {
        throw TypedDatabaseChannelError.fetchedIncorrectObjectType
      }
      try yield(typed)
    }
  }
  
  @inlinable
  open func createDatabaseChannel<O>(for type: O.Type = O.self)
    throws -> DatabaseChannelBase
    where O: DatabaseObject
  {
    return TypedDatabaseChannel<O>(database: database)
  }

  
  // MARK: - Legacy
  
  @available(*, deprecated,
              message: "Use objectsWithFetchSpecification() instead")
  @inlinable
  public func objectsWith<T>(fetchSpecification : TypedFetchSpecification<T>,
                             in trackingContext : ObjectTrackingContext,
                             _ yield            : ( T ) -> Void) throws
  {
    try objectsWithFetchSpecification(fetchSpecification, in: trackingContext,
                                      yield)
  }

  // MARK: - Description
  
  open func appendToDescription(_ ms: inout String) {
    ms += " \(database)"
  }
}

public extension DatabaseContext {
  
  /**
   * Fetch a set of objects using an typed ``TypedFetchSpecification``. This is
   * a helper wrapper that allows deriving the type of the results from the
   * fetch specification.
   *
   * - Parameters:
   *   - fetchSpecification: The description of what to fetch.
   *   - trackingContext:    The ``ObjectTrackingContext`` where fetched objects
   *                         are uniqued against.
   *   - yield:              A closure that receives all fetched objects.
   */
  @inlinable
  func objectsWithFetchSpecification<O>(
    fetchSpecification    : TypedFetchSpecification<O>,
    in    trackingContext : ObjectTrackingContext,
    _               yield : ( O ) throws -> Void
  ) throws
    where O: DatabaseObject
  {

    // Helper to type erase the fetchSpecification and jump into the main
    // method.
    func fetchObjectsWithFetchSpecification(
      _  fetchSpecification : FetchSpecification,
      in    trackingContext : ObjectTrackingContext,
      _               yield : ( O ) throws -> Void
    ) throws
      where O: DatabaseObject
    {
      try self.objectsWithFetchSpecification(fetchSpecification,
                                             in: trackingContext, yield)
    }
    try fetchObjectsWithFetchSpecification(fetchSpecification,
                                           in: trackingContext,
                                           yield)
  }
}
