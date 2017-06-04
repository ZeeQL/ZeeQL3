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
    
    XCTAssertEqual(address.attributes.count, 4)
    XCTAssertEqual(person.attributes.count,  2)
    
    print("Model: \(model)")
  }
}
