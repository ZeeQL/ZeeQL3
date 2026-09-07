//
//  ActiveRecordRelationshipTests.swift
//  ZeeQL
//

import Foundation
import XCTest
@testable import ZeeQL

class ActiveRecordRelationshipTests: XCTestCase {

  func testDefaultsUseStaticEntityCardinality() throws {
    let record = StaticEntityRelationshipObject()
    let first  = ActiveRecord()
    let second = ActiveRecord()
    let subject: RelationshipManipulation = record

    subject.addObject(first, toPropertyWithKey: "children")
    subject.addObject(second, toPropertyWithKey: "children")
    let children = try XCTUnwrap(record.values["children"] as? [ AnyObject ])
    XCTAssertEqual(children.count, 2)
    XCTAssertTrue(children[0] === first)
    XCTAssertTrue(children[1] === second)

    let target = NSObject()
    subject.addObject(target, toPropertyWithKey: "child")
    XCTAssertTrue(record.values["child"] as? NSObject === target)
    subject.removeObject(NSObject(), fromPropertyWithKey: "child")
    XCTAssertTrue(record.values["child"] as? NSObject === target)
    subject.removeObject(target, fromPropertyWithKey: "child")
    XCTAssertNil(record.values["child"])
  }

  func testDefaultsPreferInstanceEntityCardinality() {
    let record  = InstanceEntityRelationshipObject()
    let target  = NSObject()
    let subject : RelationshipManipulation = record

    XCTAssertEqual(type(of: record).entity[relationship: "child"]?.isToMany,
                   true)
    XCTAssertEqual(record.entity[relationship: "child"]?.isToMany, false)
    subject.addObject(target, toPropertyWithKey: "child")
    XCTAssertTrue(record.values["child"] as? NSObject === target)
    subject.removeObject(target, fromPropertyWithKey: "child")
    XCTAssertNil(record.values["child"])
  }

  func testDefaultsTreatMissingMetadataAsToMany() throws {
    let records: [ DefaultRelationshipObject ] = [
      DefaultRelationshipObject(), StaticEntityRelationshipObject()
    ]
    for record in records {
      let first  = ActiveRecord()
      let second = ActiveRecord()

      record.removeObject(first, fromPropertyWithKey: "unmodeled")
      XCTAssertEqual(record.writeAttempts, 0)
      record.addObject(first, toPropertyWithKey: "unmodeled")
      record.addObject(second, toPropertyWithKey: "unmodeled")
      record.addObject(first, toPropertyWithKey: "unmodeled")
      XCTAssertEqual(record.writeAttempts, 2)
      record.removeObject(ActiveRecord(), fromPropertyWithKey: "unmodeled")
      XCTAssertEqual(record.writeAttempts, 2)

      record.removeObject(first, fromPropertyWithKey: "unmodeled")
      let remaining = try XCTUnwrap(
        record.values["unmodeled"] as? [ AnyObject ])
      XCTAssertEqual(remaining.count, 1)
      XCTAssertTrue(remaining[0] === second)

      record.removeObject(second, fromPropertyWithKey: "unmodeled")
      let empty = try XCTUnwrap(record.values["unmodeled"] as? [ AnyObject ])
      XCTAssertTrue(empty.isEmpty)
    }
  }

  func testDefaultsPreserveUnexpectedToManyValues() {
    let record = StaticEntityRelationshipObject()
    let target = ActiveRecord()
    for key in [ "children", "unmodeled" ] {
      record.values[key] = "not a collection"
      record.addObject(target, toPropertyWithKey: key)
      record.removeObject(target, fromPropertyWithKey: key)
      XCTAssertEqual(record.values[key] as? String, "not a collection")
    }
    XCTAssertEqual(record.writeAttempts, 0)
  }

  func testDefaultsLogRejectedKVCWrites() throws {
    let logger         = RelationshipFailureLogger()
    let originalLogger = globalZeeQLLogger
    globalZeeQLLogger = logger
    defer { globalZeeQLLogger = originalLogger }

    let record = StaticEntityRelationshipObject()
    let first  = ActiveRecord()
    let second = ActiveRecord()
    record.values["child"]    = first
    record.values["children"] = [ first ]
    record.rejectWrites = true

    for key in [ "child", "children" ] {
      record.addObject(second, toPropertyWithKey: key)
      record.removeObject(first, fromPropertyWithKey: key)
    }

    XCTAssertEqual(record.writeAttempts, 4)
    XCTAssertTrue(record.values["child"] as? ActiveRecord === first)
    let children = try XCTUnwrap(record.values["children"] as? [ AnyObject ])
    XCTAssertEqual(children.count, 1)
    XCTAssertTrue(children[0] === first)
    XCTAssertEqual(logger.errors.count, 4)
    for error in logger.errors {
      guard case DefaultRelationshipObject.WriteError.rejected = error else {
        return XCTFail("Unexpected logged error: \(error)")
      }
    }
  }

