//
//  EntityType.swift
//  ZeeQL
//
//  Created by Helge Hess on 02/03/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * This protocol is used for ORM classes which are guaranteed to have an Entity
 * assigned - for example when the Entity is specified in code.
 * If a class has a fixed Entity, we can do more tricks in Swift.
 *
 * Example:
 *
 *     class Address : ActiveRecord, EntityType {
 *       class Entity : OGoCodeEntity {
 *         let id     = -1
 *         let street : String? = nil
 *         let person = ToOne<Person>()
 *       }
 *       static let entity : ZeeQL.Entity = CodeEntity<Address>(Entity())
 *     }
 */
public protocol EntityType { // TODO: better name
  static var entity : Entity { get }
}


// TBD: This doesn't fly, I'm not completely sure why not. I cannot use it
//      in the Object like `Person: ActiveRecord, GEntityType` due to the
//      infamous:
//        "Protocol … can only be used as a generic constraint because it has
//         Self or associated type requirements"
public protocol GEntityType : EntityType { // TODO: better name
  associatedtype FullEntity : ZeeQL.Entity
  static var e : FullEntity { get }
}
public extension GEntityType {
  static var entity : ZeeQL.Entity { return e }
}


// MARK: - Convenience

public extension EntityType {
  // TBD: maybe rename, 'select' should run the actual select, right?
  
  // TBD: what do we want?
  // let objects = db.select(from: Persons.self)
  //       .where(Persons.login.like("*")
  //         .and(Persons.entity.addresses.zip.eq("39126"))
  //       .limit(4)
  //       .prefetch("addresses")
  // if FetchSpec would be a generic, we could derive a lot from the type
  //    let fs = FetchSpecification
  //               .select(from: Person) -> GFetchSpecification<Person>
  //               .where(login.like ...) // login can access Person
  // TBD: this could return a fetch-spec builder instead of recreating the
  //      specs all the time (FetchSpecificationRepresentable?)
  
  static func select(_ attributes: String...)
              -> FetchSpecification
  {
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.fetchAttributeNames = attributes.isEmpty ? nil : attributes
    return fs
  }
  
  // TBD: change this, 'select' should run the actual select, right?
  static func select(_ a1: Attribute, _ attributes: Attribute...)
              -> FetchSpecification
  {
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.fetchAttributeNames = ([ a1 ] + attributes).map { $0.name }
    return fs
  }
  
  
  // MARK: - Qualifiers
  
  static func `where`(_ q: Qualifier) -> FetchSpecification {
    // if we need no attributes
    var fs = ModelFetchSpecification(entity: Self.entity)
    fs.qualifier = q
    return fs
  }
  static func `where`(_ q: String, _ args: Any?...) -> FetchSpecification {
    var fs = ModelFetchSpecification(entity: Self.entity)
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
