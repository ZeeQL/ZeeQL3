//
//  AdaptorActiveRecordTestCase.swift
//  ZeeQL3
//
//  Created by Helge Hess on 18/05/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import ZeeQL

class AdapterActiveRecordTests: XCTestCase {
  // Is there a better way to share test cases?
  
  var adaptor : Adaptor! {
    XCTAssertNotNil(nil, "override in subclass")
    return nil
  }
  
  let verbose = true
  let model   = ActiveRecordContactsDBModel.model
  
  func testSnapshotting() throws {
    let db = Database(adaptor: adaptor)
    
    let entity : Entity! = model[entity: "Person"]
    XCTAssert(entity != nil, "did not find person entity ...")
    guard entity != nil else { return } // tests continue to run
    
    let ds = ActiveDataSource<ActiveRecord>(database: db, entity: entity)
    
    let dagobert = try ds.findBy(matchingAll: [ "firstname": "Dagobert" ])
    XCTAssert(dagobert != nil)
    
    XCTAssertFalse(dagobert!.isNew,      "fetched object marked as new!")
    XCTAssertNotNil(dagobert!.snapshot,  "missing snapshot")
    XCTAssertFalse(dagobert!.hasChanges, "marked as having changes")
  }
  
  func testSimpleChange() throws {
    let db    = Database(adaptor: adaptor)
    
    let entity : Entity! = model[entity: "Person"]
    XCTAssert(entity != nil, "did not find person entity ...")
    guard entity != nil else { return } // tests continue to run
    
    let ds = ActiveDataSource<ActiveRecordContactsDBModel.Person>(database: db)
    
    let dagobert = try ds.findBy(matchingAll: [ "firstname": "Dagobert" ])
    XCTAssert(dagobert != nil)
    
    XCTAssertFalse(dagobert!.isNew,      "fetched object marked as new!")
    XCTAssertNotNil(dagobert!.snapshot,  "missing snapshot")
    XCTAssertFalse(dagobert!.hasChanges, "marked as having changes")

    dagobert!["firstname"] = "Bobby"
    XCTAssertTrue(dagobert!.hasChanges, "marked as not having changes")
    let changes = dagobert!.changesFromSnapshot(dagobert!.snapshot!)
    XCTAssertEqual(changes.count, 1)
    XCTAssert(changes["firstname"] != nil)
    XCTAssert((changes["firstname"] as EquatableType).isEqual(to: "Bobby"))
  }
  
  func testInsertAndDelete() throws {
    let db    = Database(adaptor: adaptor)
    let ds    = db.datasource(ActiveRecordContactsDBModel.Person.self)
    
    // clear
    try adaptor.performSQL("DELETE FROM person WHERE firstname = 'Ronald'")
    
    
    // create object
    let person = ds.createObject() // this attaches to the DB/entity
    person["firstname"] = "Ronald"
    person["lastname"]  = "McDonald"
    XCTAssertTrue(person.isNew, "new object not marked as new!")
    
    if verbose {print("before save: \(person)") }
    do {
      try person.save()
    }
    catch {
      XCTAssert(false, "save failed: \(error)")
    }
    if verbose { print("after save: \(person)") }
    
    XCTAssertFalse(person.isNew,      "object still marked as new after save!")
    XCTAssertNotNil(person.snapshot,  "missing snapshot after save")
    XCTAssertFalse(person.hasChanges, "marked as having changes after save")
    
    // TODO: check for primary key ...
    XCTAssertNotNil(person["id"],     "got no primary key!")
    
    
    // refetch object
    
    let refetch = try ds.findBy(matchingAll: [ "firstname": "Ronald" ])
    XCTAssert(refetch != nil, "did not find new Ronald")
    if verbose { print("Ronald: \(refetch as Optional)") }
    guard refetch != nil else { return } // keep tests running
    
    XCTAssertFalse(refetch!.isNew,      "fetched object marked as new!")
    XCTAssertNotNil(refetch!.snapshot,  "missing snapshot")
    XCTAssertFalse(refetch!.hasChanges, "marked as having changes")
    
    XCTAssert(refetch?["firstname"] != nil)
    XCTAssert(refetch?["lastname"]  != nil)
    XCTAssert((refetch!["firstname"] as EquatableType).isEqual(to: "Ronald"))
    XCTAssert((refetch!["lastname"]  as EquatableType).isEqual(to: "McDonald"))
    
    
    // delete object
    do {
      // try person.delete() // only works when the pkey is assigned ..
      try refetch?.delete()
    }
    catch {
      XCTAssert(false, "delete failed: \(error)")
    }
  }

  static var sharedTests = [
    ( "testSnapshotting",    testSnapshotting    ),
    ( "testSimpleChange",    testSimpleChange    ),
    ( "testInsertAndDelete", testInsertAndDelete ),
  ]
}
