//
//  EntityType.swift
//  ZeeQL
//
//  Created by Helge Hess on 02/03/2017.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

/**
 * This protocol is used for ORM classes which are guaranteed to have an
 * ``Entity`` assigned, for example when the ``Entity`` is specified in code.
 * If a class has a fixed Entity, we can do more tricks in Swift.
 *
 * Example:
 * ```swift
 * class Address : ActiveRecord, EntityType {
 *   class Entity : OGoCodeEntity {
 *     let id     = -1
 *     let street : String? = nil
 *     let person = ToOne<Person>()
 *   }
 *   static let entity : ZeeQL.Entity = CodeEntity<Address>(Entity())
 * }
 * ```
 */
public protocol EntityType { // TODO: better name
  static var entity : Entity { get }
}

/**
 * This protocol is used for ORM classes which are guaranteed to have an
 * ``Entity`` assigned, for example when the ``Entity`` is specified in code.
 * If a class has a fixed Entity, we can do more tricks in Swift.
 *
 * It enhances ``EntityType`` w/ a PAT for the concrete entity type.
 *
 * Example:
 * ```swift
 * class Address : ActiveRecord, TypedEntityType {
 *   class Entity : OGoCodeEntity {
 *     let id     = -1
 *     let street : String? = nil
 *     let person = ToOne<Person>()
 *   }
 *   static let e = Entity()
 * }
 * ```
 */
public protocol TypedEntityType : EntityType { // TODO: better name
  associatedtype FullEntity : ZeeQL.Entity
  static var e : FullEntity { get }
}

public extension TypedEntityType {
  
  @inlinable
  static var entity : ZeeQL.Entity { return e }
}


// MARK: - Convenience

public extension EntityType {
  // TBD: maybe rename, 'select' should run the actual select, right?
  
  @inlinable
  static func select(_ attributes: String...)
              -> FetchSpecification
  {
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.fetchAttributeNames = attributes.isEmpty ? nil : attributes
    return fs
  }
  
  // TBD: change this, 'select' should run the actual select, right?
  @inlinable
  static func select(_ a1: Attribute, _ attributes: Attribute...)
              -> FetchSpecification
  {
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.fetchAttributeNames = ([ a1 ] + attributes).map { $0.name }
    return fs
  }
  
  
  // MARK: - Qualifiers
  
  @inlinable
  static func `where`(_ q: Qualifier) -> FetchSpecification {
    // if we need no attributes
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.qualifier = q
    return fs
  }
  @inlinable
  static func `where`(_ q: String, _ args: Any?...) -> FetchSpecification {
    var fs = ModelFetchSpecification(entity: Self.entity)
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
}
public extension TypedEntityType where Self: DatabaseObject {
  // TBD: maybe rename, 'select' should run the actual select, right?
  
  @inlinable
  static func select(_ attributes: String...)
              -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    fs.fetchAttributeNames = attributes.isEmpty ? nil : attributes
    return fs
  }
  
  // TBD: change this, 'select' should run the actual select, right?
  @inlinable
  static func select(_ a1: Attribute, _ attributes: Attribute...)
              -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    fs.fetchAttributeNames = ([ a1 ] + attributes).map { $0.name }
    return fs
  }
  
  
  // MARK: - Qualifiers
  
  @inlinable
  static func `where`(_ q: Qualifier) -> TypedFetchSpecification<Self> {
    // if we need no attributes
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    fs.qualifier = q
    return fs
  }
  @inlinable
  static func `where`(_ q: String, _ args: Any?...)
              -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>(entity: Self.entity)
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
}


public protocol TypedEntityObject : DatabaseObject, EntityType {}
  // just a mixin

public extension TypedEntityObject {
  
  static func `where`(_ q: Qualifier) -> TypedFetchSpecification<Self> {
    var fs = TypedFetchSpecification<Self>()
    fs.qualifier = q
    return fs
  }
  static func `where`(_ q: String, _ args: Any?...)
    -> TypedFetchSpecification<Self>
  {
    var fs = TypedFetchSpecification<Self>()
    let parser = QualifierParser(string: q, arguments: args)
    fs.qualifier = parser.parseQualifier()
    return fs
  }
}
