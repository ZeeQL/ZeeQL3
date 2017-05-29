//
//  SchemaGenerationTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class SchemaGenerationTests: XCTestCase {
  
  func testCodeSchema() {
    
    class Address : ActiveRecord, EntityType {
      class Entity : CodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        
        let id            = Info.Int(column: "address_id")
        let objectVersion = Info.Int(column: "object_version")
        
        let dbStatus      = Info.String(column: "db_status", width: 50)
        
        let companyId     = Info.Int(column: "company_id")
        
        let type          = Info.String(width: 50) // TODO: an enum?
        
        let name1         = Info.OptString()
        let name2         = Info.OptString()
        let name3         = Info.OptString()
        let street        = Info.OptString()
        let zip           = Info.OptString(width: 50)
        let zipcity       = Info.OptString()
        let country       = Info.OptString()
        let state         = Info.OptString()
        let district      = Info.OptString()
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    let entity = Address.entity
    XCTAssertEqual(entity.externalName, "address")
    
    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 14)
    
    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
  }
  
  func testCodeSchemaNativeTypes() {
    
    class Address : ActiveRecord, EntityType {
      class Entity : CodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        
        let id            = Info.Int(column: "address_id")
        let objectVersion = Info.Int(column: "object_version")
        
        let dbStatus      = Info.String(column: "db_status", width: 50)
        
        let companyId     = Info.Int(column: "company_id")
        
        let type          = Info.String(width: 50) // TODO: an enum?
        
        let name1         : String? = nil
        let name2         : String? = nil
        let name3         : String? = nil
        let street        : String? = nil
        let zip           = Info.OptString(width: 50)
        let zipcity       : String? = nil
        let country       : String? = nil
        let state         : String? = nil
        let district      : String? = nil
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    let entity = Address.entity
    XCTAssertEqual(entity.externalName, "address")
    
    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 14)
    
    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
  }
  
  func testCodeSchemaWithInheritance() {
    
    class OGoObject : ActiveRecord {
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
      let dbStatus      = Info.String(column: "db_status", width: 50)
    }
    
    class Address : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        
        let id            = Info.Int(column: "address_id")
        let companyId     = Info.Int(column: "company_id")
        let type          = Info.String(width: 50) // TODO: an enum?
        
        let name1         = Info.OptString()
        let name2         = Info.OptString()
        let name3         = Info.OptString()
        let street        = Info.OptString()
        let zip           = Info.OptString(width: 50)
        let zipcity       = Info.OptString()
        let country       = Info.OptString()
        let state         = Info.OptString()
        let district      = Info.OptString()
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    let entity = Address.entity
    XCTAssertEqual(entity.externalName, "address")
    
    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 14)
    
    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
  }

  func testCodeSchemaWithRelationships() {
    class OGoObject : ActiveRecord {
      // TODO: actuall add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
    }
    
    
    class Address : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        let id            = Info.Int(column: "address_id")
        let companyId     = Info.Int(column: "company_id")
        let name1         : String? = nil
        let street        : String? = nil
        let zipcity       : String? = nil
        
        let person        = ToOne<Person>()
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    class Person : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let isPerson      = Info.Int(column: "is_person")
        
        let lastname      = Info.OptString(column: "name")
        let firstname     : String? = nil
        
        let addresses     = ToMany<Address>(on: "companyId")
        // or ToMany<Address>(on: Address.info.companyId?
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    XCTAssertEqual(Person.entity.relationships.count,  1)
    XCTAssertEqual(Address.entity.relationships.count, 1)
    guard Address.entity.relationships.count == 1,
          Person.entity.relationships.count  == 1
     else { return }
    
    let rsP = Person.entity.relationships[0]
    XCTAssertEqual(rsP.joins.count, 1)
    let rsPJ = rsP.joins[0]
    XCTAssertEqual(rsPJ.sourceName,      "id")
    XCTAssertEqual(rsPJ.destinationName, "companyId")
    
    let rsA = Address.entity.relationships[0]
    XCTAssertEqual(rsA.joins.count, 1)
    let rsAJ = rsA.joins[0]
    XCTAssertEqual(rsAJ.sourceName,      "companyId")
    XCTAssertEqual(rsAJ.destinationName, "id")
  }

  func testCodeSchemaWithAutoRelationships() {
    class OGoObject : ActiveRecord {
      // TODO: actuall add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
    }
    
    
    class Address : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        let id            = Info.Int(column: "address_id")
        let companyId     = Info.Int(column: "company_id")
        let name1         : String? = nil
        let street        : String? = nil
        let zipcity       : String? = nil
        
        let person        = ToOne<Person>()
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    class Person : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let isPerson      = Info.Int(column: "is_person")
        
        let lastname      = Info.OptString(column: "name")
        let firstname     : String? = nil
        
        let addresses     = ToMany<Address>()
        // or ToMany<Address>(on: Address.info.companyId?
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    XCTAssertEqual(Person.entity.relationships.count,  1)
    XCTAssertEqual(Address.entity.relationships.count, 1)
    guard Address.entity.relationships.count == 1,
          Person.entity.relationships.count  == 1
     else { return }
    
    let rsP = Person.entity.relationships[0]
    XCTAssertEqual(rsP.joins.count, 1)
    let rsPJ = rsP.joins[0]
    XCTAssertEqual(rsPJ.sourceName,      "id")
    XCTAssertEqual(rsPJ.destinationName, "companyId")
    
    let rsA = Address.entity.relationships[0]
    XCTAssertEqual(rsA.joins.count, 1)
    let rsAJ = rsA.joins[0]
    XCTAssertEqual(rsAJ.sourceName,      "companyId")
    XCTAssertEqual(rsAJ.destinationName, "id")
  }
  
  func testCodeObjectSchema() {
    class OGoObject : ActiveRecord {
      let objectVersion = Value.Int(column: "object_version", 0)
    }
    
    class Address : OGoObject, CodeObjectType {
      // Boxed values, annotated with Attribute information
      let id            = Value.Int   (column: "address_id")
      let dbStatus      = Value.String(column: "db_status", width: 50)
      let companyId     = Value.Int   (column: "company_id")
      let type          = Value.String(width: 50) // TODO: an enum?

      // TODO: We can do this, but we don't get automagic KVC then.
      let name1         : String? = nil
      let name2         : String? = nil
      let name3         : String? = nil
      let street        : String? = nil
      let zip           = Value.OptString(width: 50, nil)
      let zipcity       : String? = nil
      let country       : String? = nil
      let state         : String? = nil
      let district      : String? = nil
      
      // TODO
      // - This could be a 'fault'.
      //let person        = ToOne<Person>() // auto: key: "company_id")
            
      static let entity : ZeeQL.Entity
                        = CodeObjectEntity<Address>(table: "address")
    }

    let entity = Address.entity
    XCTAssertEqual(entity.externalName, "address")
    
    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 14)
    
    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
  }
}
