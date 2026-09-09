//
//  SQLite3BindingTests.swift
//  ZeeQL
//

import Foundation
import XCTest
@testable import ZeeQL

class SQLite3BindingTests: XCTestCase {

  func testIntegerBindingsRoundTripAsIntegers() throws {
    try assertInteger(Int(-1), expected: -1)
    try assertInteger(Int8(-2), expected: -2)
    try assertInteger(Int16(-3), expected: -3)
    try assertInteger(Int32(-4), expected: -4)
    try assertInteger(Int64(-5), expected: -5)
    try assertInteger(UInt(1), expected: 1)
    try assertInteger(UInt8(2), expected: 2)
    try assertInteger(UInt16(3), expected: 3)
    try assertInteger(UInt32(4), expected: 4)
    try assertInteger(UInt64(5), expected: 5)
    try assertInteger(true, expected: 1)
    try assertInteger(false, expected: 0)
  }

  func testFloatingPointBindingsRoundTripAsReal() throws {
    let float = try fetchBoundValue(Float(1.25))
    XCTAssertEqual(float.storageClass, "real")
    XCTAssertEqual(float.value as? Double, 1.25)

    let double = try fetchBoundValue(Double(2.5))
    XCTAssertEqual(double.storageClass, "real")
    XCTAssertEqual(double.value as? Double, 2.5)
  }

  func testDataBindingsRoundTripAsBlobs() throws {
    let data = Data([ 0, 1, 2, 255 ])
    let result = try fetchBoundValue(data)
    XCTAssertEqual(result.storageClass, "blob")
    XCTAssertEqual(result.value as? Data, data)

    let empty = try fetchBoundValue(Data())
    XCTAssertEqual(empty.storageClass, "blob")
    XCTAssertEqual(empty.value as? Data, Data())
  }

  func testFoundationBindingsRoundTripWithoutFallbackDescriptions() throws {
    let date = Date(timeIntervalSince1970: 1_234.5)
    let dateResult = try fetchBoundValue(date)
    XCTAssertEqual(dateResult.storageClass, "real")
    XCTAssertEqual(try Date.fromAdaptorQueryValue(dateResult.value), date)

    let decimal = try XCTUnwrap(Decimal(string: "123456.789"))
    let decimalResult = try fetchBoundValue(decimal)
    XCTAssertEqual(decimalResult.storageClass, "text")
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(decimalResult.value),
                   decimal)

    let uuid = try XCTUnwrap(
      UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
    let uuidResult = try fetchBoundValue(uuid)
    XCTAssertEqual(uuidResult.storageClass, "text")
    XCTAssertEqual(try UUID.fromAdaptorQueryValue(uuidResult.value), uuid)

    let url = try XCTUnwrap(URL(string: "https://example.com/a?b=c"))
    let urlResult = try fetchBoundValue(url)
    XCTAssertEqual(urlResult.storageClass, "text")
    XCTAssertEqual(urlResult.value as? String, url.absoluteString)
  }

  func testStringBindingRoundTripsAsText() throws {
    let result = try fetchBoundValue("ZeeQL")
    XCTAssertEqual(result.storageClass, "text")
    XCTAssertEqual(result.value as? String, "ZeeQL")
  }

  func testNullBindingRoundTripsAsNull() throws {
    let result = try fetchBoundValue(nil)
    XCTAssertEqual(result.storageClass, "null")
    XCTAssertNil(result.value)
  }

  func testOutOfRangeAndUnsupportedBindingsFail() throws {
    XCTAssertThrowsError(try fetchBoundValue(UInt64.max))
    XCTAssertThrowsError(try fetchBoundValue(UnsupportedBindingValue()))
  }

  private func assertInteger(_ value: Any, expected: Int64) throws {
    let result = try fetchBoundValue(value)
    XCTAssertEqual(result.storageClass, "integer")
    XCTAssertEqual(result.value as? Int64, expected)
  }

  private func fetchBoundValue(_ value: Any?) throws
    -> ( storageClass: String, value: Any? )
  {
    let channel = try SQLite3Adaptor(":memory:").openChannel()
    let expression = SQLExpression(entity: nil)
    expression.statement = "SELECT typeof(?), ?"
    let variable = SQLExpression.BindVariable(attribute: nil, value: value)
    expression.bindVariables = [ variable, variable ]
    var record: AdaptorRecord?
    try channel.evaluateQueryExpression(expression, nil) { record = $0 }
    let result = try XCTUnwrap(record)
    return ( try XCTUnwrap(result[0] as? String), result[1] )
  }
}

private final class UnsupportedBindingValue {}
