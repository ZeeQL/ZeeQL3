//
//  AdaptorOperationTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

final class AdaptorOperationTests: XCTestCase {

  func testEntityNameTakesPriorityOverOperator() {
    var alphaDelete = AdaptorOperation(entity: ModelEntity(name: "Alpha"))
    alphaDelete.adaptorOperator = .delete
    var zuluLock = AdaptorOperation(entity: ModelEntity(name: "Zulu"))
    zuluLock.adaptorOperator = .lock

    XCTAssertTrue(alphaDelete < zuluLock)
    XCTAssertFalse(zuluLock < alphaDelete)
  }

  func testOperatorOrdersOperationsForSameEntity() {
    let entity = ModelEntity(name: "Record")
    var insert = AdaptorOperation(entity: entity)
    insert.adaptorOperator = .insert
    var update = AdaptorOperation(entity: entity)
    update.adaptorOperator = .update

    XCTAssertTrue(insert < update)
    XCTAssertFalse(update < insert)
    XCTAssertFalse(insert < insert)
  }

  func testEqualityRequiresSameEntityIdentity() {
    var first = AdaptorOperation(entity: ModelEntity(name: "Record"))
    first.adaptorOperator = .insert
    var second = AdaptorOperation(entity: ModelEntity(name: "Record"))
    second.adaptorOperator = .insert

    XCTAssertNotEqual(first, second)
  }

  func testEqualityIncludesAttributesQualifierAndRows() {
    let entity = ModelEntity(name: "Record")
    var values: AdaptorRow = [ "id": 1 ]
    values.updateValue(nil, forKey: "name")

    var lhs = AdaptorOperation(entity: entity)
    lhs.adaptorOperator = .update
    lhs.attributes = [ ModelAttribute(name: "name") ]
    lhs.qualifier = KeyValueQualifier("id", .equalTo, 1)
    lhs.changedValues = values
    lhs.resultRow = [ "id": 1 ]

    var rhs = AdaptorOperation(lhs)
    XCTAssertEqual(lhs, rhs)

    rhs.attributes = [ ModelAttribute(name: "other") ]
    XCTAssertNotEqual(lhs, rhs)
    rhs.attributes = lhs.attributes
    XCTAssertEqual(lhs, rhs)

    rhs.qualifier = KeyValueQualifier("id", .equalTo, 2)
    XCTAssertNotEqual(lhs, rhs)
    rhs.qualifier = lhs.qualifier

    rhs.changedValues?.removeValue(forKey: "name")
    XCTAssertNotEqual(lhs, rhs)
    rhs.changedValues = lhs.changedValues

    rhs.resultRow = [ "id": 2 ]
    XCTAssertNotEqual(lhs, rhs)
  }

  func testEqualityIsReflexiveWithCompletionBlock() {
    var operation = AdaptorOperation(entity: ModelEntity(name: "Record"))
    operation.completionBlock = {}

    XCTAssertEqual(operation, operation)
  }
}
