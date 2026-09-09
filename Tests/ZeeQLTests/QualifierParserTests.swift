//
//  QualifierParserTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
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

  func testUnterminatedQuotedStringsReturnNil() {
    XCTAssertNil(qualifierWithFormat("name = '"))
    XCTAssertNil(qualifierWithFormat("name = 'unterminated"))
    XCTAssertNil(qualifierWithFormat("name = \"unterminated"))
    XCTAssertNil(qualifierWithFormat("name = 'escape\\"))
  }

  func testTrailingFormatMarkerReturnsNil() {
    XCTAssertNil(qualifierWithFormat("name = %"))
  }

  func testThrowingParser() throws {
    let qualifier = try QualifierParser.parse("name = 'Duck'")
    let keyValue = try XCTUnwrap(qualifier as? KeyValueQualifier)

    XCTAssertEqual(keyValue.key, "name")
    XCTAssertEqual(keyValue.value as? String, "Duck")
  }

  func testThrowingParserReportsOriginalString() {
    let input = "name = 'unterminated"

    XCTAssertThrowsError(try QualifierParser.parse(input)) { thrown in
      guard let error = thrown as? QualifierParser.ParserError else {
        return XCTFail("unexpected error: \(thrown)")
      }
      XCTAssertEqual(error.string, input)
      guard case .invalidSyntax(let reason, _, _) = error else {
        return XCTFail("unexpected parser error: \(error)")
      }
      XCTAssertTrue(reason.contains("not closed"))
    }
  }

  func testThrowingParserReportsEmptyInput() {
    let input = " "

    XCTAssertThrowsError(try QualifierParser.parse(input)) { thrown in
      XCTAssertEqual(
        thrown as? QualifierParser.ParserError,
        .emptyInput(string: input))
    }
  }

  func testMalformedTokenBoundariesDoNotTrap() {
    let inputs = [
      "", " ", "%", "'", "\"", "name ", "name =", "name = ",
      "name = %", "name = '", "name = \\", "name = $", "(", "SQL[",
      "SQL[$", "name = ()", "name = (Date", "name = (Date)",
      "name = (Date) "
    ]
    for input in inputs { _ = qualifierWithFormat(input) }
  }

  func testUnsupportedFormatSpecifiersReportErrors() {
    let inputs = [
      "%z = 1", "name %z 1", "name = %z", "name = 1 %z other = 2"
    ]
    for input in inputs {
      XCTAssertThrowsError(try QualifierParser.parse(input, "name")) { thrown in
        guard let error = thrown as? QualifierParser.ParserError else {
          return XCTFail("unexpected error for \(input): \(thrown)")
        }
        XCTAssertEqual(error.string, input)
        guard case .invalidSyntax(let reason, _, _) = error else {
          return XCTFail("unexpected parser error: \(error)")
        }
        XCTAssertTrue(reason.contains("unknown"))
        XCTAssertTrue(reason.contains("%z"))
      }
      XCTAssertNil(qualifierWithFormat(input, "name"), input)
    }
  }

  func testMalformedTokenBoundaryCorpusDoesNotTrap() {
    let seeds = [
      "name = 'unterminated\\", "name = \"unterminated",
      "name = %", "name = %z", "%z = 1", "name = $",
      "(name = 1 AND value = 2", "NOT (name = 1 OR)",
      "SQL[$variable", "SQL[unterminated", "emoji😀 = 'value'",
      "naïve = 'café'", "amount = -", "amount = -.",
      "a = 1 AND b = 2 OR c = 3"
    ]
    let fragments = [
      "", " ", "(", ")", "'", "\"", "%", "%z", "$", "SQL[",
      "NOT ", "name", " = ", " AND ", " OR ", "-", "1", "\\"
    ]

    for seed in seeds {
      for boundary in seed.indices {
        checkTokenBoundary(String(seed[..<boundary]))
      }
      checkTokenBoundary(seed)
    }
    for lhs in fragments {
      for rhs in fragments { checkTokenBoundary(lhs + rhs) }
    }
  }
  
  func testComplexCompoundQualifier() throws {
    let parsed = try XCTUnwrap(
      parse("a = 1 AND b = 2 OR c = 3 AND f = 4"))
    let disjunction = try XCTUnwrap(parsed as? CompoundQualifier)
    XCTAssertEqual(disjunction.op, .or)
    XCTAssertEqual(disjunction.qualifiers.count, 2)

    let left = try XCTUnwrap(
      disjunction.qualifiers[0] as? CompoundQualifier)
    XCTAssertEqual(left.op, .and)
    XCTAssertEqual(left.qualifiers.count, 2)
    XCTAssertEqual((left.qualifiers[0] as? KeyValueQualifier)?.key, "a")
    XCTAssertEqual((left.qualifiers[1] as? KeyValueQualifier)?.key, "b")

    let right = try XCTUnwrap(
      disjunction.qualifiers[1] as? CompoundQualifier)
    XCTAssertEqual(right.op, .and)
    XCTAssertEqual(right.qualifiers.count, 2)
    XCTAssertEqual((right.qualifiers[0] as? KeyValueQualifier)?.key, "c")
    XCTAssertEqual((right.qualifiers[1] as? KeyValueQualifier)?.key, "f")
  }

  func testAndBindsMoreTightlyThanOr() throws {
    let parsed = try XCTUnwrap(parse("a = 1 OR b = 2 AND c = 3"))
    let disjunction = try XCTUnwrap(parsed as? CompoundQualifier)
    XCTAssertEqual(disjunction.op, .or)
    XCTAssertEqual(disjunction.qualifiers.count, 2)
    XCTAssertEqual(
      (disjunction.qualifiers[0] as? KeyValueQualifier)?.key, "a")

    let conjunction = try XCTUnwrap(
      disjunction.qualifiers[1] as? CompoundQualifier)
    XCTAssertEqual(conjunction.op, .and)
    XCTAssertEqual(conjunction.qualifiers.count, 2)
    XCTAssertEqual(
      (conjunction.qualifiers[0] as? KeyValueQualifier)?.key, "b")
    XCTAssertEqual(
      (conjunction.qualifiers[1] as? KeyValueQualifier)?.key, "c")
  }
  
  func testComplexArgumentParsing() {
    let q = qualifierWithFormat(
              "name = %K AND salary > %d AND startDate %@ endDate",
              "firstname", "5000", "<=")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    XCTAssert(q! is CompoundQualifier, "did not parse an AND qualifier")
    let aq = q! as! CompoundQualifier
    XCTAssert(aq.op == .and, "did not parse an AND qualifier")
    
    XCTAssert(aq.qualifiers[0] is KeyComparisonQualifier,
              "first qualifier is not a key comparison")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[2] is KeyComparisonQualifier,
              "third qualifier is not a key comparison")
  }
  
  func testQualifierWithOneVariables() {
    let q = qualifierWithFormat( "lastname = $lastname")
    XCTAssertNotNil(q, "could not parse qualifier")
    let keys = q!.bindingKeys
    XCTAssertEqual(keys.count, 1, "Expected one binding")
    XCTAssert(keys.contains("lastname"), "missing 'lastname' binding")
  }

  func testQualifierWithSomeVariables() {
    let q = qualifierWithFormat(
      "lastname = $lastname AND firstname = $firstname OR salary > $salary")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let keys = q!.bindingKeys
    XCTAssertEqual(keys.count, 3, "Expected three bindings")
    XCTAssert(keys.contains("lastname"),  "missing 'lastname' binding")
    XCTAssert(keys.contains("firstname"), "missing 'firstname' binding")
    XCTAssert(keys.contains("salary"),    "missing 'salary' binding")
  }
  
  func testQualifierWithParenthesis() throws {
    let qb = qualifierWithFormat(
      "name = 'Duck' AND (balance = 1 OR balance = 2\n OR balance = 3)")
    XCTAssertNotNil(qb, "could not parse qualifier")
    let q = try XCTUnwrap(qb)

    XCTAssert(q is CompoundQualifier, "did not parse an AND qualifier")
    let aq = try XCTUnwrap(q as? CompoundQualifier)
    XCTAssert(aq.op == .and, "did not parse an AND qualifier")
    
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    
    XCTAssert(aq.qualifiers[1] is CompoundQualifier,
              "second qualifier is not an OR qualifier")
    let aq2 = try XCTUnwrap(aq.qualifiers[1] as? CompoundQualifier)
    XCTAssert(aq2.op == .or, "second qualifier is not an OR qualifier")
  }
  
  func XtestArrayINQualifier() { // plist array values after IN unsupported
    let q = qualifierWithFormat(
                        "person.aksa_status IN ('301','302','303')")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is KeyValueQualifier, "did not parse a key/value qualifier")
    let aq = q! as! KeyValueQualifier
    
    XCTAssertEqual(aq.key, "person.aksa_status", "parsed key is incorrect")
  }

  func testSimpleBoolKeyValueQualifier() {
    let q = qualifierWithFormat( "isArchived")
    XCTAssertNotNil(q, "could not parse qualifier")

    XCTAssert(q! is KeyValueQualifier, "did not parse a key/value qualifier")
    guard let kvq = q as? KeyValueQualifier else { return }
    
    XCTAssertEqual(kvq.operation, .equalTo)
    XCTAssert(kvq.value is Bool)
    guard let bv = kvq.value as? Bool else { return }
    XCTAssertEqual(bv, true)
  }
  
  func testBoolKeyValueAndFrontQualifier() throws {
    let q = try XCTUnwrap(qualifierWithFormat( "isArchived AND code > 3"),
                          "could not parse qualifier")

    XCTAssert(q is CompoundQualifier, "did not parse an AND qualifier")
    let aq = try XCTUnwrap(q as? CompoundQualifier)
    XCTAssert(aq.op == .and, "did not parse an AND qualifier")
   
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
  }
  
  func testBoolKeyValueAndBackQualifier() throws {
    let q = try XCTUnwrap(qualifierWithFormat( "code > 3 AND isArchived"),
                          "could not parse qualifier")
    
    XCTAssert(q is CompoundQualifier, "did not parse an AND qualifier")
    let aq = try XCTUnwrap(q as? CompoundQualifier)
    XCTAssert(aq.op == .and, "did not parse an AND qualifier")
   
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
  }
  
  func testBoolKeyValueAndParenQualifier() throws {
    let q = try XCTUnwrap(qualifierWithFormat(
                            "(isArchived) AND code > 3 AND (isUsed)"),
                          "could not parse qualifier")

    XCTAssert(q is CompoundQualifier, "did not parse an AND qualifier")
    let aq = try XCTUnwrap(q as? CompoundQualifier)
    XCTAssert(aq.op == .and, "did not parse an AND qualifier")
   
    XCTAssert(aq.qualifiers[0] is KeyValueQualifier,
              "first qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[1] is KeyValueQualifier,
              "second qualifier is not a key/value qualifier")
    XCTAssert(aq.qualifiers[2] is KeyValueQualifier,
              "third qualifier is not a key/value qualifier")
  }
  
  func testSQLQualifier() throws {
    let q = try XCTUnwrap(qualifierWithFormat(
                         "SQL[lastname = $lastname AND balance = $balance]"),
                          "could not parse qualifier")

    XCTAssert(q is SQLQualifier, "did not parse a SQL qualifier")
    
    let parts = (try XCTUnwrap(q as? SQLQualifier)).parts
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

  func testPlainString() throws {
    // Actually the same like testSimpleBoolKeyValueQualifier, but for
    // clarity :-)
    let q = try XCTUnwrap(qualifierWithFormat( "hello"),
                          "could not parse qualifier")

    // Not sure whether this is actually intended :-) It makes sense for this:
    //   "lastname = 'abc' AND isLoggedIn" etc.
    XCTAssert(q is KeyValueQualifier, "did not parse a key/value qualifier")
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)

    XCTAssertEqual(kvq.operation, .equalTo)
    XCTAssert(kvq.value is Bool)
    guard let bv = kvq.value as? Bool else { return }
    XCTAssertEqual(bv, true)
  }


  // MARK: - CONTAINS/BEGINSWITH/ENDSWITH

  func testContainsQualifier() throws {
    let q = try XCTUnwrap(parse("name CONTAINS 'Zee'"))
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .contains)
    XCTAssertEqual(kvq.value as? String, "Zee")
  }

  func testCaseInsensitiveContainsQualifier() throws {
    let q = try XCTUnwrap(parse("name CONTAINS[c] 'zee'"))
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .caseInsensitiveContains)
    XCTAssertEqual(kvq.value as? String, "zee")
  }

  func testBeginsWithQualifier() throws {
    let q = try XCTUnwrap(parse("name BEGINSWITH 'Zee'"))
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .beginsWith)
    XCTAssertEqual(kvq.value as? String, "Zee")
  }

  func testCaseInsensitiveBeginsWithQualifier() throws {
    let q = try XCTUnwrap(parse("name BEGINSWITH[c] 'zee'"))
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .caseInsensitiveBeginsWith)
    XCTAssertEqual(kvq.value as? String, "zee")
  }

  func testEndsWithQualifier() throws {
    let q = try XCTUnwrap(parse("name ENDSWITH 'QL'"))
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .endsWith)
    XCTAssertEqual(kvq.value as? String, "QL")
  }

  func testCaseInsensitiveEndsWithQualifier() throws {
    let q = try XCTUnwrap(parse("name ENDSWITH[c] 'ql'"))
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .caseInsensitiveEndsWith)
    XCTAssertEqual(kvq.value as? String, "ql")
  }


  // MARK: - NOT IN

  func testNotInQualifier() throws {
    let list = [ "Mickey", "Goofy" ]
    let q = try XCTUnwrap(qualifierWithFormat( "name NOT IN %@", list))
    XCTAssert(q is KeyValueQualifier)
    let kvq = try XCTUnwrap(q as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .notIn)
  }

  func testNotInQualifierWithCompound() throws {
    let list = [ "Mickey", "Goofy" ]
    let q = try XCTUnwrap(
      qualifierWithFormat( "age > 10 AND name NOT IN %@", list)
    )
    XCTAssert(q is CompoundQualifier, "expected compound qualifier")
    let cq = try XCTUnwrap(q as? CompoundQualifier)
    XCTAssertEqual(cq.op, .and)
    XCTAssertEqual(cq.qualifiers.count, 2)

    let kvq = try XCTUnwrap(cq.qualifiers[1] as? KeyValueQualifier)
    XCTAssertEqual(kvq.key, "name")
    XCTAssertEqual(kvq.operation, .notIn)
  }


  // MARK: - Support

  private func checkTokenBoundary(_ input: String) {
    do { _ = try QualifierParser.parse(input, "key", 1) }
    catch let error as QualifierParser.ParserError {
      XCTAssertEqual(error.string, input)
      if case .invalidSyntax(_, let position, _) = error {
        XCTAssertGreaterThanOrEqual(position, 0, input)
        XCTAssertLessThanOrEqual(position, input.count, input)
      }
    }
    catch {
      XCTFail("unexpected error for \(input.debugDescription): \(error)")
    }
  }
  
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
    var parser = QualifierParser(string: fmt)
    let q = parser.parseQualifier()
    // TODO: check for errors
    return q
  }

  static var allTests = [
    ( "testSimpleKeyValueQualifierInt",    testSimpleKeyValueQualifierInt    ),
    ( "testSimpleKeyValueQualifierString", testSimpleKeyValueQualifierString ),
    ( "testUnterminatedQuotedStringsReturnNil",
      testUnterminatedQuotedStringsReturnNil ),
    ( "testTrailingFormatMarkerReturnsNil",
      testTrailingFormatMarkerReturnsNil ),
    ( "testThrowingParser",               testThrowingParser               ),
    ( "testThrowingParserReportsOriginalString",
      testThrowingParserReportsOriginalString ),
    ( "testThrowingParserReportsEmptyInput",
      testThrowingParserReportsEmptyInput ),
    ( "testMalformedTokenBoundariesDoNotTrap",
      testMalformedTokenBoundariesDoNotTrap ),
    ( "testComplexCompoundQualifier",      testComplexCompoundQualifier      ),
    ( "testAndBindsMoreTightlyThanOr",     testAndBindsMoreTightlyThanOr     ),
    ( "testComplexArgumentParsing",        testComplexArgumentParsing        ),
    ( "testQualifierWithOneVariables",     testQualifierWithOneVariables     ),
    ( "testQualifierWithSomeVariables",    testQualifierWithSomeVariables    ),
    ( "testQualifierWithParenthesis",      testQualifierWithParenthesis      ),
    ( "testSimpleBoolKeyValueQualifier",   testSimpleBoolKeyValueQualifier   ),
    ( "testBoolKeyValueAndFrontQualifier", testBoolKeyValueAndFrontQualifier ),
    ( "testBoolKeyValueAndBackQualifier",  testBoolKeyValueAndBackQualifier  ),
    ( "testBoolKeyValueAndParenQualifier", testBoolKeyValueAndParenQualifier ),
    ( "testSQLQualifier",                  testSQLQualifier                  ),
    ( "testPlainString",                   testPlainString                   ),
    ( "testContainsQualifier",             testContainsQualifier             ),
    ( "testCaseInsensitiveContainsQualifier",
      testCaseInsensitiveContainsQualifier ),
    ( "testBeginsWithQualifier",           testBeginsWithQualifier           ),
    ( "testCaseInsensitiveBeginsWithQualifier",
      testCaseInsensitiveBeginsWithQualifier ),
    ( "testEndsWithQualifier",             testEndsWithQualifier             ),
    ( "testCaseInsensitiveEndsWithQualifier",
      testCaseInsensitiveEndsWithQualifier ),
    ( "testNotInQualifier",                testNotInQualifier                ),
    ( "testNotInQualifierWithCompound",    testNotInQualifierWithCompound    ),
  ]
}
