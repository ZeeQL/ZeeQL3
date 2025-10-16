//
//  ModelTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 16/05/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class ModelTests: XCTestCase {
  
  let donald : Person = {
    let person = Person()
    person["id"] = 1000
    person["firstname"] = "Donald"
    person["lastname"]  = "Duck"
    return person
  }()
  
  func testPrimaryKeyExtraction() throws {
    let entity = Person.entity
    
    let person = donald
    
    let key = entity.primaryKeyForRow(person)
    XCTAssertNotNil(key)
    XCTAssertEqual(key?.count, 1)
    XCTAssertEqual(key?.keys.first, "id")
    XCTAssertTrue(key?.values.first is Int)
    XCTAssertEqual(key?.values.first as? Int, 1000)
  }

  func testPrimaryKeyQualifier() throws {
    let entity = Person.entity
    
    let person = donald
    
    let q = entity.qualifierForPrimaryKey(person)
    
    XCTAssertNotNil(q)
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "id")
    XCTAssertEqual(kvq.operation, .equalTo)
    XCTAssertEqual(kvq.value as? Int, 1000)
  }
  
  func testPrimaryKeyQualifierSnapshot() throws {
    let entity = Person.entity
    
    let person : Snapshot = [
      "id":        1000,
      "firstname": nil,
      "lastname":  "Duck"
    ];
    
    let q = entity.qualifierForPrimaryKey(person)
    
    XCTAssertNotNil(q)
    XCTAssert(q is KeyValueQualifier)
    let kvq = q as! KeyValueQualifier
    XCTAssertEqual(kvq.key, "id")
    XCTAssertEqual(kvq.operation, .equalTo)
    XCTAssertEqual(kvq.value as? Int, 1000)
  }
  
  // MARK: - CodeEntity based model
  
  class OGoObject : ActiveRecord {
    // TODO: actually add KVC to store the key in this var
    var id : Int { return value(forKey: "id") as! Int }
  }
  class Address : OGoObject, EntityType {
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
      
      let person        = ToOne<Person>() // auto: key: "company_id")
    }
    static let entity : ZeeQL.Entity = Entity()
  }
  
  class Person : OGoObject, EntityType {
    class Entity : CodeEntity<Person> {
      let table         = "person"
      let id            = Info.Int(column: "company_id")
      let objectVersion = Info.Int(column: "object_version")
      let isPerson      = Info.Int(column: "is_person")
      
      let login         = Attribute.OptString(width: 50)
      let isLocked      = Info.Int(column: "is_locked")
      let number        = Info.String(width: 100)
      
      let lastname      = Info.OptString(column: "name")
      
      let firstname     : String? = nil
      let middlename    : String? = nil
      
      let addresses     = ToMany<Address>()
    }
    
    static let e      = Entity()         // TODO: how to do this betta?
    static let entity : ZeeQL.Entity = e // this erases the type
    
    var addresses : [ Address ] { // TBD: Careful, does it conflict with KVC?
      return storedValue(forKey: "addresses") as? [ Address ] ?? []
    }
  }
  
  static var allTests = [
    ( "testPrimaryKeyExtraction",        testPrimaryKeyExtraction        ),
    ( "testPrimaryKeyQualifier",         testPrimaryKeyQualifier         ),
    ( "testPrimaryKeyQualifierSnapshot", testPrimaryKeyQualifierSnapshot ),
  ]
}
