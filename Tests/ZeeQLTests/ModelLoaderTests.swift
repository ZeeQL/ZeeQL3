//
//  ModelLoaderTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 04/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
import struct Foundation.URL
import class  Foundation.Bundle
@testable import ZeeQL

class ModelLoaderTests: XCTestCase {

  let urlToModel : URL = {
    #if ZEE_BUNDLE_RESOURCES
      let bundle = Bundle(for: type(of: self) as! AnyClass)
      let url    = bundle.url(forResource:   "Contacts",
                              withExtension: "xcdatamodel")
      return url?.path ?? URL(fileSystemPath: "Contacts.xcdatamodel")
    #else
      let path = ProcessInfo().environment["SRCROOT"]
              ?? FileManager.default.currentDirectoryPath
      return URL(fileURLWithPath: "\(path)/data/Contacts.xcdatamodel")
    #endif
  }()
  
  let verbose = true
  
  func testModelPath() {
    let url = urlToModel
    XCTAssert(!url.path.isEmpty)
    XCTAssert(!url.path.hasPrefix("/tmp"))
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
        XCTAssertEqual(kvq.operation, .Like)
      }
    }
  }
}