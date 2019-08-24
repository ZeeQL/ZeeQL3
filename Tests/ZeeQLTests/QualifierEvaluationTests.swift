//
//  QualifierEvaluationTests.swift
//  ZeeQLTests
//
//  Created by Helge Heß on 24.08.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class QualifierEvaluationTests: XCTestCase {
  
  typealias Person = ModelTests.Person
  
  let donald : Person = {
    let person = Person()
    person["id"]        = 1000
    person["firstname"] = "Donald"
    person["lastname"]  = "Duck"
    return person
  }()
  let anyDict : [ String : Any ] = [
    "id"        : 1000,
    "firstname" : "Donald",
    "lastname"  : "Duck"
  ]
  let anyOptDict : [ String : Any? ] = [
    "id"        : 1000,
    "firstname" : "Donald",
    "lastname"  : "Duck"
  ]

  func testMatchingKeyValueQualifier() {
    let qq = qualifierWith(format: "firstname = 'Donald'")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertTrue(q.evaluateWith(object: anyDict))
    XCTAssertTrue(q.evaluateWith(object: anyOptDict))
    XCTAssertTrue(q.evaluateWith(object: donald))
  }
  
  func testNotMatchingKeyValueQualifier() {
    let qq = qualifierWith(format: "firstname = 'Mickey'")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertFalse(q.evaluateWith(object: anyDict))
    XCTAssertFalse(q.evaluateWith(object: anyOptDict))
    XCTAssertFalse(q.evaluateWith(object: donald))
  }
  
  func testCrossTypeKeyValueQualifier() {
    let qq = qualifierWith(format: "firstname = 100")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertFalse(q.evaluateWith(object: anyDict))
    XCTAssertFalse(q.evaluateWith(object: anyOptDict))
    XCTAssertFalse(q.evaluateWith(object: donald))
  }

  func testMatchingKeyValueIntQualifier() {
    let qq = qualifierWith(format: "id = 1000")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertTrue(q.evaluateWith(object: anyDict))
    XCTAssertTrue(q.evaluateWith(object: anyOptDict))
    XCTAssertTrue(q.evaluateWith(object: donald))
  }

  func testMatchingKeyValueNotQualifier() {
    let qq = qualifierWith(format: "id != 1001")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertTrue(q.evaluateWith(object: anyDict))
    XCTAssertTrue(q.evaluateWith(object: anyOptDict))
    XCTAssertTrue(q.evaluateWith(object: donald))
  }
}
