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
