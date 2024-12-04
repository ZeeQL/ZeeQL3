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

public protocol TypedEntityObject : DatabaseObject, EntityType {}
  // just a mixin
