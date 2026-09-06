//
//  AdaptorRecordTests.swift
//  ZeeQL
//

import Dispatch
import XCTest
@testable import ZeeQL

class AdaptorRecordTests: XCTestCase {

  func testAttributeSchemaSnapshotsNamesAtInitialization() {
    let attribute = ModelAttribute(name: "id")
    let schema    = AdaptorRecordSchemaWithAttributes([ attribute ])
    attribute.name = "renamed"

    XCTAssertEqual(schema.attributeNames, [ "id" ])
    XCTAssertEqual(schema.count, 1)
    XCTAssertTrue(schema.attributes?.first === attribute)
  }

  func testConcurrentReadsShareAttributeSchema() {
    let attributes = [ ModelAttribute(name: "id"),
                       ModelAttribute(name: "name") ]
    for _ in 0..<10 {
      let schema = AdaptorRecordSchemaWithAttributes(attributes)
      let record = AdaptorRecord(schema: schema, values: [ 42, "Duck" ])

      DispatchQueue.concurrentPerform(iterations: 64) { _ in
        XCTAssertEqual(schema.attributeNames, [ "id", "name" ])
        XCTAssertEqual(schema.count, 2)
        XCTAssertEqual(record["id"] as? Int, 42)
        XCTAssertEqual(record["name"] as? String, "Duck")
      }
    }
  }

  func testEmptyAttributeSchema() {
    let schema = AdaptorRecordSchemaWithAttributes([])

    XCTAssertTrue(schema.attributeNames.isEmpty)
    XCTAssertEqual(schema.count, 0)
  }

  func testAdaptorRowIncludesNullValues() {
    let schema = AdaptorRecordSchemaWithNames([ "id", "nickname" ])
    let record = AdaptorRecord(schema: schema, values: [ 42, nil ])

    let row = record.asAdaptorRow
    XCTAssertEqual(row.count, 2)
    XCTAssertEqual(row["id"] as? Int, 42)
    XCTAssertTrue(row.keys.contains("nickname"))
    guard let nickname = row["nickname"] else {
      return XCTFail("NULL value is missing from the row")
    }
    XCTAssertNil(nickname)
  }

  func testDictionaryExcludesNullValues() {
    let schema = AdaptorRecordSchemaWithNames([ "id", "nickname" ])
    let record = AdaptorRecord(schema: schema, values: [ 42, nil ])

    let dictionary = record.asDictionary
    XCTAssertEqual(dictionary.count, 1)
    XCTAssertEqual(dictionary["id"] as? Int, 42)
    XCTAssertFalse(dictionary.keys.contains("nickname"))
  }

  func testAdaptorRowDynamicEqualityPreservesNullPresence() {
    var lhs: AdaptorRow = [ "id": 42 ]
    lhs.updateValue(nil, forKey: "nickname")
    var rhs = lhs

    XCTAssertTrue(lhs.isEqual(to: rhs))

    rhs.removeValue(forKey: "nickname")
    XCTAssertFalse(lhs.isEqual(to: rhs))

    rhs.updateValue(nil, forKey: "nickname")
    XCTAssertTrue(lhs.isEqual(to: rhs))

    rhs["id"] = 43
    XCTAssertFalse(lhs.isEqual(to: rhs))
  }
}
