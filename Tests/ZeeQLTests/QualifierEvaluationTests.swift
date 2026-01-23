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
    let qq = qualifierWithFormat( "firstname = 'Donald'")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertTrue(q.evaluate(with: anyDict))
    XCTAssertTrue(q.evaluate(with: anyOptDict))
    XCTAssertTrue(q.evaluate(with: donald))
  }
  func testMatchingKeyComparisonQualifier() {
    let qq = qualifierWithFormat( "firstname = firstname")
    XCTAssert(qq is KeyComparisonQualifier)
    guard let q = qq as? KeyComparisonQualifier else { return }
    
    XCTAssertTrue(q.evaluate(with: anyDict))
    XCTAssertTrue(q.evaluate(with: anyOptDict))
    XCTAssertTrue(q.evaluate(with: donald))
  }

  func testNotMatchingKeyValueQualifier() {
    let qq = qualifierWithFormat( "firstname = 'Mickey'")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertFalse(q.evaluate(with: anyDict))
    XCTAssertFalse(q.evaluate(with: anyOptDict))
    XCTAssertFalse(q.evaluate(with: donald))
  }
  func testNotMatchingKeyComparisonQualifier() {
    let qq = qualifierWithFormat( "firstname != lastName")
    XCTAssert(qq is KeyComparisonQualifier)
    guard let q = qq as? KeyComparisonQualifier else { return }
    
    XCTAssertTrue(q.evaluate(with: anyDict))
    XCTAssertTrue(q.evaluate(with: anyOptDict))
    XCTAssertTrue(q.evaluate(with: donald))
  }

  func testCrossTypeKeyValueQualifier() {
    let qq = qualifierWithFormat( "firstname = 100")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertFalse(q.evaluate(with: anyDict))
    XCTAssertFalse(q.evaluate(with: anyOptDict))
    XCTAssertFalse(q.evaluate(with: donald))
  }

  func testMatchingKeyValueIntQualifier() {
    let qq = qualifierWithFormat( "id = 1000")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertTrue(q.evaluate(with: anyDict))
    XCTAssertTrue(q.evaluate(with: anyOptDict))
    XCTAssertTrue(q.evaluate(with: donald))
  }

  func testMatchingKeyValueNotQualifier() {
    let qq = qualifierWithFormat( "id != 1001")
    XCTAssert(qq is KeyValueQualifier)
    guard let q = qq as? KeyValueQualifier else { return }
    
    XCTAssertTrue(q.evaluate(with: anyDict))
    XCTAssertTrue(q.evaluate(with: anyOptDict))
    XCTAssertTrue(q.evaluate(with: donald))
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
    let qq = qualifierWithFormat( "firstname IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }
    
    XCTAssertTrue(q.evaluate(with: donald))
  }
  func testStringContains() {
    let list = "Donald Duck"
    let qq = qualifierWithFormat( "firstname IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }
    
    XCTAssertTrue(q.evaluate(with: donald))
  }

  func testCollectionNotIn() {
    let list = [ "Mickey", "Goofy" ]
    let qq = qualifierWithFormat( "firstname NOT IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }

    XCTAssertTrue(q.evaluate(with: donald)) // Donald not in list
  }

  func testCollectionNotInFails() {
    let list = [ "Donald", "Mickey" ]
    let qq = qualifierWithFormat( "firstname NOT IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }

    XCTAssertFalse(q.evaluate(with: donald)) // Donald IS in list
  }

  func testEmptyCollectionNotIn() {
    let list = [ String ]()
    let qq = qualifierWithFormat( "firstname NOT IN %@", list)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return }

    XCTAssertTrue(q.evaluate(with: donald)) // not in empty is true
  }

  func testInQualifierNotConvertsToNotIn() {
    let list = [ "Donald", "Mickey" ]
    let q = KeyValueQualifier("firstname", .in, list)
    let notQ = q.not

    XCTAssert(notQ is KeyValueQualifier, "expected KeyValueQualifier")
    guard let kvq = notQ as? KeyValueQualifier else { return }
    XCTAssertEqual(kvq.operation, .notIn)
    XCTAssertEqual(kvq.key, "firstname")

    // Donald is in the list, so NOT IN should be false
    XCTAssertFalse(kvq.evaluate(with: donald))
  }

  func testNotInQualifierNotConvertsToIn() {
    let list = [ "Donald", "Mickey" ]
    let q = KeyValueQualifier("firstname", .notIn, list)
    let notQ = q.not

    XCTAssert(notQ is KeyValueQualifier, "expected KeyValueQualifier")
    guard let kvq = notQ as? KeyValueQualifier else { return }
    XCTAssertEqual(kvq.operation, .in)
    XCTAssertEqual(kvq.key, "firstname")

    // Donald is in the list, so IN should be true
    XCTAssertTrue(kvq.evaluate(with: donald))
  }

  func testDoubleNotInReturnsOriginal() {
    let list = [ "Donald", "Mickey" ]
    let q = KeyValueQualifier("firstname", .in, list)
    let doubleNot = q.not.not

    XCTAssert(doubleNot is KeyValueQualifier, "expected KeyValueQualifier")
    guard let kvq = doubleNot as? KeyValueQualifier else { return }
    XCTAssertEqual(kvq.operation, .in)
  }

  func testNotConvertsComparisonOperations() {
    // equalTo ↔ notEqualTo
    let eq = KeyValueQualifier("id", .equalTo, 10)
    let notEq = eq.not as? KeyValueQualifier
    XCTAssertEqual(notEq?.operation, .notEqualTo)
    XCTAssertEqual((notEq?.not as? KeyValueQualifier)?.operation, .equalTo)

    // lessThan ↔ greaterThanOrEqual
    let lt = KeyValueQualifier("id", .lessThan, 10)
    let notLt = lt.not as? KeyValueQualifier
    XCTAssertEqual(notLt?.operation, .greaterThanOrEqual)
    XCTAssertEqual((notLt?.not as? KeyValueQualifier)?.operation, .lessThan)

    // greaterThan ↔ lessThanOrEqual
    let gt = KeyValueQualifier("id", .greaterThan, 10)
    let notGt = gt.not as? KeyValueQualifier
    XCTAssertEqual(notGt?.operation, .lessThanOrEqual)
    XCTAssertEqual((notGt?.not as? KeyValueQualifier)?.operation, .greaterThan)
  }

  func testNotEvaluatesCorrectly() {
    // NOT (id < 1001) should be id >= 1001, which is false for id=1000
    let lt = KeyValueQualifier("id", .lessThan, 1001)
    XCTAssertTrue(lt.evaluate(with: donald))
    guard let notLt = lt.not as? KeyValueQualifier else { return XCTFail() }
    XCTAssertFalse(notLt.evaluate(with: donald))

    // NOT (id > 999) should be id <= 999, which is false for id=1000
    let gt = KeyValueQualifier("id", .greaterThan, 999)
    XCTAssertTrue(gt.evaluate(with: donald))
    guard let notGt = gt.not as? KeyValueQualifier else { return XCTFail() }
    XCTAssertFalse(notGt.evaluate(with: donald))
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
    let qq = qualifierWithFormat( qualifier)
    XCTAssert(qq is QualifierEvaluation)
    guard let q = qq as? QualifierEvaluation else { return false }
    return q.evaluate(with: object)
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
