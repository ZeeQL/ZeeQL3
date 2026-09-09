//
//  SQLite3OGoAdaptorTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import ZeeQL

class SQLite3OGoAdaptorTests: AdaptorOGoTestCase {
  
  override var adaptor : Adaptor! { return _adaptor }
  private var _adaptor    : SQLite3Adaptor?
  private var databaseURL : URL?

  override func setUpWithError() throws {
    let url = try temporaryTestDatabase(named: "OGo.sqlite3")
    databaseURL = url
    _adaptor    = SQLite3Adaptor(url.path)
  }

  override func tearDownWithError() throws {
    _adaptor = nil
    if let databaseURL {
      try FileManager.default.removeItem(at: databaseURL)
    }
    databaseURL = nil
  }

  func testRawAdaptorChannelQuery() throws { try runRawAdaptorChannelQuery() }
  func testEvaluateQueryExpression() throws { try runEvaluateQueryExpression() }
  func testRawTypeSafeQuery() throws { try runRawTypeSafeQuery() }
  func testSimpleTX() throws { try runSimpleTX() }

  func testAdaptorDataSourceFindByID() throws {
    try runAdaptorDataSourceFindByID()
  }

  func testBasicReflection() throws { try runBasicReflection() }
  func testTableReflection() throws { try runTableReflection() }
  func testCodeSchema() throws { try runCodeSchema() }

  func testCodeSchemaWithJoinQualifier() throws {
    try runCodeSchemaWithJoinQualifier()
  }

  func testCodeSchemaWithRelshipPrefetch() throws {
    try runCodeSchemaWithRelshipPrefetch()
  }

  func testCodeSchemaWithTypedFetchSpec() throws {
    try runCodeSchemaWithTypedFetchSpec()
  }

  func testCount() throws {
    let db = Database(adaptor: adaptor)

    class OGoObject : ActiveRecord {
      // TODO: actually add KVC to store the key in this var
      var id : Int { return valueForKey("id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
    }
    
    class Person : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let isPerson      = Info.Int(column: "is_person")
        
        let login         = Info.OptString(width: 50)
        let isLocked      = Info.Int(column: "is_locked")
        let number        = Info.String(width: 100)
        
        let lastname      = Info.OptString(column: "name")
        let firstname     : String? = nil
        let middlename    : String? = nil
      }
      static let fields = Entity()
      static let entity : ZeeQL.Entity = fields
    }
    
    let persons = ActiveDataSource<Person>(database: db)
    
    persons.fetchSpecification = Person
      .where(Person.fields.login.like("*"))
      .limit(4)
      .order(by: Person.fields.login)
    
    do {
      let count = try persons.fetchCount()
      if printResults {
        print("got person count: #\(count)")
      }
      XCTAssert(count > 2)
    }
    catch {
      XCTAssertNil(error, "catched error: \(error)")
    }
  }

  func testFetchGlobalIDs() throws {
    let db = Database(adaptor: adaptor)

    class OGoObject : ActiveRecord {
      // TODO: actually add KVC to store the key in this var
      var id : Int { return valueForKey("id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
    }
    
    class Person : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let isPerson      = Info.Int(column: "is_person")
        
        let login         = Info.OptString(width: 50)
        let isLocked      = Info.Int(column: "is_locked")
        let number        = Info.String(width: 100)
        
        let lastname      = Info.OptString(column: "name")
        let firstname     : String? = nil
        let middlename    : String? = nil
      }
      static let fields = Entity()
      static let entity : ZeeQL.Entity = fields
    }
    
    let persons = ActiveDataSource<Person>(database: db)
    
    persons.fetchSpecification = Person
      .where(Person.fields.login.like("*"))
      .limit(4)
      .order(by: Person.fields.login)
    
    do {
      let gids = try persons.fetchGlobalIDs()
      if printResults {
        print("got person count: \(gids)")
      }
      XCTAssert(gids.count > 2)
      
      // and now lets fetch the GIDs
      
      let objects = try persons.fetchObjects(with: gids)
      if printResults {
        print("got persons: #\(objects.count)")
      }
      XCTAssertEqual(objects.count, gids.count)
    }
    catch {
      XCTAssertNil(error, "catched error: \(error)")
    }
  }
  
}
