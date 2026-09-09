//
//  AdaptorChannelStreamingTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

class AdaptorChannelStreamingTests: XCTestCase {

  func testMappedRowsAreDeliveredAsTheyAreProduced() throws {
    let entity  = makeEntity()
    let channel = StreamingTestChannel()
    var names   = [ String ]()

    try channel.selectAttributes(nil, ModelFetchSpecification(entity: entity),
                                 lock: false, entity) 
    { record in
      names.append(try XCTUnwrap(record["name"] as? String))
      XCTAssertEqual(channel.producedCount, names.count)
    }

    XCTAssertEqual(names, [ "Alpha", "Beta" ])
    XCTAssertEqual(channel.requestedAttributes?.map { $0.name }, [ "name" ])
  }

  func testConsumerErrorStopsRowProduction() throws {
    let entity  = makeEntity()
    let channel = StreamingTestChannel()

    XCTAssertThrowsError(try channel.selectAttributes(
      nil, ModelFetchSpecification(entity: entity), lock: false, entity)
    { _ in
      throw StreamingTestError.consumer
    }) { error in
      XCTAssertEqual(error as? StreamingTestError, .consumer)
    }

    XCTAssertEqual(channel.producedCount, 1)
    XCTAssertEqual(channel.completedCallbacks, 0)
  }

  func testProducerErrorPreservesAlreadyDeliveredRows() throws {
    let entity  = makeEntity()
    let channel = StreamingTestChannel()
    channel.values = [ "Alpha" ]
    channel.failAfterRows = true
    var names = [ String ]()

    XCTAssertThrowsError(try channel.selectAttributes(
      nil, ModelFetchSpecification(entity: entity), lock: false, entity)
    { record in
      names.append(try XCTUnwrap(record["name"] as? String))
    }) { error in
      XCTAssertEqual(error as? StreamingTestError, .producer)
    }

    XCTAssertEqual(names, [ "Alpha" ])
  }

  func testSharedSchemaIsMappedOnlyOnce() throws {
    let entity  = makeEntity()
    let schema  = MappingTestSchema()
    let channel = StreamingTestChannel(schema: schema)
    var count   = 0

    try channel.selectAttributes(nil, ModelFetchSpecification(entity: entity),
                                 lock: false, entity) 
    { record in
      count += 1
      XCTAssertTrue(record.schema === schema)
      XCTAssertEqual(record.schema.attributeNames, [ "name" ])
      XCTAssertNotNil(record["name"])
      XCTAssertNil(record["full_name"])
    }

    XCTAssertEqual(count, 2)
    XCTAssertEqual(schema.switchCount, 1)
  }

  func testRawRowsKeepColumnNames() throws {
    let entity  = makeEntity()
    let schema  = MappingTestSchema()
    let channel = StreamingTestChannel(schema: schema)
    var specification = ModelFetchSpecification(entity: entity)
    specification.fetchesRawRows = true
    var count = 0

    try channel.selectAttributes(nil, specification, lock: false, entity) {
      count += 1
      XCTAssertEqual($0.schema.attributeNames, [ "full_name" ])
      XCTAssertNotNil($0["full_name"])
      XCTAssertEqual(channel.producedCount, count)
    }

    XCTAssertEqual(count, 2)
    XCTAssertEqual(schema.switchCount, 0)
    XCTAssertNil(channel.requestedAttributes)
  }

  func testAttributeBackedSchemaKeepsMappedNames() throws {
    let entity  = makeEntity()
    let schema  = AdaptorRecordSchemaWithAttributes(entity.attributes)
    let channel = StreamingTestChannel(schema: schema)
    var names   = [ String ]()

    try channel.selectAttributes(nil, ModelFetchSpecification(entity: entity),
                                 lock: false, entity) 
    { record in
      names.append(try XCTUnwrap(record["name"] as? String))
    }

    XCTAssertEqual(names, [ "Alpha", "Beta" ])
    XCTAssertEqual(schema.attributeNames, [ "name" ])
  }

  func testDeliveredRecordsAreNotRetainedBySelection() throws {
    let entity  = makeEntity()
    let channel = StreamingTestChannel()
    weak var previous: AdaptorRecord?
    var count = 0

    try channel.selectAttributes(nil, ModelFetchSpecification(entity: entity),
                                  lock: false, entity) { record in
      XCTAssertNil(previous)
      previous = record
      count += 1
    }

    XCTAssertEqual(count, 2)
    XCTAssertNil(previous)
  }

  func testEmptyResultDoesNotMapSchemaOrCallConsumer() throws {
    let entity  = makeEntity()
    let schema  = MappingTestSchema()
    let channel = StreamingTestChannel(schema: schema)
    channel.values = []

    try channel.selectAttributes(nil, ModelFetchSpecification(entity: entity),
                                 lock: false, entity) 
    { _ in
      XCTFail("Unexpected row for an empty result")
    }

    XCTAssertEqual(schema.switchCount, 0)
    XCTAssertEqual(channel.producedCount, 0)
  }

  private func makeEntity() -> ModelEntity {
    let entity = ModelEntity(name: "Record", table: "records")
    entity.attributes = [ ModelAttribute(name: "name", column: "full_name") ]
    return entity
  }
  
  // Helpers
  
  private enum StreamingTestError: Error {
    case consumer
    case producer
  }

  private final class StreamingTestChannel: FakeAdaptor.FakeAdaptorChannel {

    let schema              : AdaptorRecordSchema
    var requestedAttributes : [ Attribute ]?
    var values              = [ "Alpha", "Beta" ]
    var producedCount       = 0
    var completedCallbacks  = 0
    var failAfterRows        = false

    init(schema: AdaptorRecordSchema = MappingTestSchema()) {
      self.schema = schema
      super.init(adaptor: FakeAdaptor())
    }

    override func evaluateQueryExpression(_ expression: SQLExpression,
                                          _ attributes: [ Attribute ]?,
                                          result: (AdaptorRecord) throws -> Void)
      throws
    {
      requestedAttributes = attributes
      for value in values {
        let record = AdaptorRecord(schema: schema, values: [ value ])
        producedCount += 1
        try result(record)
        completedCallbacks += 1
      }
      if failAfterRows { throw StreamingTestError.producer }
    }
  }

  private final class MappingTestSchema: AdaptorRecordSchema {

    var attributeNames = [ "full_name" ]
    var switchCount    = 0
    var attributes : [ Attribute ]? { return nil }
    var count      : Int { return attributeNames.count }

    func switchKey(_ oldKey: String, to newKey: String) -> Bool {
      switchCount += 1
      guard let index = attributeNames.firstIndex(of: oldKey) else {
        return false
      }
      attributeNames[index] = newKey
      return true
    }
  }
}

