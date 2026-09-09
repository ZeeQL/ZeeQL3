//
//  AdaptorDataSourceTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

class AdaptorDataSourceTests: XCTestCase {

  func testFetchReusesAndReturnsPooledChannel() throws {
    let ( source, pool, channel ) = try makePooledSource()

    for _ in 0..<2 {
      let records = try source.fetchObjects()
      XCTAssertEqual(records.count, 1)
      XCTAssertEqual(records.first?["name"] as? String, "Duck")
    }

    let returned = try XCTUnwrap(pool.grab())
    XCTAssertTrue(returned as AnyObject === channel as AnyObject)
  }

  func testCallbackErrorReturnsPooledChannel() throws {
    let ( source, pool, channel ) = try makePooledSource()
    let specification = try source.fetchSpecificationForFetch()

    XCTAssertThrowsError(try source.fetchObjects(specification) { _ in
      throw FetchError.callback
    }) { error in
      XCTAssertEqual(error as? FetchError, .callback)
    }

    let returned = try XCTUnwrap(pool.grab())
    XCTAssertTrue(returned as AnyObject === channel as AnyObject)
    pool.add(returned)
    XCTAssertEqual(try source.fetchObjects().count, 1)
  }

  func testQueryErrorReturnsPooledChannel() throws {
    let ( source, pool, original ) = try makePooledSource()
    let channel = try XCTUnwrap(pool.grab())
    try channel.performSQL("DROP TABLE sample")
    source.adaptor.releaseChannel(channel)

    XCTAssertThrowsError(try source.fetchObjects())

    let returned = try XCTUnwrap(pool.grab())
    XCTAssertTrue(returned as AnyObject === original as AnyObject)
    XCTAssertFalse(returned.isTransactionInProgress)
  }

  func testFetchOpensChannelWhenPoolIsEmpty() throws {
    let pool   = SingleConnectionPool(maxAge: 60)
    let source = try makeConstantSource(pool: pool)

    XCTAssertEqual(try source.fetchObjects().first?["name"] as? String,
                   "Duck")
    XCTAssertNotNil(pool.grab())
  }

  func testFetchWorksWithoutConfiguredPool() throws {
    let source = try makeConstantSource(pool: nil)

    XCTAssertEqual(try source.fetchObjects().first?["name"] as? String,
                   "Duck")
  }

  private func makeSource(pool: AdaptorChannelPool?) -> AdaptorDataSource {
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    let entity  = ModelEntity(name: "Sample", table: "sample")
    entity.attributes = [ ModelAttribute(name: "name") ]
    return AdaptorDataSource(adaptor: adaptor, entity: entity)
  }

  private func makeConstantSource(pool: AdaptorChannelPool?) throws
    -> AdaptorDataSource
  {
    let source = makeSource(pool: pool)
    var specification = try source.fetchSpecificationForFetch()
    specification.hints["CustomQueryExpressionHintKey"] =
      "SELECT 'Duck' AS name"
    source.fetchSpecification = specification
    return source
  }

  private func makePooledSource() throws
    -> ( AdaptorDataSource, SingleConnectionPool, AdaptorChannel )
  {
    let pool    = SingleConnectionPool(maxAge: 60)
    let source  = makeSource(pool: pool)
    let channel = try source.adaptor.openChannel()
    try channel.performSQL("CREATE TABLE sample (name TEXT)")
    try channel.performSQL("INSERT INTO sample VALUES ('Duck')")
    source.adaptor.releaseChannel(channel)
    return ( source, pool, channel )
  }

  private enum FetchError: Error {

    case callback
  }
}
