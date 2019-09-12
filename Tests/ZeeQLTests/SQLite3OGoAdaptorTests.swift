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
  
  override var adaptor : Adaptor! {
    XCTAssertNotNil(_adaptor)
    return _adaptor
  }
  
  var _adaptor : SQLite3Adaptor = {
    var pathToTestDB : String = {
      #if ZEE_BUNDLE_RESOURCES
        let bundle = Bundle(for: type(of: self) as! AnyClass)
        let url    = bundle.url(forResource: "OGo", withExtension: "sqlite3")
        guard let path = url?.path else { return "OGo.sqlite3" }
        return path
      #else
        let dataPath = lookupTestDataPath()
        return "\(dataPath)/OGo.sqlite3"
      #endif
    }()
    return SQLite3Adaptor(pathToTestDB)
  }()

  func testCount() throws {
    let db = Database(adaptor: adaptor)

    class OGoObject : ActiveRecord {
      // TODO: actually add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
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
      var id : Int { return value(forKey: "id") as! Int }
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
  
  // MARK: - Non-ObjC Swift Support

  static var allTests = [
    // super
    ( "testRawAdaptorChannelQuery",  testRawAdaptorChannelQuery  ),
    ( "testEvaluateQueryExpression", testEvaluateQueryExpression ),
    ( "testRawTypeSafeQuery",        testRawTypeSafeQuery        ),
    ( "testSimpleTX",                testSimpleTX                ),
    ( "testAdaptorDataSourceFindByID", testAdaptorDataSourceFindByID ),
    ( "testBasicReflection",         testBasicReflection         ),
    ( "testTableReflection",         testTableReflection         ),
    ( "testCodeSchema",              testCodeSchema              ),
    ( "testCodeSchemaWithJoinQualifier",   testCodeSchemaWithJoinQualifier ),
    ( "testCodeSchemaWithRelshipPrefetch", testCodeSchemaWithRelshipPrefetch ),
    ( "testCodeSchemaWithTypedFetchSpec",  testCodeSchemaWithTypedFetchSpec ),
    // own
    ( "testCount", testCount ),
  ]
}
