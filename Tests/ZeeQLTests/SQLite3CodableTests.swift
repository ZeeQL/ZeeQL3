//
//  SQLite3CodableTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 12.02.18.
//  Copyright © 2018 ZeeZide GmbH. All rights reserved.
//

import XCTest
import Foundation
@testable import ZeeQL

class SQLite3CodableTests: XCTestCase {
  #if swift(>=4.0)

  var adaptor : Adaptor! { return _adaptor }
  var _adaptor : Adaptor = {
    var pathToTestDB : String = {
    #if ZEE_BUNDLE_RESOURCES
      let bundle = Bundle(for: type(of: self) as! AnyClass)
      let url    = bundle.url(forResource: "contacts", withExtension: "sqlite3")
      guard let path = url?.path else { return "contacts.sqlite3" }
      return path
    #else
      return "\(lookupTestDataPath())/contacts.sqlite3"
    #endif
    }()
    return SQLite3Adaptor(pathToTestDB)
  }()
  

  func testRawAdaptorQuery() throws {
    #if false // TODO: does not work yet
    guard let entity = PlainCodableContactsDBModel.sqlModel[entity: "Person"]
     else
    {
      XCTAssertNotNil(PlainCodableContactsDBModel.sqlModel[entity: "Person"],
                      "got no Person entity?")
      return
    }
    
    print("Entity:", entity)
    
    let factory = adaptor.expressionFactory
    
    do {
      let channel = try adaptor.openChannel()
      defer { adaptor.releaseChannel(channel) }
      
      let expr =
        factory.selectExpressionForAttributes(entity.attributes, nil, entity)
      
      var records = [ AdaptorRecord ]()
      try channel.evaluateQueryExpression(expr, entity.attributes) { record in
        records.append(record)
      }
      
      print("records:", records)
      
      //XCTAssertEqual(records.count, 1, "there should be one template record")
    }
    catch {
      XCTFail("Unexpected error: \(error)")
    }
    #endif
  }


  // MARK: - Non-ObjC Swift Support
  
  static var allTests = [
    ( "testRawAdaptorQuery", testRawAdaptorQuery )
  ]
  
  #else // Not Swift 4
  
  static var allTests = [(String, (SQLite3CodableTests) -> () -> ())]()
  
  #endif // Not Swift 4
}
