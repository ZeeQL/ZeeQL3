//
//  SQLite3AdaptorTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 06/03/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import ZeeQL

class SQLite3AdaptorTests: XCTestCase {
  
  var adaptor : SQLite3Adaptor = {
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
  
  let entity  : Entity = {
    let e = ModelEntity(name: "person")
    e.attributes = [
      ModelAttribute(name: "id",    column: "company_id"),
      ModelAttribute(name: "login")
    ]
    return e
  }()

  func testBindQuery() {
    let q = qualifierWithFormat( "login = %@", "template")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let fs = ModelFetchSpecification(entity: entity, qualifier: q)
    let expr = adaptor.expressionFactory.selectExpressionForAttributes(
      entity.attributes, fs, entity
    )
    XCTAssertEqual(expr.statement,
                   "SELECT BASE.\"company_id\", BASE.\"login\" " +
                     "FROM \"person\" AS BASE " +
                    "WHERE BASE.\"login\" = ?",
                   "unexpected SQL result")
    let bindings = expr.bindVariables
    XCTAssertEqual(bindings.count, 1, "unexpected binding count")
    XCTAssertEqual(bindings[0].value as? String, "template")
    
    do {
      let channel = try adaptor.openChannel()
      defer { adaptor.releaseChannel(channel) }
      
      var records = [ AdaptorRecord ]()
      try channel.evaluateQueryExpression(expr, entity.attributes) { record in
        records.append(record)
      }
      
      XCTAssertEqual(records.count, 1, "there should be one template record")
    }
    catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFailedCommitPreservesTransactionState() throws {
    let channel = try SQLite3Adaptor(":memory:").openChannel()
    try channel.performSQL("PRAGMA foreign_keys = ON")
    try channel.performSQL("CREATE TABLE parent(id INTEGER PRIMARY KEY)")
    try channel.performSQL(
      """
      CREATE TABLE child(parent_id INTEGER REFERENCES parent(id)
                         DEFERRABLE INITIALLY DEFERRED)
      """)

    try channel.begin()
    try channel.performSQL("INSERT INTO child(parent_id) VALUES (1)")
    XCTAssertThrowsError(try channel.commit())
    XCTAssertTrue(channel.isTransactionInProgress)
    try channel.rollback()
    XCTAssertFalse(channel.isTransactionInProgress)
  }

  func testFailedRollbackReflectsSQLiteTransactionState() throws {
    let channel = try SQLite3Adaptor(":memory:").openChannel()
    try channel.begin()
    try channel.performSQL("ROLLBACK TRANSACTION;")

    XCTAssertThrowsError(try channel.rollback())
    XCTAssertFalse(channel.isTransactionInProgress)
  }

  
  // MARK: - Non-ObjC Swift Support
  
  static var allTests = [
    ( "testBindQuery", testBindQuery ),
    ( "testFailedCommitPreservesTransactionState",
      testFailedCommitPreservesTransactionState ),
    ( "testFailedRollbackReflectsSQLiteTransactionState",
      testFailedRollbackReflectsSQLiteTransactionState ),
  ]
}
