//
//  UUIDDecimalTypeTests.swift
//  ZeeQLTests
//
//  Created by Helge Heß on 06/07/26.
//  Copyright © 2026 ZeeZide GmbH. All rights reserved.
//

import XCTest
import Foundation
@testable import ZeeQL

final class UUIDDecimalTypeTests: XCTestCase {

  // MARK: - AttributeValue conformance

  func testUUIDIsAttributeValue() throws {
    XCTAssertFalse(UUID.isOptional)
    XCTAssertEqual("\(try XCTUnwrap(UUID.optionalBaseType))", "UUID")
    XCTAssertEqual("\(try XCTUnwrap(UUID.optionalType))", "Optional<UUID>")
  }


  // MARK: - valueTypeForExternalType (SQL type => Swift type)

  func testValueTypeForUUID() throws {
    let nonNull = try XCTUnwrap(
      ZeeQLTypes.valueTypeForExternalType("UUID", allowsNull: false))
    XCTAssertEqual(ObjectIdentifier(nonNull), ObjectIdentifier(UUID.self))
    let opt = try XCTUnwrap(
      ZeeQLTypes.valueTypeForExternalType("UUID", allowsNull: true))
    XCTAssertEqual(ObjectIdentifier(opt),
                   ObjectIdentifier(Optional<UUID>.self))
  }

  func testValueTypeForNumeric() throws {
    let nonNull = try XCTUnwrap(
      ZeeQLTypes.valueTypeForExternalType("NUMERIC(10,2)", allowsNull: false))
    XCTAssertEqual(ObjectIdentifier(nonNull), ObjectIdentifier(Decimal.self))
    let opt = try XCTUnwrap(
      ZeeQLTypes.valueTypeForExternalType("NUMERIC", allowsNull: true))
    XCTAssertEqual(ObjectIdentifier(opt),
                   ObjectIdentifier(Optional<Decimal>.self))
  }


  // MARK: - externalTypeFor (Swift type => SQL type)

  func testExternalTypeForSwiftTypeName() {
    XCTAssertEqual(ZeeQLTypes.externalTypeFor(swiftType: "UUID"),    "UUID")
    XCTAssertEqual(ZeeQLTypes.externalTypeFor(swiftType: "Decimal"), "NUMERIC")
  }

  func testExternalTypeForSwiftType() {
    XCTAssertEqual(ZeeQLTypes.externalTypeFor(swiftType: UUID.self), "UUID")
    XCTAssertEqual(ZeeQLTypes.externalTypeFor(swiftType: Decimal.self),
                   "NUMERIC")
    XCTAssertEqual(ZeeQLTypes.externalTypeFor(swiftType: UUID.self,
                                              includeConstraint: true),
                   "UUID NOT NULL")
    XCTAssertEqual(ZeeQLTypes.externalTypeFor(swiftType: Optional<UUID>.self,
                                              includeConstraint: true),
                   "UUID NULL")
    XCTAssertEqual(ZeeQLTypes.externalTypeFor(swiftType: Optional<Decimal>.self,
                                              includeConstraint: true),
                   "NUMERIC NULL")
  }


  // MARK: - AdaptorQueryColumnRepresentable coercion

  func testUUIDFromAdaptorQueryValue() throws {
    let u = UUID()
    XCTAssertEqual(try UUID.fromAdaptorQueryValue(u), u)
    XCTAssertEqual(try UUID.fromAdaptorQueryValue(u.uuidString), u)
    XCTAssertThrowsError(try UUID.fromAdaptorQueryValue(nil))
    XCTAssertThrowsError(try UUID.fromAdaptorQueryValue("not-a-uuid"))
  }

  func testUUIDFromData() throws {
    let u    = UUID()
    let data = withUnsafeBytes(of: u.uuid) { Data($0) }
    XCTAssertEqual(data.count, 16)
    XCTAssertEqual(try UUID.fromAdaptorQueryValue(data), u)
    // Wrong length must not be coerced.
    XCTAssertThrowsError(try UUID.fromAdaptorQueryValue(Data([ 1, 2, 3 ])))
  }

  #if compiler(>=6)
  @available(macOS 15, iOS 13, *)
  func testUUIDFromUInt128() throws {
    // 128-bit value == big-endian interpretation of the UUID's 16 bytes.
    let n: UInt128 = 0x00112233_44556677_8899aabb_ccddeeff
    let expected =
      try XCTUnwrap(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
    XCTAssertEqual(try UUID.fromAdaptorQueryValue(n), expected)
  }
  #endif

  func testDecimalFromAdaptorQueryValue() throws {
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(Decimal(5)), Decimal(5))
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(3), Decimal(3)) // Int
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue("12.5"),
                   try XCTUnwrap(Decimal(string: "12.5")))
    XCTAssertThrowsError(try Decimal.fromAdaptorQueryValue(nil))
  }

  func testDecimalFromFloatAndBinaryIntegers() throws {
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(Float(1.5)), Decimal(1.5))
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(Int32(42)),  Decimal(42))
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(UInt(7)),    Decimal(7))
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(Int64(-9)),  Decimal(-9))
    XCTAssertEqual(try Decimal.fromAdaptorQueryValue(UInt64.max),
                   Decimal(UInt64.max))
  }
}
