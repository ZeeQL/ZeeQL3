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
  open func objectsWithFetchSpecification<O>(_ fs: FetchSpecification,
                                             in tc: ObjectTrackingContext,
                                             _ cb: ( O ) throws -> Void) throws
    where O: DatabaseObject
  {
    if fs.requiresAllQualifierBindingVariables {
      if let q = fs.qualifier {
        if q.hasUnresolvedBindings {
          throw Error.FetchSpecificationHasUnresolvedBindings(fs)
        }
      }
    }
    
    return try rootObjectStore.objectsWithFetchSpecification(fs, in: tc, cb)
  }
  
  
  // MARK: - Object Registry
  
  @inlinable
  public func record(object: AnyObject, with gid: GlobalID) {
    gidToObject[gid] = object
  }
  @inlinable
  public func forget(object: AnyObject) {
    if let gid = gidToObject.firstKeyFor(value: object) {
      gidToObject.removeValue(forKey: gid)
    }
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
  public func globalIDsFor(objects: [ AnyObject ]) -> [ GlobalID? ] {
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
    for ( k, v ) in self {
      if v === value { return k }
    }
    return nil
  }
  
}
