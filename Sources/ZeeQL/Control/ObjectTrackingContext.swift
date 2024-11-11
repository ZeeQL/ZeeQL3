//
//  ObjectTrackingContext.swift
//  ZeeQL
//
//  Created by Helge Hess on 03/03/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * An `ObjectTrackingContext` is primarily used as an object uniquer.
 *
 * Unlike an `ObjectEditingContext` it doesn't track changes and e.g. is useful
 * in combination w/ `ActiveRecord` objects (which track changes inside the
 * object itself).
 *
 * An `ObjectTrackingContext` can be wrapped around a `DatabaseContext`.
 * It can also be used in a nested way! (though that is more useful w/
 * editing contexts).
 */
open class ObjectTrackingContext : ObjectStore {
  
  public enum Error : Swift.Error {
    case FetchSpecificationHasUnresolvedBindings(FetchSpecification)
  }
  
  var gidToObject = [ GlobalID : AnyObject ]()
  
  // the store from which we fetch objects, usually a DatabaseContext
  public let parentObjectStore : ObjectStore
  
  init(parent: ObjectStore) {
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
   * `objectsWith(fetchSpecification:in:)` with the tracking context itself.
   */
  open func objectsWith(fetchSpecification fs: FetchSpecification) throws
            -> [ Any ]
  {
    var objects = [ Any ]()
    try objectsWith(fetchSpecification: fs, in: self) {
      objects.append($0)
    }
    return objects
  }
  
  /**
   * This method asks the `rootObjectStore` to fetch the objects specified
   * in the _fs.
   * Objects will get registered in the given tracking context.
   */
  open func objectsWith(fetchSpecification fs: FetchSpecification,
                        in tc: ObjectTrackingContext,
                        _ cb: ( Any ) -> Void) throws
  {
    if fs.requiresAllQualifierBindingVariables {
      if let q = fs.qualifier {
        if q.hasUnresolvedBindings {
          throw Error.FetchSpecificationHasUnresolvedBindings(fs)
        }
      }
    }
    
    return try rootObjectStore.objectsWith(fetchSpecification: fs, in: tc, cb)
  }
  
  
  // MARK: - Object Registry
  
  public func record(object: AnyObject, with gid: GlobalID) {
    gidToObject[gid] = object
  }
  public func forget(object: AnyObject) {
    if let gid = gidToObject.firstKeyFor(value: object) {
      gidToObject.removeValue(forKey: gid)
    }
  }

  public func objectFor(globalID: GlobalID) -> AnyObject? {
    return gidToObject[globalID]
  }
  
  public func globalIDFor(object: AnyObject) -> GlobalID? {
    if let smartObject = object as? ObjectWithGlobalID,
       let gid = smartObject.globalID { return gid }
    return gidToObject.firstKeyFor(value: object)
  }

  public func globalIDsFor(objects: [ AnyObject ]) -> [ GlobalID? ] {
    // TODO: this could reduce the Dictionary backward scanning
    return objects.map { globalIDFor(object: $0) }
  }
  
  public var registeredObjects : [ AnyObject ] {
    return Array(gidToObject.values)
  }
  
  public func reset() {
    gidToObject.removeAll()
  }
}


// MARK: - Helper


fileprivate extension Dictionary where Value: AnyObject {
  
  func firstKeyFor(value: Value) -> Key? {
    for ( k, v ) in self {
      if v === value { return k }
    }
    return nil
  }
  
}
