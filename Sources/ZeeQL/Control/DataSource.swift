//
//  DataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * A DataSource performs a query against some 'entity', in the ORM usually a
 * database table (which is mapped to an Entity).
 *
 * The ZeeQL DataSources always have an FetchSpecification which specifies
 * the environment for fetches.
 *
 * The DataSource is very general, but ORM specific subclasses include:
 * - DatabaseDataSource
 * - ActiveDataSource
 * - AdaptorDataSource
 */
open class DataSource<Object: SwiftObject>: EquatableType, Equatable {
  // Used to be a protocol, but Swift 3 and generic protocols ....
  
  open var fetchSpecification : FetchSpecification?
  
  open func fetchObjects(yield: ( Object ) -> Void) throws {
    fatalError("Subclass must implement: \(#function)")
  }
  open func fetchCount() throws -> Int { // inefficient default implementation
    var count = 0
    try fetchObjects(yield: { _ in count += 1 })
    return count
  }
  
  // MARK: - Equatable
  
  @inlinable
  public func isEqual(to object: Any?) -> Bool {
    guard let other = object as? DataSource else { return false }
    return other.isEqual(to: self)
  }
  @inlinable
  public func isEqual(to object: DataSource) -> Bool {
    return self === object
  }
  
  @inlinable
  public static func ==(lhs: DataSource, rhs: DataSource) -> Bool {
    return lhs.isEqual(to: rhs)
  }
}

/**
 * Protocol which enforces that a type is a class type (to be used as a generic
 * constraint).
 * Like `AnyObject` w/o the `@objc`.
 */
public protocol SwiftObject: AnyObject {
  // is there a standard protocol for this? `AnyObject` also does @objc ...
}

public extension DataSource {
  
  @inlinable
  func fetchObjects() throws -> [ Object ] {
    var objects = [ Object ]()
    try fetchObjects { objects.append($0) }
    return objects
  }
  
}
