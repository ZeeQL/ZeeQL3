//
//  QualifierEvaluationTests.swift
//  ZeeQLTests
//
//  Created by Helge Heß on 24.08.19.
//  Copyright © 2019-2025 ZeeZide GmbH. All rights reserved.
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
  func testMatchingKeyComparisonQualifier() {
    let qq = qualifierWith(format: "firstname = firstname")
    XCTAssert(qq is KeyComparisonQualifier)
    guard let q = qq as? KeyComparisonQualifier else { return }
    
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
  func testNotMatchingKeyComparisonQualifier() {
    let qq = qualifierWith(format: "firstname != lastName")
    XCTAssert(qq is KeyComparisonQualifier)
    guard let q = qq as? KeyComparisonQualifier else { return }
    
    XCTAssertTrue(q.evaluateWith(object: anyDict))
    XCTAssertTrue(q.evaluateWith(object: anyOptDict))
    XCTAssertTrue(q.evaluateWith(object: donald))
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
  
  func testOpKeyValueQualifier() {
    XCTAssertTrue (evaluate("id < 1001", anyDict))
    XCTAssertFalse(evaluate("id > 1000", anyDict))
    XCTAssertTrue (evaluate("id > 0",    anyDict))
    XCTAssertTrue (evaluate("id < 1001", donald))
    XCTAssertTrue (evaluate("id <= 1001", anyDict))
    XCTAssertTrue (evaluate("id <= 1000", anyDict))
  }
  
  func testCollectionContains() {
    let list = [ "Donald", "Mickey" ]
    let qq = qualifierWith(format: "firstname IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }
    
    XCTAssertTrue(q.evaluateWith(object: donald))
  }
  func testStringContains() {
    let list = "Donald Duck"
    let qq = qualifierWith(format: "firstname IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }
    
    XCTAssertTrue(q.evaluateWith(object: donald))
  }

  func testCollectionNotIn() {
    let list = [ "Mickey", "Goofy" ]
    let qq = qualifierWith(format: "firstname NOT IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }

    XCTAssertTrue(q.evaluateWith(object: donald)) // Donald not in list
  }

  func testCollectionNotInFails() {
    let list = [ "Donald", "Mickey" ]
    let qq = qualifierWith(format: "firstname NOT IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }

    XCTAssertFalse(q.evaluateWith(object: donald)) // Donald IS in list
  }

  func testEmptyCollectionNotIn() {
    let list = [ String ]()
    let qq = qualifierWith(format: "firstname NOT IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }

    XCTAssertTrue(q.evaluateWith(object: donald)) // not in empty is true
  }
  func testLikeOp() {
    XCTAssertTrue (evaluate("firstname LIKE 'Don*'", anyDict))
    XCTAssertFalse(evaluate("firstname LIKE 'don*'", anyDict))
    XCTAssertTrue (evaluate("firstname LIKE 'Don*'", donald))

    XCTAssertTrue (evaluate("firstname ILIKE 'don*'", donald))

    XCTAssertTrue (evaluate("firstname LIKE 'Donald'",  donald))
    XCTAssertTrue (evaluate("firstname ILIKE 'Donald'", donald))
  }

  func testContainsOp() {
    // Case-sensitive CONTAINS
    XCTAssertTrue (evaluate("firstname CONTAINS 'onal'", donald))
    XCTAssertTrue (evaluate("firstname CONTAINS 'Don'",  donald))
    XCTAssertTrue (evaluate("firstname CONTAINS 'ald'",  donald))
    XCTAssertFalse(evaluate("firstname CONTAINS 'onal'", anyDict) == false
                   || evaluate("firstname CONTAINS 'ONAL'", donald))
    XCTAssertFalse(evaluate("firstname CONTAINS 'Mickey'", donald))

    // Case-insensitive CONTAINS
    XCTAssertTrue (evaluate("firstname CONTAINS[c] 'ONAL'", donald))
    XCTAssertTrue (evaluate("firstname CONTAINS[c] 'don'",  donald))
    XCTAssertFalse(evaluate("firstname CONTAINS[c] 'mickey'", donald))
  }

  func testBeginsWithOp() {
    // Case-sensitive BEGINSWITH
    XCTAssertTrue (evaluate("firstname BEGINSWITH 'Don'", donald))
    XCTAssertTrue (evaluate("firstname BEGINSWITH 'Donald'", donald))
    XCTAssertFalse(evaluate("firstname BEGINSWITH 'don'", donald))
    XCTAssertFalse(evaluate("firstname BEGINSWITH 'onald'", donald))

    // Case-insensitive BEGINSWITH
    XCTAssertTrue (evaluate("firstname BEGINSWITH[c] 'don'", donald))
    XCTAssertTrue (evaluate("firstname BEGINSWITH[c] 'DON'", donald))
    XCTAssertFalse(evaluate("firstname BEGINSWITH[c] 'onald'", donald))
  }

  func testEndsWithOp() {
    // Case-sensitive ENDSWITH
    XCTAssertTrue (evaluate("firstname ENDSWITH 'ald'", donald))
    XCTAssertTrue (evaluate("firstname ENDSWITH 'Donald'", donald))
    XCTAssertFalse(evaluate("firstname ENDSWITH 'ALD'", donald))
    XCTAssertFalse(evaluate("firstname ENDSWITH 'Don'", donald))

    // Case-insensitive ENDSWITH
    XCTAssertTrue (evaluate("firstname ENDSWITH[c] 'ALD'", donald))
    XCTAssertTrue (evaluate("firstname ENDSWITH[c] 'donald'", donald))
    XCTAssertFalse(evaluate("firstname ENDSWITH[c] 'don'", donald))
  }

  func evaluate<T>(_ qualifier: String, _ object: T) -> Bool {
    let qq = qualifierWith(format: qualifier)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return false }
    return q.evaluateWith(object: object)
  }
  
  
  func testCombiningOr() {
    let qualifiers = [
      KeyValueQualifier("a", .equalTo, 10),
      KeyValueQualifier("a", .equalTo, 10),
      KeyValueQualifier("a", .equalTo, 11),
      KeyValueQualifier("b", .equalTo, "hello")
    ]
    let q = qualifiers.compactingOr()
    XCTAssert(q is CompoundQualifier)
    guard let tl = q as? CompoundQualifier else { return }
    XCTAssert(tl.op == .or)
    XCTAssert(tl.qualifiers.count == 2)
    guard tl.qualifiers.count >= 2 else { return }
    
    let first  = tl.qualifiers[0]
    let second = tl.qualifiers[1]
    XCTAssert(first is KeyValueQualifier && second is KeyValueQualifier)
    guard let fk = first  as? KeyValueQualifier,
          let sk = second as? KeyValueQualifier else { return }
    
    assert(fk.operation == .in || sk.operation == .in)
    assert(fk.operation == .equalTo  || sk.operation == .equalTo)
    let aQual = fk.operation == .in      ? fk : sk
    let bQual = fk.operation == .equalTo ? fk : sk

    XCTAssertEqual(bQual.key, "b")
    XCTAssertEqual(bQual.operation, .equalTo)
    XCTAssertEqual(bQual.value as? String, "hello")
    
    XCTAssertEqual(aQual.key, "a")
    XCTAssertEqual(aQual.operation, .in)
    XCTAssertEqual(aQual.value as? [ Int ], [ 10, 10, 11 ])
  }
}
