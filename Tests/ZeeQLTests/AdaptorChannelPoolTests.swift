//
//  AdaptorChannelPoolTests.swift
//  ZeeQL
//

import Foundation
import XCTest
@testable import ZeeQL

class AdaptorChannelPoolTests: XCTestCase {

  func testSingleConnectionPoolKeepsYoungEntry() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let channel = try FakeAdaptor().openChannel()

    pool.add(channel)
    pool.expire()

    let reused = try XCTUnwrap(pool.grab())
    XCTAssertTrue(reused as AnyObject === channel as AnyObject)
  }

  func testSingleConnectionPoolRemovesExpiredEntry() throws {
    let pool = SingleConnectionPool(maxAge: 0.001)
    let channel = try FakeAdaptor().openChannel()

    pool.add(channel)
    Thread.sleep(forTimeInterval: 0.01)
    pool.expire()

    XCTAssertNil(pool.grab())
  }
}
