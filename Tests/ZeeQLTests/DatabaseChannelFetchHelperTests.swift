//
//  DatabaseChannelFetchHelperTests.swift
//  ZeeQL
//

import Foundation
import XCTest
@testable import ZeeQL

class DatabaseChannelFetchHelperTests: XCTestCase {

  func testSupportedJoinValuesAreCollected() throws {
    let uuid = UUID()
    let date = Date(timeIntervalSince1970: 42)
    let data = Data([ 1, 2, 3 ])
    let rawValues: [ Any ] = [
      "string-key", uuid, UInt(7), date, data, Decimal(12)
    ]
    let objects = rawValues.map(makeObject)
    let helper = DatabaseChannelFetchHelper(baseObjects: objects)

    let values = try helper.getSourceValues("joinKey")
    XCTAssertEqual(values.count, rawValues.count)
    XCTAssertEqual(Set(values),
                   Set(rawValues.compactMap { $0 as? AnyHashable }))
  }

  func testEquivalentIntegerWidthsShareJoinBucket() throws {
    let first = makeObject(Int(7))
    let second = makeObject(Int64(7))
    let helper = DatabaseChannelFetchHelper(baseObjects: [ first, second ])

    let values = try helper.getSourceValues("joinKey")
    XCTAssertEqual(values.count, 1)
    let objects = try helper.getValueToObjects("joinKey")
    XCTAssertEqual(objects[try XCTUnwrap(values.first)]?.count, 2)
  }

  func testUnsupportedJoinValueThrowsRecoverableError() {
    let helper = DatabaseChannelFetchHelper(
      baseObjects: [ makeObject(UnsupportedJoinValue()) ])

    XCTAssertThrowsError(try helper.getSourceValues("joinKey")) { error in
      guard case DatabaseChannelError.unsupportedPrefetchJoinValue = error
      else { return XCTFail("Unexpected prefetch error: \(error)") }
    }
  }

  func testStringKeyRelationshipPrefetch() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("CREATE TABLE parent(id TEXT PRIMARY KEY)")
    try adaptor.performSQL(
      "CREATE TABLE child(id INTEGER PRIMARY KEY, parent_id TEXT)")
    try adaptor.performSQL("INSERT INTO parent VALUES ('A'), ('B')")
    try adaptor.performSQL("INSERT INTO child VALUES (1, 'A'), (2, 'B')")

    let parent = ModelEntity(name: "Parent", table: "parent")
    parent.className = "ActiveRecord"
    let parentID = ModelAttribute(name: "id", column: "id",
                                  externalType: "TEXT")
    parent.attributes = [ parentID ]
    parent.primaryKeyAttributeNames = [ "id" ]

    let child = ModelEntity(name: "Child", table: "child")
    child.className = "ActiveRecord"
    let childID = ModelAttribute(name: "id", column: "id",
                                 externalType: "INTEGER")
    let childParentID = ModelAttribute(name: "parentID", column: "parent_id",
                                       externalType: "TEXT")
    child.attributes = [ childID, childParentID ]
    child.primaryKeyAttributeNames = [ "id" ]

    let children = ModelRelationship(name: "children", isToMany: true,
                                     source: parent, destination: child)
    children.joins = [ Join(source: parentID, destination: childParentID) ]
    parent.relationships = [ children ]

    adaptor.model = Model(entities: [ parent, child ])
    let types = StaticObjectTypeLookupContext([ "ActiveRecord":
                                                ActiveRecord.self ])
    let database = Database(adaptor: adaptor, objectTypes: types)
    let dataSource = ActiveDataSource<ActiveRecord>(database: database,
                                                    entity: parent)
    var fetch = ModelFetchSpecification(entity: parent)
    fetch.prefetchingRelationshipKeyPathes = [ "children" ]
    dataSource.fetchSpecification = fetch

    let objects = try dataSource.fetchObjects()
    XCTAssertEqual(objects.count, 2)
    for object in objects {
      let id = try XCTUnwrap(object.storedValueForKey("id") as? String)
      let values = object.storedValueForKey("children")
      let children = try XCTUnwrap(values as? [ ActiveRecord ])
      XCTAssertEqual(children.count, 1)
      XCTAssertEqual(children[0].storedValueForKey("parentID") as? String, id)
    }
  }

  private func makeObject(_ value: Any) -> DatabaseObject {
    let object = ActiveRecord()
    object.takeStoredValue(value, forKey: "joinKey")
    return object
  }
}

private final class UnsupportedJoinValue {}
