//
//  ModelLoaderTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 04/06/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

import XCTest
import Foundation
@testable import ZeeQL

class ModelLoaderTests: XCTestCase {
  
  var urlToModel    : URL = URL(fileURLWithPath: "/tmp")
  var urlToMOMModel : URL = URL(fileURLWithPath: "/tmp")
  let verbose       = true
  
  override func setUp() {
    super.setUp()
    #if ZEE_BUNDLE_RESOURCES
      let bundle = Bundle(for: type(of: self)) // ModelLoaderTests.self)
      var url    = bundle.url(forResource:   "Contacts",
                              withExtension: "xcdatamodel")
      if url == nil {
        url    = bundle.url(forResource:   "Contacts",
                            withExtension: "mom")
      }
      if url == nil {
        print("could not locate xcdatamodel: \(url as Optional) " +
              "in bundle: \(bundle)")
      }
      urlToModel    = url ?? URL(fileURLWithPath: "Contacts.xcdatamodel")
      urlToMOMModel = urlToModel // FIXME
    #else
      let dataPath = lookupTestDataPath()
      urlToModel    = URL(fileURLWithPath: "\(dataPath)/Contacts.xcdatamodel")
      urlToMOMModel = URL(fileURLWithPath: "\(dataPath)/Contacts.mom")
    #endif
  }
  
  func testModelPath() {
    let url = urlToModel
    XCTAssert(!url.path.isEmpty)
    print("URL: \(url)")
  }
  
