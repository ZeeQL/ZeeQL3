//
//  QualifierParserTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class QualifierParserTests: XCTestCase {
  
  func testSimpleKeyValueQualifierInt() {
    _testKeyValueQualifier("amount = 10000", "amount", 10000)
  }
  
  func testSimpleKeyValueQualifierString() {
    _testKeyValueQualifier("name = 'Duck'",     "name", "Duck")
    _testKeyValueQualifier("name like 'Duck*'", "name", "Duck*")
    _testKeyValueQualifier("name < 'Duck'",     "name", "Duck")
    _testKeyValueQualifier("name = null",       "name", nil)
  }
  
  func testComplexCompoundQualifier() {
    // should be: ((a = 1 AND b = 2) OR c = 3) AND f = 4
    let q = parse("a = 1 AND b = 2 OR c = 3 AND f = 4") // TODO: FAILS
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is CompoundQualifier, "did not parse an AND qualifier")
    let aq = q! as! CompoundQualifier
    XCTAssert(aq.op == .And, "did not parse an AND qualifier")
    
    XCTAssertEqual(aq.qualifiers.count, 2, "length of top-level does not match")
  }
  
  func testComplexArgumentParsing() {
    let q = qualifierWith(format:
              "name = %K AND salary > %d AND startDate %@ endDate",
              "firstname", "5000", "<=")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    XCTAssert(q! is CompoundQualifier, "did not parse an AND qualifier")
    let aq = q! as! CompoundQualifier
    XCTAssert(aq.op == .And, "did not parse an AND qualifier")
    
    XCTAssert(aq.qualifiers[0] is KeyComparisonQualifier,
              "first qualifier is not a key comparison")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[2] is KeyComparisonQualifier,
              "third qualifier is not a key comparison")
  }
  
  func testQualifierWithOneVariables() {
    let q = qualifierWith(format: "lastname = $lastname")
    XCTAssertNotNil(q, "could not parse qualifier")
    let keys = q!.bindingKeys
    XCTAssertEqual(keys.count, 1, "Expected one binding")
    XCTAssert(keys.contains("lastname"), "missing 'lastname' binding")
  }

  func testQualifierWithSomeVariables() {
    let q = qualifierWith(format:
      "lastname = $lastname AND firstname = $firstname OR salary > $salary")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let keys = q!.bindingKeys
    XCTAssertEqual(keys.count, 3, "Expected three bindings")
    XCTAssert(keys.contains("lastname"),  "missing 'lastname' binding")
    XCTAssert(keys.contains("firstname"), "missing 'firstname' binding")
    XCTAssert(keys.contains("salary"),    "missing 'salary' binding")
  }
  
  func testQualifierWithParenthesis() {
    let q = qualifierWith(format:
      "name = 'Duck' AND (balance = 1 OR balance = 2\n OR balance = 3)")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is CompoundQualifier, "did not parse an AND qualifier")
    let aq = q! as! CompoundQualifier
    XCTAssert(aq.op == .And, "did not parse an AND qualifier")
    
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    
    XCTAssert(aq.qualifiers[1] is CompoundQualifier,
              "second qualifier is not an OR qualifier")
    let aq2 = aq.qualifiers[1] as! CompoundQualifier
    XCTAssert(aq2.op == .Or, "second qualifier is not an OR qualifier")
  }
  
  func XtestArrayINQualifier() { // plist array values after IN unsupported
    let q = qualifierWith(format:
                        "person.aksa_status IN ('301','302','303')")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is KeyValueQualifier, "did not parse a key/value qualifier")
    let aq = q! as! KeyValueQualifier
    
    XCTAssertEqual(aq.key, "person.aksa_status", "parsed key is incorrect")
  }

  func testSimpleBoolKeyValueQualifier() {
    let q = qualifierWith(format: "isArchived")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is KeyValueQualifier, "did not parse a key/value qualifier")
    guard let kvq = q as? KeyValueQualifier else { return }
    
    XCTAssertEqual(kvq.operation, .EqualTo)
    XCTAssert(kvq.value is Bool)
    guard let bv = kvq.value as? Bool else { return }
    XCTAssertEqual(bv, true)
  }
  
  func testBoolKeyValueAndFrontQualifier() {
    let q = qualifierWith(format: "isArchived AND code > 3")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is CompoundQualifier, "did not parse an AND qualifier")
    let aq = q! as! CompoundQualifier
    XCTAssert(aq.op == .And, "did not parse an AND qualifier")
   
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
  }
  
  func testBoolKeyValueAndBackQualifier() {
    let q = qualifierWith(format: "code > 3 AND isArchived")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    XCTAssert(q! is CompoundQualifier, "did not parse an AND qualifier")
    let aq = q! as! CompoundQualifier
    XCTAssert(aq.op == .And, "did not parse an AND qualifier")
   
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
  }
  
  func testBoolKeyValueAndParenQualifier() {
    let q = qualifierWith(format:
                       "(isArchived) AND code > 3 AND (isUsed)")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is CompoundQualifier, "did not parse an AND qualifier")
    let aq = q! as! CompoundQualifier
    XCTAssert(aq.op == .And, "did not parse an AND qualifier")
   
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[2] is KeyValueQualifier,
              "third qualifier is not a key/value qualifier")
  }
  
  func testSQLQualifier() {
    let q = qualifierWith(format:
                         "SQL[lastname = $lastname AND balance = $balance]")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is SQLQualifier, "did not parse a SQL qualifier")
    
    let parts = (q as! SQLQualifier).parts
    XCTAssertEqual(parts.count, 4, "number of parts does not match")
    
    if case .rawValue(let v) = parts[0] {
      XCTAssertEqual(v, "lastname = ", "1st raw value doesn't match")
    }
    else {
      XCTFail("first part is not a SQL value: \(parts[0])")
    }
    
    if case .variable(let id) = parts[1] {
      XCTAssertEqual(id, "lastname", "2nd part qvar doesn't match")
    }
    else {
      XCTFail("2nd part is not a QualifierVariable: \(parts[1])")
    }
    
    if case .rawValue(let v) = parts[2] {
      XCTAssertEqual(v, " AND balance = ", "3rd raw value doesn't match")
    }
    else {
      XCTFail("3rd part is not a SQL value: \(parts[2])")
    }

    if case .variable(let id) = parts[3] {
      XCTAssertEqual(id, "balance", "4th part qvar doesn't match")
    }
    else {
      XCTFail("4th part is not a QualifierVariable: \(parts[3])")
    }
  }

  func testPlainString() {
    // Actually the same like testSimpleBoolKeyValueQualifier, but for
    // clarity :-)
    let q = qualifierWith(format: "hello")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    // Not sure whether this is actually intended :-) It makes sense for this:
    //   "lastname = 'abc' AND isLoggedIn" etc.
    XCTAssert(q! is KeyValueQualifier, "did not parse a key/value qualifier")
    guard let kvq = q as? KeyValueQualifier else { return }
    
    XCTAssertEqual(kvq.operation, .EqualTo)
    XCTAssert(kvq.value is Bool)
    guard let bv = kvq.value as? Bool else { return }
    XCTAssertEqual(bv, true)
  }

  
  // MARK: - Support
  
  func _testKeyValueQualifier(_ _qs: String, _ _k: String, _ _v: Any?) {
    let q = parse(_qs)
    XCTAssertNotNil(q, "could not parse qualifier")
    
    XCTAssert(q! is KeyValueQualifier,
              "did not parse a key/value qualifier \(q!.self)")
    
    let kvq = q! as! KeyValueQualifier
    XCTAssertEqual(_k, kvq.key,  "key of qualifier does not match")
    XCTAssert(eq(_v, kvq.value), "value of qualifier does not match")
  }
  
  func parse(_ fmt: String) -> Qualifier? {
    let parser = QualifierParser(string: fmt)
    let q = parser.parseQualifier()
    // TODO: check for errors
    return q
  }

  static var allTests = [
    ( "testSimpleKeyValueQualifierInt",    testSimpleKeyValueQualifierInt ),
    ( "testSimpleKeyValueQualifierString", testSimpleKeyValueQualifierString ),
    ( "testComplexCompoundQualifier",      testComplexCompoundQualifier ),
    ( "testComplexArgumentParsing",        testComplexArgumentParsing ),
    ( "testQualifierWithOneVariables",     testQualifierWithOneVariables ),
    ( "testQualifierWithSomeVariables",    testQualifierWithSomeVariables ),
    ( "testQualifierWithParenthesis",      testQualifierWithParenthesis ),
    ( "testSimpleBoolKeyValueQualifier",   testSimpleBoolKeyValueQualifier ),
    ( "testBoolKeyValueAndFrontQualifier", testBoolKeyValueAndFrontQualifier ),
    ( "testBoolKeyValueAndBackQualifier",  testBoolKeyValueAndBackQualifier ),
    ( "testBoolKeyValueAndParenQualifier", testBoolKeyValueAndParenQualifier ),
    ( "testSQLQualifier",                  testSQLQualifier ),
    ( "testPlainString",                   testPlainString ),
  ]
}
