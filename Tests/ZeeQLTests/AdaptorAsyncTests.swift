//
//  AdaptorAsyncTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 12/04/2026.
//  Copyright © 2026 ZeeZide GmbH. All rights reserved.
//

#if swift(>=5.5)
import Foundation
import XCTest
@testable import ZeeQL

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class AdaptorAsyncTests: XCTestCase {

  private func makeAdaptor() -> SQLite3Adaptor {
    return SQLite3Adaptor(":memory:", autocreate: true,
                          pool: SingleConnectionPool(maxAge: 60))
  }

  private func makeAdaptorWithTable() async throws -> SQLite3Adaptor {
    let adaptor = makeAdaptor()
    try await adaptor.performSQL(
      "CREATE TABLE company(company_id INTEGER PRIMARY KEY, name TEXT NOT NULL)"
    )
    return adaptor
  }


  // MARK: - Basic Queries

  func testPerformSQL() async throws {
    let adaptor = makeAdaptor()
    try await adaptor.performSQL(
      "CREATE TABLE company (company_id INTEGER PRIMARY KEY)"
    )
    let count = try await adaptor.performSQL("INSERT INTO company VALUES (1)")
    XCTAssertEqual(count, 1)
  }

  func testQuerySQL() async throws {
    let adaptor = try await makeAdaptorWithTable()
    try await adaptor.performSQL("INSERT INTO company VALUES (1, 'Apple')")
    try await adaptor.performSQL("INSERT INTO company VALUES (2, 'Pixar')")

    let records = try await adaptor.querySQL(
      "SELECT company_id, name FROM company ORDER BY company_id"
    )
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records[0]["name"] as? String, "Apple")
    XCTAssertEqual(records[1]["name"] as? String, "Pixar")
  }

  func testTypedSelect() async throws {
    let adaptor = try await makeAdaptorWithTable()
    try await adaptor.performSQL("INSERT INTO company VALUES (1, 'Apple')")
    try await adaptor.performSQL("INSERT INTO company VALUES (2, 'Pixar')")

    let rows: [ ( Int, String ) ] = try await adaptor.select(
      "SELECT company_id, name FROM company ORDER BY company_id"
    )
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(rows[0].0, 1)
    XCTAssertEqual(rows[0].1, "Apple")
    XCTAssertEqual(rows[1].0, 2)
    XCTAssertEqual(rows[1].1, "Pixar")
  }

  func testWithChannel() async throws {
    let adaptor = try await makeAdaptorWithTable()
    try await adaptor.performSQL("INSERT INTO company VALUES (1, 'Apple')")

    let names: [ String ] = try await adaptor.withChannel { ch in
      var result = [ String ]()
      try ch.querySQL("SELECT name FROM company") { record in
        if let n = record["name"] as? String { result.append(n) }
      }
      return result
    }
    XCTAssertEqual(names, [ "Apple" ])
  }

  func testTransaction() async throws {
    let adaptor = try await makeAdaptorWithTable()

    try await adaptor.transaction { ch in
      try ch.performSQL("INSERT INTO company VALUES (1, 'Apple')")
      try ch.performSQL("INSERT INTO company VALUES (2, 'Pixar')")
    }

    let records = try await adaptor.querySQL("SELECT * FROM company")
    XCTAssertEqual(records.count, 2)
  }

  func testTransactionRollback() async throws {
    enum _TestError: Error { case intentional }

    let adaptor = try await makeAdaptorWithTable()

    do {
      try await adaptor.transaction { ch in
        try ch.performSQL("INSERT INTO company VALUES (1, 'Apple')")
        throw _TestError.intentional
      }
      XCTFail("Should have thrown")
    }
    catch is _TestError {}

    let records = try await adaptor.querySQL("SELECT * FROM company")
    XCTAssertEqual(records.count, 0,
                   "Transaction should have been rolled back")
  }


  func testCustomRunner() async throws {
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    final class _MockRunner: AdaptorAsyncRunner, @unchecked Sendable {
      var didRun = false

      func run<R>(_ operation: @Sendable @escaping () throws -> R)
        async throws -> R
        where R: Sendable
      {
        didRun = true
        return try operation()
      }
    }

    let mock = _MockRunner()
    let adaptor = SQLite3Adaptor(":memory:", autocreate: true,
                                 pool: SingleConnectionPool(maxAge: 60),
                                 asyncRunner: mock)
    try await adaptor.performSQL(
      "CREATE TABLE company(company_id INTEGER PRIMARY KEY, name TEXT NOT NULL)"
    )
    try await adaptor.performSQL("INSERT INTO company VALUES (1, 'Apple')")

    let records = try await adaptor.querySQL("SELECT * FROM company")
    XCTAssertEqual(records.count, 1)
    XCTAssertTrue(mock.didRun, "Custom runner should have been used")
  }
}

#endif
