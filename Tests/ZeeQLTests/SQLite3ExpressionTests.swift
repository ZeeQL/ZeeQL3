//
//  SQLite3AdaptorTests.swift
//  SQLite3AdaptorTests
//
//  Created by Helge Hess on 03/03/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import ZeeQL

class SQLite3ExpressionTests: XCTestCase {

  let factory = SQLite3ExpressionFactory()

  let entity  : Entity = {
    let e = ModelEntity(name: "company")
    e.attributes = [
      ModelAttribute(name: "id",   externalType: "INTEGER"),
      ModelAttribute(name: "age",  externalType: "INTEGER"),
      ModelAttribute(name: "name", externalType: "VARCHAR(255)")
    ]
    return e
  }()
  
  func testRawDeleteSQLExpr() {
    let q = qualifierWith(format: "id = 5")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let expr = factory.deleteStatementWithQualifier(q!, entity)
    XCTAssertEqual(expr.statement,
                   "DELETE FROM \"company\" WHERE \"id\" = 5",
                   "unexpected SQL result")
  }
  
  func testUpdateSQLExpr() {
    let q = qualifierWith(format: "id = 5")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let row : [ String : Any? ] = [ "age": 42, "name": "Zealandia" ]
    
    let expr = factory.updateStatementForRow(row, q!, entity)
    
    XCTAssertEqual(expr.statement,
      "UPDATE \"company\" SET \"age\" = 42, \"name\" = ? WHERE \"id\" = 5",
      "unexpected SQL result")
    
    let bindings = expr.bindVariables
    XCTAssertEqual(bindings.count, 1, "unexpected binding count")
    XCTAssertEqual(bindings[0].value as? String, "Zealandia")
  }

  func testInsertSQLExpr() {
    let row : [ String : Any? ] = [ "id": 5, "age": 42, "name": "Zealandia" ]
    
    let expr = factory.insertStatementForRow(row, entity)
    // can be reordered, hashtable has no ordering!
    XCTAssert((
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"id\", \"age\", \"name\" ) " +
         "VALUES ( 5, 42, ? )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"name\", \"id\", \"age\" ) " +
          "VALUES ( ?, 5, 42 )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"age\", \"name\", \"id\" ) " +
          "VALUES ( 42, ?, 5 )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"age\", \"id\", \"name\" ) " +
          "VALUES ( 42, 5, ? )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"id\", \"name\", \"age\" ) " +
          "VALUES ( 5, ?, 42 )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"name\", \"age\", \"id\" ) " +
          "VALUES ( ?, 42, 5 )" ) )
      ), "unexpected SQL result `\(expr.statement)`")
    
    let bindings = expr.bindVariables
    XCTAssertEqual(bindings.count, 1, "unexpected binding count")
    XCTAssertEqual(bindings[0].value as? String, "Zealandia")
  }

  func testSimpleSelectExpr() {
    let q = qualifierWith(format: "age > 13")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let fs = ModelFetchSpecification(entity: entity, qualifier: q)
    let expr = factory.selectExpressionForAttributes(
      entity.attributes, lock: true, fs, entity
    )
    XCTAssertEqual(expr.statement,
      "SELECT BASE.\"id\", BASE.\"age\", BASE.\"name\" " +
        "FROM \"company\" AS BASE " +
       "WHERE BASE.\"age\" > 13", // no FOR UPDATE for locking in SQLite
      "unexpected SQL result")
  }
  
  func testSimpleSelectExprWithArgument() {
    let q = qualifierWith(format: "name = %@", "Donald")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let fs = ModelFetchSpecification(entity: entity, qualifier: q)
    let expr = factory.selectExpressionForAttributes(
      entity.attributes, lock: true, fs, entity
    )
    XCTAssertEqual(expr.statement,
                   "SELECT BASE.\"id\", BASE.\"age\", BASE.\"name\" " +
                     "FROM \"company\" AS BASE " +
                    "WHERE BASE.\"name\" = ?",
                   "unexpected SQL result")
    let bindings = expr.bindVariables
    XCTAssertEqual(bindings.count, 1, "unexpected binding count")
    XCTAssertEqual(bindings[0].value as? String, "Donald")
  }
}
