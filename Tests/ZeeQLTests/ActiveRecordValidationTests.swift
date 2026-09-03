//
//  ActiveRecordValidationTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

class ActiveRecordValidationTests: XCTestCase {

  func testReadOnlyEntityRejectsInsert() {
    let ( record, adaptor ) = makeRecord(entityIsReadOnly: true, isNew: true)

    assertReadOnly(when: { try record.save() }, record: record)
    XCTAssertTrue(adaptor.sqlCalls.isEmpty)
  }

  func testSnapshotlessRecordRejectsUpdate() {
    let ( record, adaptor ) = makeRecord(entityIsReadOnly: false, isNew: false)

    assertReadOnly(when: { try record.save() }, record: record)
    XCTAssertTrue(adaptor.sqlCalls.isEmpty)
  }

  func testSnapshotlessRecordRejectsDelete() {
    let ( record, adaptor ) = makeRecord(entityIsReadOnly: false, isNew: false)

    assertReadOnly(when: { try record.delete() }, record: record)
    XCTAssertTrue(adaptor.sqlCalls.isEmpty)
  }

  private func makeRecord(entityIsReadOnly: Bool, isNew: Bool)
    -> ( ActiveRecord, FakeAdaptor )
  {
    let entity = ModelEntity(name: "Item")
    entity.isReadOnly = entityIsReadOnly
    let model = Model(entities: [ entity ])
    let adaptor = FakeAdaptor(model: model)
    let database = Database(adaptor: adaptor)
    let record = ActiveRecord()
    record.bind(to: database, entity: entity)
    if !isNew { record.awakeFromFetch(database) }
    return ( record, adaptor )
  }

  private func assertReadOnly(when operation: () throws -> Void,
                              record: ActiveRecord)
  {
    XCTAssertThrowsError(try operation()) { error in
      guard case DatabaseObjectError.readOnly(let object) = error else {
        return XCTFail("Unexpected validation error: \(error)")
      }
      XCTAssertTrue(object === record)
    }
  }
}
