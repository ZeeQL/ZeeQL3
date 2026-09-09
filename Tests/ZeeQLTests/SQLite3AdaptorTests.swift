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

  func testDeferredForeignKeysAreReappliedToPooledChannel() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    let first = try adaptor.openChannelFromPool()

    try first.begin()
    XCTAssertEqual(try deferForeignKeysValue(first), 1)
    try first.commit()
    XCTAssertEqual(try deferForeignKeysValue(first), 0)
    adaptor.releaseChannel(first)

    let reused = try adaptor.openChannelFromPool()
    XCTAssertTrue(first as AnyObject === reused as AnyObject)
    try reused.begin()
    XCTAssertEqual(try deferForeignKeysValue(reused), 1)
    try reused.rollback()
    adaptor.releaseChannel(reused)
  }

  func testSQLLoggingIsDisabledByDefault() throws {
    let logger = CapturingLogger()
    let adaptor = SQLite3Adaptor(":memory:")
    adaptor.log = logger
    let channel = try adaptor.openChannel()

    try channel.performSQL("SELECT 'private-value'")
    XCTAssertTrue(logger.messages.isEmpty)
  }

  func testBindValuesAreRedactedFromSQLLoggingByDefault() throws {
    var options = SQLite3Adaptor.RuntimeOptions()
    options.logSQL = true
    let logger = CapturingLogger()
    let adaptor = SQLite3Adaptor(":memory:", options: options)
    adaptor.log = logger
    let channel = try adaptor.openChannel()
    let expression = SQLExpression(entity: nil)
    expression.statement = "SELECT ?"
    expression.bindVariables = [
      SQLExpression.BindVariable(attribute: nil, value: "private-value")
    ]

    try channel.evaluateQueryExpression(expression, nil) { _ in }
    XCTAssertTrue(logger.messages.contains { $0.contains("SELECT ?") })
    XCTAssertFalse(logger.messages.contains { $0.contains("private-value") })
  }

  private func deferForeignKeysValue(_ channel: AdaptorChannel)
    throws -> Int64
  {
    var value: Int64?
    try channel.select("PRAGMA defer_foreign_keys") {
      (result: Int64) in value = result
    }
    return try XCTUnwrap(value)
  }

  
  // MARK: - Non-ObjC Swift Support
  
  static var allTests = [
    ( "testBindQuery", testBindQuery ),
    ( "testFailedCommitPreservesTransactionState",
      testFailedCommitPreservesTransactionState ),
    ( "testFailedRollbackReflectsSQLiteTransactionState",
      testFailedRollbackReflectsSQLiteTransactionState ),
    ( "testDeferredForeignKeysAreReappliedToPooledChannel",
      testDeferredForeignKeysAreReappliedToPooledChannel ),
    ( "testSQLLoggingIsDisabledByDefault",
      testSQLLoggingIsDisabledByDefault ),
    ( "testBindValuesAreRedactedFromSQLLoggingByDefault",
      testBindValuesAreRedactedFromSQLLoggingByDefault ),
  ]
}

private final class CapturingLogger: ZeeQLLogger {

  private(set) var messages = [ String ]()

  func primaryLog(_ logLevel: ZeeQLLoggerLogLevel,
                  _ message: () -> String, _ values: [ Any? ])
  {
    let suffix = values.map { String(describing: $0) }.joined(separator: " ")
    messages.append(suffix.isEmpty ? message() : "\(message()) \(suffix)")
  }
}
