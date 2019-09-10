//
//  ObjectStore.swift
//  ZeeQL
//
//  Created by Helge Hess on 17/02/17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

public protocol ObjectWithGlobalID {
  // Quite often the objects themselves do store their own GID
  var globalID : GlobalID? { get }
}

/**
 * A store which stores objects :-)
 *
 * Current subclasses:
 * - `ObjectTrackingContext` (an object uniquer)
 * - `DatabaseContext` (a store on top of `Database`)
 */
public protocol ObjectStore {
  
  // TBD: add throws?
  func objectsWith(fetchSpecification : FetchSpecification,
                   in tc              : ObjectTrackingContext,
                   _ cb               : ( Any ) -> Void) throws
  
}
