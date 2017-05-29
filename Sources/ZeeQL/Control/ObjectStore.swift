//
//  ObjectStore.swift
//  ZeeQL
//
//  Created by Helge Hess on 17/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol ObjectWithGlobalID {
  // Quite often the objects themselves do store their own GID
  var globalID : GlobalID { get }
}

public protocol ObjectStore {
  
  // TBD: add throws?
  func objectsWith(fetchSpecification : FetchSpecification,
                   in tc              : ObjectTrackingContext,
                   _ cb               : ( Any ) -> Void) throws
  
}
