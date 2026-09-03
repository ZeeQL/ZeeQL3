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
}
