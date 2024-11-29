//
//  ObjectTrackingContext.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * An ``ObjectTrackingContext`` is primarily used as an object uniquer.
 *
 * Unlike an ``EditingContext`` it doesn't track changes and e.g. is useful
 * in combination w/ ``ActiveRecord`` objects (which track changes inside the
 * object itself).
 *
 * An ``ObjectTrackingContext`` can be wrapped around a ``DatabaseContext``.
 * It can also be used in a nested way! (though that is more useful w/
 * editing contexts).
 */
open class ObjectTrackingContext : ObjectStore {
  
  public enum Error : Swift.Error {
    case FetchSpecificationHasUnresolvedBindings(FetchSpecification)
  }
  
  @usableFromInline
  var gidToObject = [ GlobalID : AnyObject ]()
  
  // the store from which we fetch objects, usually a DatabaseContext
  public let parentObjectStore : ObjectStore
  
  @inlinable
  public init(parent: ObjectStore) {
    parentObjectStore = parent
  }
  
  @inlinable
  public var rootObjectStore : ObjectStore {
    if let tc = parentObjectStore as? ObjectTrackingContext {
      return tc.rootObjectStore
    }
    else {
      return parentObjectStore
    }
  }

  /**
   * Fetches the objects for the given specification. This works by calling
   * ``objectsWithFetchSpecification(_:in:_:)`` with the tracking context
   * itself.
   */
  @inlinable
  open func objectsWithFetchSpecification<O>(_ type: O.Type = O.self,
                                             _ fs: FetchSpecification) throws
            -> [ O ]
    where O: DatabaseObject
  {
    var objects = [ O ]()
    try objectsWithFetchSpecification(fs) { objects.append($0) }
    return objects
  }
  
  /**
   * Fetches the objects for the given specification. This works by calling
   * ``objectsWithFetchSpecification(_:in:_:)`` with the tracking context
   * itself.
   */
  @inlinable
  open func objectsWithFetchSpecification<O>(_ fs: FetchSpecification,
                                             _ cb: ( O ) throws -> Void) throws
    where O: DatabaseObject
  {
    return try objectsWithFetchSpecification(fs, in: self, cb)
  }

  /**
   * This method asks the ``rootObjectStore`` to fetch the objects specified
   * in the _fs (usually a ``DatabaseContext``).
   *
   * Objects will get registered in the given tracking context (usually `self`
   * for ``ObjectTrackingContext``)
   *
   * This is the primitve method of ``ObjectStore``.
   */
  @inlinable
  open func objectsWithFetchSpecification<O>(
    _ fetchSpecification: FetchSpecification,
    in trackingContex: ObjectTrackingContext,
    _ yield: ( O ) throws -> Void
  ) throws
    where O: DatabaseObject
  {
    assert(!fetchSpecification.fetchesRawRows,
           "Attempt to use raw-rows fetch w/ tracking context?")
    if fetchSpecification.requiresAllQualifierBindingVariables {
      if let q = fetchSpecification.qualifier {
        if q.hasUnresolvedBindings {
          throw Error.FetchSpecificationHasUnresolvedBindings(fetchSpecification)
        }
      }
    }
    
    return try rootObjectStore
      .objectsWithFetchSpecification(fetchSpecification, in: trackingContex,
                                     yield)
  }
  
  
  // MARK: - Object Registry
  
  @inlinable
  public func record(object: AnyObject, with gid: GlobalID) {
    gidToObject[gid] = object
  }
  
  @inlinable
  open func forget(object: AnyObject) {
    guard let idx = gidToObject.firstIndex(where: { $0.value === object }) else
    {
      assertionFailure(
        "Did not find object to forget, not registered? \(object)")
      return
    }
    gidToObject.remove(at: idx)
  }

  @inlinable
  public func objectFor(globalID: GlobalID) -> AnyObject? {
    return gidToObject[globalID]
  }
  
  @inlinable
  public func globalIDFor(object: AnyObject) -> GlobalID? {
    if let smartObject = object as? ObjectWithGlobalID,
       let gid = smartObject.globalID { return gid }
    return gidToObject.firstKeyFor(value: object)
  }
  @inlinable
  public func globalIDFor<Object>(object: Object) -> GlobalID?
    where Object: ObjectWithGlobalID
  {
    return object.globalID ?? gidToObject.firstKeyFor(value: object)
  }

  @inlinable
  public func globalIDsFor(objects: [ AnyObject ]) -> [ GlobalID? ] {
    // TODO: this could reduce the Dictionary backward scanning
    return objects.map { globalIDFor(object: $0) }
  }
  @inlinable
  public func globalIDsFor<C>(objects: C) -> [ GlobalID? ]
    where C: Collection, C.Element: ObjectWithGlobalID
  {
    // TODO: this could reduce the Dictionary backward scanning
    return objects.map { globalIDFor(object: $0) }
  }

  @inlinable
  public var registeredObjects : [ AnyObject ] {
    return Array(gidToObject.values)
  }
  
  @inlinable
  public func reset() {
    gidToObject.removeAll()
  }
}


// MARK: - Helper

extension Dictionary where Value: AnyObject {

  @usableFromInline
  func firstKeyFor(value: Value) -> Key? {
    first(where: { $0.value === value })?.key
  }
  
}
