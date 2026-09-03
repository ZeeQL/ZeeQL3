//
//  SQLite3ModelTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14/04/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import ZeeQL

class SQLite3ModelTests: XCTestCase {
  
  var adaptor : SQLite3Adaptor = {
    #if ZEE_BUNDLE_RESOURCES
      let bundle = Bundle(for: SQLite3ModelTests.self)
      let url    = bundle.url(forResource: "OGo", withExtension: "sqlite3")
      guard let path = url?.path else { return SQLite3Adaptor("OGo.sqlite3") }
      //NSLog("URL: \(url) \(path)")
      return SQLite3Adaptor(path)
    #else
      let dataPath = lookupTestDataPath()
      return SQLite3Adaptor("\(dataPath)/OGo.sqlite3")
    #endif
  }()
  

  func testDescribeDatabaseNames() throws {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    let values  = try channel.describeDatabaseNames()
    
    XCTAssertEqual(values.count, 1)
    XCTAssertEqual(values[0], "main")
  }
  
  func testDescribeOGoTableNames() throws {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    let values  = try channel.describeTableNames()
    
    XCTAssertEqual(values.count, 63)
    XCTAssert(values.contains("appointment"))
    XCTAssert(values.contains("person"))
    XCTAssert(values.contains("address"))
  }
  
  func testFetchModel() throws {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    let model = try SQLite3ModelFetch(channel: channel).fetchModel()
    
    XCTAssertEqual(model.entities.count, 63)
    let values = model.entityNames
    XCTAssert(values.contains("appointment"))
    XCTAssert(values.contains("person"))
    XCTAssert(values.contains("address"))
    
    XCTAssertNotNil(model.tag, "model has no tag")
  }
  
  func testSchemaTag() throws {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    let modelFetch = SQLite3ModelFetch(channel: channel)
    
    try channel.performSQL("DROP TABLE IF EXISTS zeeqltesttag")
    defer {
      _ = try? channel.performSQL("DROP TABLE IF EXISTS zeeqltesttag")
    }
    
    let tag1 = try modelFetch.fetchModelTag()
    let tag2 = try modelFetch.fetchModelTag()
    XCTAssert(tag1.isEqual(to: tag2))
    
    try channel.performSQL("CREATE TABLE zeeqltesttag ( id INT )")
    let tag3 = try modelFetch.fetchModelTag()
    XCTAssert(!tag2.isEqual(to: tag3))
    XCTAssert(!tag1.isEqual(to: tag3))
    
    let tag4 = try modelFetch.fetchModelTag()
    XCTAssert(tag3.isEqual(to: tag4))
    
    try channel.performSQL("ALTER TABLE zeeqltesttag ADD COLUMN name TEXT")
    let tag5 = try modelFetch.fetchModelTag()
    XCTAssert(!tag4.isEqual(to: tag5))
    XCTAssert(!tag1.isEqual(to: tag5))

    try channel.performSQL("DROP TABLE zeeqltesttag")
    let tag6 = try modelFetch.fetchModelTag()
    XCTAssert(!tag5.isEqual(to: tag6))
    XCTAssert(!tag4.isEqual(to: tag6))
    XCTAssert(!tag1.isEqual(to: tag6))
  }

  func testDescribeTableNamesBindsLikePattern() throws {
    let channel = try SQLite3Adaptor(":memory:").openChannel()
    try channel.performSQL("CREATE TABLE normal(id INTEGER)")
    try channel.performSQL("CREATE TABLE \"odd'name\"(id INTEGER)")
    let fetch = SQLite3ModelFetch(channel: channel)

    XCTAssertEqual(try fetch.describeTableNames(like: "odd'%"),
                   [ "odd'name" ])
    XCTAssertTrue(
      try fetch.describeTableNames(like: "%' OR 1=1 --").isEmpty)
  }

  func testDescribeEntityQuotesTableName() throws {
    let channel = try SQLite3Adaptor(":memory:").openChannel()
    try channel.performSQL(
      "CREATE TABLE \"parent table\"(\"id\" INTEGER PRIMARY KEY)")
    try channel.performSQL(
      """
      CREATE TABLE "child)""table"(
        "parent id" INTEGER,
        FOREIGN KEY("parent id") REFERENCES "parent table"("id"))
      """)
    let fetch = SQLite3ModelFetch(channel: channel)

    let entity = try fetch.describeEntityWithTableName("child)\"table")
    XCTAssertEqual(entity.externalName, "child)\"table")
    XCTAssertNotNil(entity[attribute: "parent id"])
    XCTAssertEqual(entity.relationships.count, 1)
    let relationship = try XCTUnwrap(
      entity.relationships[0] as? ModelRelationship)
    XCTAssertEqual(relationship.destinationEntityName, "parent table")
  }
  
  
  // MARK: - Non-ObjC Swift Support

  static var allTests = [
    ( "testDescribeDatabaseNames", testDescribeDatabaseNames ),
    ( "testDescribeOGoTableNames", testDescribeOGoTableNames ),
    ( "testFetchModel",            testFetchModel ),
    ( "testSchemaTag",             testSchemaTag  ),
    ( "testDescribeTableNamesBindsLikePattern",
      testDescribeTableNamesBindsLikePattern ),
    ( "testDescribeEntityQuotesTableName",
      testDescribeEntityQuotesTableName ),
  ]
}
