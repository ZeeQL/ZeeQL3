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
  var _adaptor : Adaptor = {
    var pathToTestDB : String = {
    #if ZEE_BUNDLE_RESOURCES
      let bundle = Bundle(for: type(of: self) as! AnyClass)
      let url    = bundle.url(forResource: "contacts", withExtension: "sqlite3")
      guard let path = url?.path
       else { return "contacts.sqlite3" }
      return path
    #else
      let path = ProcessInfo().environment["SRCROOT"]
              ?? FileManager.default.currentDirectoryPath
      return "\(path)/data/contacts.sqlite3"
    #endif
    }()
    return SQLite3Adaptor(pathToTestDB)
  }()
  
}
