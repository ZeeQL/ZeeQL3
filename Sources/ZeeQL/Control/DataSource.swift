//
//  DataSource.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * A DataSource performs a query against something, in the ORM usually a
 * database table (which is mapped to an ``Entity``).
 *
 * The ZeeQL DataSources always have an FetchSpecification which specifies
 * the environment for fetches.
 *
 * The DataSource is very general, but ORM specific subclasses include:
 * - ``DatabaseDataSource``
 * - ``ActiveDataSource``
 * - ``AdaptorDataSource``
 */
public protocol DataSourceType<Object>: EquatableType, Equatable {
  
  associatedtype Object: SwiftObject
  
  var fetchSpecification : FetchSpecification? { get set }
  
  func fetchObjects(yield: ( Object ) -> Void) throws
  func fetchCount() throws -> Int
}

public extension DataSourceType {
  
  @inlinable
  func fetchCount() throws -> Int { // inefficient default implementation
    var count = 0
    try fetchObjects(yield: { _ in count += 1 })
    return count
  }
}

public extension DataSourceType where Self: AnyObject { // Equatable
  
  @inlinable
  func isEqual(to object: Any?) -> Bool {
    guard let other = object as? Self else { return false }
    return other.isEqual(to: self)
  }
  @inlinable
  func isEqual(to object: Self) -> Bool { return self === object }
  
  @inlinable
  static func ==(lhs: Self, rhs: Self) -> Bool { return lhs.isEqual(to: rhs) }
}

/**
 * A DataSource performs a query against something, in the ORM usually a
 * database table (which is mapped to an ``Entity``).
 *
 * The ZeeQL DataSources always have an FetchSpecification which specifies
 * the environment for fetches.
 *
 * The DataSource is very general, but ORM specific subclasses include:
 * - ``DatabaseDataSource``
 * - ``ActiveDataSource``
 * - ``AdaptorDataSource``
 */
open class DataSource<Object: SwiftObject>: DataSourceType {
  // Used to be a protocol, but Swift 3 and generic protocols ....
  
  open var fetchSpecification : FetchSpecification?
  
  open func fetchObjects(yield: ( Object ) -> Void) throws {
    fatalError("Subclass must implement: \(#function)")
  }
  
  // MARK: - Equatable
  
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

public extension DataSourceType {
  
  @inlinable
  func fetchObjects() throws -> [ Object ] {
    var objects = [ Object ]()
    try fetchObjects { objects.append($0) }
    return objects
  }
}
