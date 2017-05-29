//
//  DataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * A DataSource performs a query against some 'entity', in the ORM usually a
 * database table (which is mapped to an Entity).
 *
 * The ZeeQL DataSources always have an FetchSpecification which specifies
 * the environment for fetches.
 */
open class DataSource<Object: SwiftObject> {
  // Used to be a protocol, but Swift 3 and generic protocols ....
  
  open var fetchSpecification : FetchSpecification?
  
  open func fetchObjects(cb: ( Object ) -> Void) throws {
    fatalError("Subclass must implement: \(#function)")
  }
  open func fetchCount() throws -> Int {
    fatalError("Subclass must implement: \(#function)")
  }
}

/**
 * Protocol which enforces that a type is a class type (to be used as a generic
 * constraint).
 * Like `AnyObject` w/o the `@objc`.
 */
public protocol SwiftObject: class {
  // is there a standard protocol for this? `AnyObject` also does @objc ...
}

public extension DataSource {
  
  func fetchObjects() throws -> [ Object ] {
    var objects = [ Object ]()
    try fetchObjects { objects.append($0) }
    return objects
  }
  
}
