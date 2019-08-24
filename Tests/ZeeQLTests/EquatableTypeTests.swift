//
//  EquatableTests.swift
//  ZeeQLTests
//
//  Created by Helge Heß on 24.08.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class EquatableTypeTests: XCTestCase {

  public func testInts() {
    XCTAssertFalse(Int.max.isEqual(to: 8 as Int8))
    XCTAssertTrue ((8 as Int).isEqual(to: 8 as Int8))
    XCTAssertTrue ((8 as Int8).isEqual(to: 8 as Int))
    XCTAssertFalse((8 as Int8).isEqual(to: Int.max))
    XCTAssertTrue (Int.max.isEqual(to: Int64.max))
    XCTAssertTrue (Int.max.isEqual(to: UInt64(Int.max)))
  }

  public func testStrings() {
    let a  : String  = "Hello"
    let oa : String? = "Hello"
    let ow : String? = "World"
    XCTAssertTrue(a .isEqual(to: "Hello"))
    XCTAssertTrue(oa.isEqual(to: "Hello"))
    XCTAssertTrue(a .isEqual(to: oa))
    XCTAssertTrue(oa.isEqual(to: a))
    XCTAssertFalse(a .isEqual(to: "World"))
    XCTAssertFalse(oa.isEqual(to: "World"))
    XCTAssertFalse(a .isEqual(to: ow))
    XCTAssertFalse(ow.isEqual(to: a))
  }
  
  public func testMixBoolTypes() {
    XCTAssertFalse("0".isEqual(to: false))
    XCTAssertFalse("1".isEqual(to: true))
    XCTAssertFalse(0  .isEqual(to: false))
    XCTAssertFalse(1  .isEqual(to: true))
  }
  
  public func testMixTypes() {
    XCTAssertFalse(48.isEqual(to: "48"))
    XCTAssertFalse("48".isEqual(to: 48))
    XCTAssertFalse("48".isEqual(to: 48 as Double))
    XCTAssertFalse((48 as Double).isEqual(to: 48 as Float))
    XCTAssertFalse((48 as Float) .isEqual(to: 48 as Double))
    XCTAssertFalse((48 as Double).isEqual(to: "48"))
  }

}