  func testProtocolDispatchUsesRelationshipCardinality() throws {
    let entity = ModelEntity(name: "Parent")
    let target = ModelEntity(name: "Child")
    entity.relationships = [
      ModelRelationship(name: "child", source: entity, destination: target),
      ModelRelationship(name: "children", isToMany: true, source: entity,
                        destination: target)
    ]
    let adaptor = FakeAdaptor(model: Model(entities: [ entity, target ]))
    let record  = ActiveRecord()
    record.bind(to: Database(adaptor: adaptor), entity: entity)
    let subject : RelationshipManipulation = record
    let first   = ActiveRecord()
    let second  = ActiveRecord()

    subject.addObject(first, toPropertyWithKey: "children")
    subject.addObject(second, toPropertyWithKey: "children")
    subject.addObject(first, toPropertyWithKey: "children")

    let children = try XCTUnwrap(
      record.storedValueForKey("children") as? [ AnyObject ])
    XCTAssertEqual(children.count, 2)
    XCTAssertTrue(children[0] === first)
    XCTAssertTrue(children[1] === second)

    subject.removeObject(first, fromPropertyWithKey: "children")
    let remaining = try XCTUnwrap(
      record.storedValueForKey("children") as? [ AnyObject ])
    XCTAssertEqual(remaining.count, 1)
    XCTAssertTrue(remaining[0] === second)

    subject.addObject(first, toPropertyWithKey: "child")
    XCTAssertTrue(record.storedValueForKey("child") as? ActiveRecord === first)
    subject.removeObject(first, fromPropertyWithKey: "child")
    XCTAssertNil(record.storedValueForKey("child"))
  }

  func testBothSidesHelpersForwardToConformerImplementations() {
    let recorder = RelationshipMutationRecorder()
    let target   = RelationshipMutationRecorder()
    let subject  : RelationshipManipulation = recorder

    subject.addObject(target, toBothSidesOfRelationshipWithKey: "children")
    XCTAssertTrue(recorder.addedObject === target)
    XCTAssertEqual(recorder.addedKey, "children")

    subject.removeObject(target, fromBothSidesOfRelationshipWithKey: "children")
    XCTAssertTrue(recorder.removedObject === target)
    XCTAssertEqual(recorder.removedKey, "children")
  }

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

private final class RelationshipMutationRecorder: RelationshipManipulation {

  var addedObject   : AnyObject?
  var removedObject : AnyObject?
  var addedKey      : String?
  var removedKey    : String?

  func valueForKey(_ key: String) -> Any? { return nil }

  func takeValue(_ value: Any?, forKey key: String) throws {
    XCTFail("Relationship helpers must call the conformer's mutation methods")
  }

  func addObject(_ object: AnyObject, toPropertyWithKey key: String) {
    addedObject = object
    addedKey    = key
  }

  func removeObject(_ object: AnyObject, fromPropertyWithKey key: String) {
    removedObject = object
    removedKey    = key
  }
}

private class DefaultRelationshipObject: RelationshipManipulation {

  enum WriteError: Error {

    case rejected
  }

  var values        = [ String : Any ]()
  var writeAttempts = 0
  var rejectWrites  = false

  func valueForKey(_ key: String) -> Any? { return values[key] }

  func takeValue(_ value: Any?, forKey key: String) throws {
    writeAttempts += 1
    if rejectWrites { throw WriteError.rejected }
    values[key] = value
  }
}

private final class StaticEntityRelationshipObject: DefaultRelationshipObject,
                                                     EntityType
{
  static let entity: Entity = makeDefaultRelationshipEntity()
}

private final class InstanceEntityRelationshipObject: DefaultRelationshipObject,
                                                       ActiveRecordType,
                                                       EntityType
{
  static let entity: Entity = makeDefaultRelationshipEntity(childIsToMany: true)
  static var database: Database? { return nil }

  var entity   : Entity
  var database : Database
  var isNew    = true
  var snapshot : Snapshot?

  override init() {
    let entity    = makeDefaultRelationshipEntity()
    let adaptor   = FakeAdaptor(model: Model(entities: [ entity ]))
    self.entity   = entity
    self.database = Database(adaptor: adaptor)
    super.init()
  }

  func bind(to database: Database, entity: Entity?) {
    self.database = database
    if let entity { self.entity = entity }
  }

  func takeStoredValue(_ value: Any?, forKey key: String) {
    values[key] = value
  }
  func save() throws {}
  func delete() throws {}
}

private func makeDefaultRelationshipEntity(childIsToMany: Bool = false)
             -> ModelEntity
{
  let entity = ModelEntity(name: "Parent")
  let target = ModelEntity(name: "Child")
  entity.relationships = [
    ModelRelationship(name: "child", isToMany: childIsToMany, source: entity,
                      destination: target),
    ModelRelationship(name: "children", isToMany: true, source: entity,
                      destination: target)
  ]
  return entity
}

private final class RelationshipFailureLogger: ZeeQLLogger {

  var errors = [ Error ]()

  func primaryLog(_ level: ZeeQLLoggerLogLevel, _ message: () -> String,
                  _ values: [ Any? ])
  {
    for value in values {
      if let error = value as? Error { errors.append(error) }
    }
  }
}
