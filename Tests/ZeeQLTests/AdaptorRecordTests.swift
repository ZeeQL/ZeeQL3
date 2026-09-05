//
//  AdaptorRecordTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

class AdaptorRecordTests: XCTestCase {

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