  func testModelLoad() {
    let url = urlToModel
    let model : Model
    
    do {
      model = try ModelLoader.loadModel(from: url)
    }
    catch {
      XCTAssertNil(error, "error: \(error)")
      return
    }
    
    XCTAssertEqual(model.entities.count, 2)
    XCTAssertNotNil(model[entity: "Address"])
    XCTAssertNotNil(model[entity: "Person"])
    guard let address = model[entity: "Address"],
          let person  = model[entity: "Person"]
     else { return }

    if verbose {
      print("Model:     \(model)")
      print("  Address: \(address.attributes)")
      print("  Address: \(address.relationships)")
      print("  Person:  \(person.attributes)")
      print("  Person:  \(person.relationships)")
    }
    
    XCTAssertEqual(address.attributes.count,    6) // +id +fkey
    XCTAssertEqual(person.attributes.count,     3) // +id
    XCTAssertEqual(address.relationships.count, 1)
    XCTAssertEqual(person.relationships.count,  1)
    XCTAssertEqual(address.primaryKeyAttributeNames?.count, 1)
    XCTAssertEqual(person.primaryKeyAttributeNames?.count,  1)
    
    if let toOne = address.relationships.first {
      XCTAssertEqual(toOne.joins.count, 1)
      XCTAssert(toOne.destinationEntity === person)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.destinationName, "id")
        XCTAssertEqual(join.sourceName,      "personId")
      }
    }
    
    if let toMany = person.relationships.first {
      XCTAssertEqual(toMany.joins.count, 1)
      XCTAssert(toMany.destinationEntity === address)
      if let join = toMany.joins.first {
        XCTAssertEqual(join.sourceName,      "id")
        XCTAssertEqual(join.destinationName, "personId")
      }
    }
    
    XCTAssert(person[fetchSpecification: "fetchTheDucks"] != nil)
    if let fs = person[fetchSpecification: "fetchTheDucks"] {
      if verbose {
        print("fspec: \(fs)")
      }
      XCTAssertEqual(fs.fetchLimit, 220)
      XCTAssertNotNil(fs.qualifier)
      XCTAssertNotNil(fs.qualifier as? KeyValueQualifier)
      XCTAssertTrue(fs.usesDistinct)
      
      if let kvq = fs.qualifier as? KeyValueQualifier {
        XCTAssertEqual(kvq.key, "lastName")
        XCTAssertEqual(kvq.value as? String, "Duck*")
        XCTAssertEqual(kvq.operation, .like)
      }
    }
  }
  
  func testCompiledModelLoad() {
    let url = urlToMOMModel
    let model : Model
    
    do {
      model = try ModelLoader.loadModel(from: url)
    }
    catch {
      XCTAssertNil(error, "error: \(error)")
      return
    }
    
    XCTAssertEqual(model.entities.count, 2)
    XCTAssertNotNil(model[entity: "Address"])
    XCTAssertNotNil(model[entity: "Person"])
    guard let address = model[entity: "Address"],
          let person  = model[entity: "Person"]
     else { return }

    if verbose {
      print("Model:     \(model)")
      print("  Address: \(address.attributes)")
      print("  Address: \(address.relationships)")
      print("  Person:  \(person.attributes)")
      print("  Person:  \(person.relationships)")
    }
    
    XCTAssertEqual(address.attributes.count,    6) // +id +fkey
    XCTAssertEqual(person.attributes.count,     3) // +id
    XCTAssertEqual(address.relationships.count, 1)
    XCTAssertEqual(person.relationships.count,  1)
    XCTAssertEqual(address.primaryKeyAttributeNames?.count, 1)
    XCTAssertEqual(person.primaryKeyAttributeNames?.count,  1)
    
    if let toOne = address.relationships.first {
      XCTAssertEqual(toOne.joins.count, 1)
      XCTAssert(toOne.destinationEntity === person)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.destinationName, "id")
        XCTAssertEqual(join.sourceName,      "personId")
      }
    }
    
    if let toMany = person.relationships.first {
      XCTAssertEqual(toMany.joins.count, 1)
      XCTAssert(toMany.destinationEntity === address)
      if let join = toMany.joins.first {
        XCTAssertEqual(join.sourceName,      "id")
        XCTAssertEqual(join.destinationName, "personId")
      }
    }
    
    XCTAssert(person[fetchSpecification: "fetchTheDucks"] != nil)
    if let fs = person[fetchSpecification: "fetchTheDucks"] {
      if verbose {
        print("fspec: \(fs)")
      }
      #if false // stuff not implemented yet: :-)
      XCTAssertEqual(fs.fetchLimit, 220)
      XCTAssertNotNil(fs.qualifier)
      XCTAssertNotNil(fs.qualifier as? KeyValueQualifier)
      XCTAssertTrue(fs.usesDistinct)
      #endif
      
      if let kvq = fs.qualifier as? KeyValueQualifier {
        XCTAssertEqual(kvq.key, "lastName")
        XCTAssertEqual(kvq.value as? String, "Duck*")
        XCTAssertEqual(kvq.operation, .like)
      }
    }
  }

  func testModelSQLize() {
    let url = urlToModel
    let originalModel : Model
    
    do {
      originalModel = try ModelLoader.loadModel(from: url)
    }
    catch {
      XCTAssertNil(error, "error: \(error)")
      return
    }
    
    let sqlizer = ModelSQLizer()
    let model   = sqlizer.sqlizeModel(originalModel)
    
    XCTAssertNotNil(model[entity: "Address"])
    XCTAssertNotNil(model[entity: "Person"])
    guard let address = model[entity: "Address"],
          let person  = model[entity: "Person"]
     else { return }

    if verbose {
      print("Model:     \(model)")
      print("  Address: #\(address.attributes.count)")
      for addr in address.attributes {
        print("    \(addr)")
      }
      print("  Address: \(address.relationships)")
      print("  Person:  #\(person.attributes.count)")
      for addr in person.attributes {
        print("    \(addr)")
      }
      print("  Person:  \(person.relationships)")
    }

    XCTAssertEqual(address.externalName, "address")
    XCTAssertEqual(person.externalName,  "person")
    
    XCTAssertNotNil(address[attribute: "id"])
    if let attr = address[attribute: "id"] {
      XCTAssertNotNil(attr.columnName)
      XCTAssertEqual(attr.columnName, "address_id")
    }
    
    XCTAssertNotNil(address[attribute: "personId"])
    if let attr = address[attribute: "personId"] {
      XCTAssertNotNil(attr.columnName)
      XCTAssertEqual(attr.columnName, "person_id")
    }
  }
  
  static var allTests = [
    ( "testModelPath",         testModelPath         ),
    ( "testModelLoad",         testModelLoad         ),
    // Compiled models do not work on Linux:
    // ( "testCompiledModelLoad", testCompiledModelLoad ),
    ( "testModelSQLize",       testModelSQLize       ),
  ]
}
