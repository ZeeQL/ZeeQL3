//
//  ObjectStore.swift
//  ZeeQL
//
//  Created by Helge Hess on 17/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

public protocol ObjectWithGlobalID: AnyObject {
  // Quite often the objects themselves do store their own GID
  var globalID : GlobalID? { get }
}

/**
 * A store which stores objects :-)
 *
 * Current subclasses:
 * - ``ObjectTrackingContext`` (an object uniquer)
 * - ``DatabaseContext`` (a store on top of `Database`)
 */
public protocol ObjectStore {
  
  func objectsWithFetchSpecification<O>(
    _ fetchSpecification : FetchSpecification,
    in   trackingContext : ObjectTrackingContext,
    _            yield   : ( O ) throws -> Void
  ) throws
    where O: DatabaseObject
  
}
