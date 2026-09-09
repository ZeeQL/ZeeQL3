//
//  ActiveRecordInsertTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

class ActiveRecordInsertTests: XCTestCase {

  func testInsertAppliesRefetchedValuesBeforeAwakeAndSnapshot() throws {
    let setup  = try makeSetup()
    let object = setup.source.createObject()
    object["name"] = "Alpha"

    try object.save()

    XCTAssertTrue(eq(object["id"], 1))
    XCTAssertEqual(object["state"] as? String, "pending")
    XCTAssertTrue(eq(object.idAtAwake, 1))
    XCTAssertEqual(object.stateAtAwake, "pending")
    let snapshot = try XCTUnwrap(object.snapshot)
    XCTAssertTrue(eq(snapshot["id"] ?? nil, 1))
    XCTAssertEqual(snapshot["state"] as? String, "pending")
    XCTAssertFalse(object.isNew)
    XCTAssertFalse(object.hasChanges)
  }

  func testInsertAppliesTriggerChangesIncludingNulls() throws {
    let setup = try makeSetup()
    try setup.adaptor.performSQL("""
      CREATE TRIGGER adjust_record AFTER INSERT ON records BEGIN
        UPDATE records SET name = upper(NEW.name), note = NULL
        WHERE id = NEW.id;
      END
      """)
    let object = setup.source.createObject()
    object["name"] = "Alpha"
    object["note"] = "client value"

    try object.save()

    XCTAssertEqual(object["name"] as? String, "ALPHA")
    XCTAssertNil(object["note"])
    let snapshot = try XCTUnwrap(object.snapshot)
    XCTAssertEqual(snapshot["name"] as? String, "ALPHA")
    XCTAssertTrue(snapshot.keys.contains("note"))
    XCTAssertNil(snapshot["note"] ?? nil)
    XCTAssertFalse(object.hasChanges)
  }

  func testBatchResultsStayAssociatedWithOperations() throws {
    let setup   = try makeSetup()
    let first   = setup.source.createObject()
    let second  = setup.source.createObject()
    let channel = DatabaseChannel(database: setup.database)
    let context = ObjectTrackingContext(parent: DatabaseContext(setup.database))
    channel.objectContext = context
    first["name"]  = "Alpha"
    second["name"] = "Beta"
    second["id"]   = 42
    let firstOp  = insertOperation(first)
    let secondOp = insertOperation(second)
    var completionCount = 0
    firstOp.completionBlock = {
      completionCount += 1
      XCTAssertTrue(eq(first["id"], 1))
      XCTAssertEqual(first["state"] as? String, "pending")
    }
    secondOp.completionBlock = {
      completionCount += 1
      XCTAssertTrue(eq(second["id"], 42))
      XCTAssertEqual(second["state"] as? String, "pending")
    }

    try channel.performDatabaseOperations([ firstOp, secondOp ])

    XCTAssertEqual(completionCount, 2)
    XCTAssertEqual(firstOp.adaptorOperations.count, 1)
    XCTAssertEqual(secondOp.adaptorOperations.count, 1)
    XCTAssertEqual(firstOp.adaptorOperations[0].resultRow?["name"] as? String,
                   "Alpha")
    XCTAssertEqual(secondOp.adaptorOperations[0].resultRow?["name"] as? String,
                   "Beta")
    let firstID  = try XCTUnwrap(first.globalID)
    let secondID = try XCTUnwrap(second.globalID)
    XCTAssertTrue(context.objectFor(globalID: firstID) === first)
    XCTAssertTrue(context.objectFor(globalID: secondID) === second)
  }

