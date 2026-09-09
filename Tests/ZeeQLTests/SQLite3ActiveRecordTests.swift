//
//  SQLite3ActiveRecordTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 15/05/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import ZeeQL

class SQLite3ActiveRecordTests: AdapterActiveRecordTests {
  
  override var adaptor : Adaptor! { return _adaptor }
  private var _adaptor    : SQLite3Adaptor?
  private var databaseURL : URL?

  override func setUpWithError() throws {
    let url = try temporaryTestDatabase(named: "contacts.sqlite3")
    databaseURL = url
    _adaptor    = SQLite3Adaptor(url.path)
  }

  override func tearDownWithError() throws {
    _adaptor = nil
    if let databaseURL {
      try FileManager.default.removeItem(at: databaseURL)
    }
    databaseURL = nil
  }

  func testSnapshotting() throws { try runSnapshotting() }
  func testSimpleChange() throws { try runSimpleChange() }
  func testInsertAndDelete() throws { try runInsertAndDelete() }
  
  func testFetchRawContactsModel() throws { // doesn't belong here, but well
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    let model = try SQLite3ModelFetch(channel: channel).fetchModel()
    
    XCTAssertEqual(model.entities.count, 2)
    XCTAssertNotNil(model[entity: "address"])
    XCTAssertNotNil(model[entity: "person"])
    guard let address = model[entity: "address"],
          let person  = model[entity: "person"]
     else { return }
    
    if verbose {
      print("Model:     \(model)")
      print("  Address: \(address.attributes)")
      print("  Address: \(address.relationships)")
      print("  Person:  \(person.attributes)")
      print("  Person:  \(person.relationships)")
    }
    
    XCTAssertEqual(address.attributes.count,    6)
    XCTAssertEqual(person.attributes.count,     3)
    XCTAssertEqual(address.relationships.count, 1)

    XCTAssertEqual(address.primaryKeyAttributeNames?.count, 1)
    XCTAssertEqual(person .primaryKeyAttributeNames?.count,  1)
    let addressId = address.primaryKeyAttributeNames?.first ?? "-"
    let personId  = person .primaryKeyAttributeNames?.first ?? "-"
    XCTAssertNotNil(person [attribute: personId])
    XCTAssertNotNil(address[attribute: addressId])
    
    // toMany is created in FancyModelMaker, not during loading!
    XCTAssertEqual(person.relationships.count,  0)
    
    XCTAssertEqual(address.primaryKeyAttributeNames?.count, 1)
    XCTAssertEqual(person.primaryKeyAttributeNames?.count,  1)

    
    if let pkey = person[attribute: personId] {
      XCTAssertNotNil(pkey.allowsNull)
      XCTAssertEqual(pkey.allowsNull ?? true, false)
    }
    if let street = address[attribute: "street"] {
      XCTAssertNotNil(street.allowsNull)
      XCTAssertEqual(street.allowsNull ?? false, true)
    }
    
    
    if let toOne = address.relationships.first {
      XCTAssertEqual(toOne.joins.count, 1)
      XCTAssert(toOne.destinationEntity === person)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.destinationName, "person_id")
        XCTAssertEqual(join.sourceName,      "person_id")
      }
    }
  }

}
