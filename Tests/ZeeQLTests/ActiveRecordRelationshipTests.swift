//
//  ActiveRecordRelationshipTests.swift
//  ZeeQL
//

import Foundation
import XCTest
@testable import ZeeQL

class ActiveRecordRelationshipTests: XCTestCase {

  func testRemoveObjectStoresFlatToManyCollection() throws {
    let entity = ModelEntity(name: "Parent")
    let adaptor = FakeAdaptor(model: Model(entities: [ entity ]))
    let record = ActiveRecord()
    record.bind(to: Database(adaptor: adaptor), entity: entity)
    let first = NSObject()
    let second = NSObject()
    record.takeStoredValue([ first, second ], forKey: "children")

    record.removeObject(first, fromPropertyWithKey: "children")

    let remaining = try XCTUnwrap(
      record.storedValueForKey("children") as? [ AnyObject ])
    XCTAssertEqual(remaining.count, 1)
    XCTAssertTrue(remaining[0] === second)

    record.removeObject(second, fromPropertyWithKey: "children")

    let empty = try XCTUnwrap(
      record.storedValueForKey("children") as? [ AnyObject ])
    XCTAssertTrue(empty.isEmpty)
  }
}