  func testFailedBatchKeepsObjectsUnchangedAndCanBeRetried() throws {
    let setup  = try makeSetup()
    let first  = setup.source.createObject()
    let second = setup.source.createObject()
    first["name"]  = "Alpha"
    second["name"] = "Alpha" // Violates the UNIQUE constraint.
    let firstOp  = insertOperation(first)
    let secondOp = insertOperation(second)
    let operations = [ firstOp, secondOp ]
    var completionCount = 0
    for operation in operations {
      operation.completionBlock = { completionCount += 1 }
    }

    XCTAssertThrowsError(
      try setup.database.performDatabaseOperations(operations))

    XCTAssertEqual(completionCount, 2)
    for object in [ first, second ] {
      XCTAssertTrue(object.isNew)
      XCTAssertNil(object["id"])
      XCTAssertNil(object["state"])
      XCTAssertNil(object.snapshot)
    }
    let counts: [ Int ] =
      try setup.adaptor.select("SELECT COUNT(*) FROM records")
    XCTAssertEqual(counts, [ 0 ])

    second["name"] = "Beta"
    try setup.database.performDatabaseOperations(operations)

    XCTAssertTrue(eq(first["id"], 1))
    XCTAssertTrue(eq(second["id"], 2))
    XCTAssertFalse(first.isNew)
    XCTAssertFalse(second.isNew)
    XCTAssertEqual(firstOp.adaptorOperations.count, 1)
    XCTAssertEqual(secondOp.adaptorOperations.count, 1)
    XCTAssertNil(firstOp.completionBlock)
    XCTAssertNil(secondOp.completionBlock)
  }

  func testReusedOperationDoesNotRetainOldAdaptorResults() throws {
    let setup = try makeSetup()
    let first = setup.source.createObject()
    first["name"] = "Alpha"
    let operation = insertOperation(first)
    try setup.database.performDatabaseOperations([ operation ])
    XCTAssertNotNil(operation.adaptorOperations[0].resultRow)

    operation.databaseOperator = .update
    operation.dbSnapshot = first.snapshot
    let second = setup.source.createObject()
    second["name"] = "Beta"
    let secondOp = insertOperation(second)

    try setup.database.performDatabaseOperations([ operation, secondOp ])

    XCTAssertTrue(operation.adaptorOperations.isEmpty)
    XCTAssertTrue(eq(first["id"], 1))
    XCTAssertTrue(eq(second["id"], 2))
    XCTAssertEqual(secondOp.adaptorOperations.count, 1)
    XCTAssertEqual(secondOp.adaptorOperations[0].resultRow?["name"] as? String,
                   "Beta")
  }

  func testInsertOperationDoesNotRetainCapturedAdaptorOperation() throws {
    weak var observedEntity: ModelEntity?
    do {
      let entity = ModelEntity(name: "Record")
      observedEntity = entity
      let operation = DatabaseOperation(ActiveRecord(), entity)
      operation.databaseOperator = .insert
      _ = try operation.primaryAdaptorOperation()
    }
    XCTAssertNil(observedEntity)
  }

  // MARK: - Helpers

  private func insertOperation(_ object: ActiveRecord) -> DatabaseOperation {
    let operation = DatabaseOperation(object)
    operation.databaseOperator = .insert
    return operation
  }

  private func makeSetup() throws -> Setup {
    let pool    = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", autocreate: true, pool: pool)
    try adaptor.performSQL("""
      CREATE TABLE records(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        state TEXT DEFAULT 'pending',
        note TEXT
      )
      """)

    let entity = ModelEntity(name: "Record", table: "records")
    let id     = ModelAttribute(name: "id", externalType: "INTEGER")
    id.isAutoIncrement = true
    entity.attributes = [
      id,
      ModelAttribute(name: "name", externalType: "TEXT"),
      ModelAttribute(name: "state", externalType: "TEXT"),
      ModelAttribute(name: "note", externalType: "TEXT")
    ]
    entity.primaryKeyAttributeNames = [ "id" ]
    adaptor.model = Model(entities: [ entity ])
    let database = Database(adaptor: adaptor)
    let source   = ActiveDataSource<InsertedRecord>(database: database,
                                                   entity: entity)
    return Setup(adaptor: adaptor, database: database, source: source)
  }

  private struct Setup {

    let adaptor  : SQLite3Adaptor
    let database : Database
    let source   : ActiveDataSource<InsertedRecord>
  }

  private final class InsertedRecord: ActiveRecord {

    var idAtAwake    : Any?
    var stateAtAwake : String?

    override func awakeFromFetch(_ database: Database) {
      super.awakeFromFetch(database)
      idAtAwake    = self["id"]
      stateAtAwake = self["state"] as? String
    }
  }
}
