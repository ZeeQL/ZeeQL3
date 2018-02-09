//
//  FormatterTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class FormatterTests: XCTestCase {
  
  let person = [ "firstname": "Donald", "lastname": "Duck" ]
  
  func testKeyValueStringFormatter1() {
    let s = KeyValueStringFormatter.format("%(firstname)s %(lastname)s",
                                           object: person)
    XCTAssertEqual(s, "Donald Duck")
  }
  
  func testKeyValueStringFormatterPosArg() {
    let s = KeyValueStringFormatter.format("%s %i", "Hello", 42)
    XCTAssertEqual(s, "Hello 42")
  }
  
  func testKeyValueStringFormatterInvalidPercent() {
    let s = KeyValueStringFormatter.format("%(murkel %i", "Hello", 42)
    XCTAssertEqual(s, "%(murkel %i")
  }
  
  func testKeyValueStringFormatterEndInPercent() {
    let s = KeyValueStringFormatter.format("%(firstname)s %", object: person)
    XCTAssertEqual(s, "Donald %")
  }
  
  static var allTests = [
    ( "testKeyValueStringFormatter1", testKeyValueStringFormatter1 ),
    ( "testKeyValueStringFormatterPosArg", testKeyValueStringFormatterPosArg ),
    ( "testKeyValueStringFormatterInvalidPercent",
       testKeyValueStringFormatterInvalidPercent ),
    ( "testKeyValueStringFormatterEndInPercent",
       testKeyValueStringFormatterEndInPercent ),
  ]
}
