//
//  ContactsDBModel.swift
//  ZeeQL3
//
//  Created by Helge Hess on 16/05/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import ZeeQL

enum ContactsDBModel {
  
  static let model = Model(entities: [ Person.entity, Address.entity ])
  
  class Address : ActiveRecord, EntityType {
    class Entity : CodeEntity<Address> {
      let table     = "address"
      let id        = Info.Int(column: "address_id")
      
      let street    = Info.OptString()
      let city      = Info.OptString()
      let state     = Info.OptString()
      let country   = Info.OptString()

      let personId  = Info.Int(column: "person_id")
      let person    = ToOne<Person>()
    }
    static let entity : ZeeQL.Entity = Entity()
  }
  
  class Person : ActiveRecord, EntityType {
    class Entity : CodeEntity<Person> {
      let table     = "person"
      let id        = Info.Int(column: "person_id")
      
      let firstname = Info.OptString()
      let lastname  = Info.String()
      
      let addresses = ToMany<Address>()
    }
    static let entity : ZeeQL.Entity = Entity()
  }
  
}

enum RawContactsDBModel { // as a schema SQLite3 fetch returns it

  static let model = Model(entities: [ person, address ])
  
  static let person : Entity = {
    let entity = ModelEntity(name: "person")
    entity.externalName = "person"
    entity.attributes = [
      ModelAttribute(name: "person_id", column: "person_id",
                     externalType: "INTEGER", allowsNull: false,
                     valueType: Int.self),
      ModelAttribute(name: "firstname", column: "firstname",
                     externalType: "VARCHAR", allowsNull: true,
                     valueType: Optional<String>.self),
      ModelAttribute(name: "lastname", column: "lastname",
                     externalType: "VARCHAR", allowsNull: false,
                     valueType: String.self)
    ]
    entity.primaryKeyAttributeNames = [ "person_id" ]
    
    // FancyModelMaker assigns reverse toMany relationships
    
    return entity
  }()
  
  static let address : Entity = {
    let entity = ModelEntity(name: "address")
    entity.externalName = "address"
    entity.attributes = [
      ModelAttribute(name: "address_id", column: "address_id",
                     externalType: "INTEGER", allowsNull: false,
                     valueType: Int.self),
      ModelAttribute(name: "street", column: "street",
                     externalType: "VARCHAR", allowsNull: true,
                     valueType: Optional<String>.self),
      ModelAttribute(name: "city", column: "city",
                     externalType: "VARCHAR", allowsNull: true,
                     valueType: Optional<String>.self),
      ModelAttribute(name: "state", column: "state",
                     externalType: "VARCHAR", allowsNull: true,
                     valueType: Optional<String>.self),
      ModelAttribute(name: "country", column: "country",
                     externalType: "VARCHAR", allowsNull: true,
                     valueType: Optional<String>.self),
      ModelAttribute(name: "person_id", column: "person_id",
                     externalType: "INTEGER", allowsNull: true,
                     valueType: Optional<Int>.self)
    ]
    
    // FancyModelMaker assigns nice names
    
    let toPerson = ModelRelationship(name: "constraint0", isToMany: false,
                                     source: entity, destination: nil)
    toPerson.destinationEntityName = "person"
    toPerson.joins = [ Join(source: "person_id", destination: "person_id") ]
    entity.relationships = [ toPerson ]
    
    entity.primaryKeyAttributeNames = [ "address_id" ]
    return entity
  }()
}
