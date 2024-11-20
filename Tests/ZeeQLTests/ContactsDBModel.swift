//
//  ContactsDBModel.swift
//  ZeeQL3
//
//  Created by Helge Hess on 16/05/17.
//  Copyright © 2017-2024 ZeeZide GmbH. All rights reserved.
//

import ZeeQL

enum ActiveRecordContactsDBModel {
  
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

enum PlainCodableContactsDBModel {
  
  static let model : Model = {
    do {
      return try Model.createFromTypes(Address.self, Person.self)
    }
    catch {
      print("COULD NOT CREATE TEST MODEL:", error)
      return Model(entities: [], tag: nil)
    }
  }()
  static let sqlModel : Model = {
    let model = (try? Model.createFromTypes(Address.self, Person.self))
                   ?? Model(entities: [])
    return ModelSQLizer().sqlizeModel(model)
  }()
  
  class Address   : Codable {
    // TODO:
    // Hm, why does this compile w/ 4.0? breaks 4.1 due to Person not being init
    // error: class 'PlainCodableContactsDBModel.Address' has no initializers
    // note: stored property 'person' without initial value prevents synthesized
    //       initializers
    var id        : Int
    var street    : String?
    var city      : String?
    var state     : String?
    var country   : String?
    var person    : Person
  }
  
  class Person    : Codable {
    var id        : Int
    var firstname : String?
    var lastname  : String
    var addresses : [ Address ]
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


import class Foundation.ProcessInfo
import class Foundation.FileManager
import struct Foundation.URL

internal func lookupTestDataPath() -> String {
  let fm = FileManager.default
  
  // This isn't set anymore when running the test in Xcode 16.1?
  if let path = ProcessInfo.processInfo.environment["SRCROOT"], !path.isEmpty {
    if fm.fileExists(atPath: "\(path)/data") { return "\(path)/data" }
    fatalError("could not locate data path in SRCROOT: \(path)")
  }
    
  do { // Xcode 16: runs in /private/tmp
    let path = FileManager.default.currentDirectoryPath
    if fm.fileExists(atPath: "\(path)/data") { return "\(path)/data" }
    
    // on Linux we seem to be in `/src/Tests/ZeeQLTests`, so step up two
    let url = URL(fileURLWithPath: path)
              .deletingLastPathComponent()
              .deletingLastPathComponent()
              .appendingPathComponent("data")
    if fm.fileExists(atPath: url.path) { return url.path }
    print("could not locate data path in current dir:", path)
  }
  
  do {
    let path = #filePath // Tests/ZeeQLTests/ContactsDBModel.swift
    let url = URL(fileURLWithPath: path)
              .deletingLastPathComponent()
              .deletingLastPathComponent()
              .deletingLastPathComponent()
              .appendingPathComponent("data")
    if fm.fileExists(atPath: url.path) { return url.path }
    print("could not locate data path in src dir:", path)
  }

  for ( key, value ) in ProcessInfo.processInfo.environment {
    print("\(key):", value)
  }
  fatalError("Missing data path?")
  //return "\(path)/data"
}
