//
//  GlobalIDTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

class GlobalIDTests: XCTestCase {

  func testCompositeKeyPreservesNullPosition() throws {
    let globalID = try XCTUnwrap(KeyGlobalID.make(
      entityName: "Membership", values: [ 7, nil, "owner" ]))

    XCTAssertEqual(globalID.keyCount, 3)
    XCTAssertEqual(globalID[0] as? Int, 7)
    XCTAssertNil(globalID[1])
    XCTAssertEqual(globalID[2] as? String, "owner")
  }

  func testNullPositionAffectsCompositeIdentity() throws {
    let withNull = try XCTUnwrap(KeyGlobalID.make(
      entityName: "Membership", values: [ 7, nil, "owner" ]))
    let withoutNull = try XCTUnwrap(KeyGlobalID.make(
      entityName: "Membership", values: [ 7, "owner" ]))

    XCTAssertNotEqual(withNull, withoutNull)
  }

  #if !DEBUG
  func testNonHashableKeyReturnsNil() {
    let value = NonHashableValue()
    XCTAssertNil(KeyGlobalID.make(entityName: "Invalid", values: [ value ]))
  }
  #endif
}

private final class NonHashableValue {}
