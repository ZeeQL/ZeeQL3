//
//  SchemaSyncTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class SchemaSyncTests: XCTestCase {
  
  let model   = ContactsDBModel.model
  let adaptor = FakeAdaptor(model: ContactsDBModel.model)
  
  let verbose = true
  
  func testDropAddressStatement() {
    let options = SchemaGenerationOptions()
    options.createTables = false
    options.dropTables   = true
    
    let sf = adaptor.synchronizationFactory
    let statements =
      sf.schemaCreationStatementsForEntities([ model[entity: "Address"]! ],
                                             options: options)
    if verbose { print("statements: \(statements)") }
    
    XCTAssertEqual(statements.count, 1)
    XCTAssertEqual(statements.first?.statement, "DROP TABLE \"address\"")
  }

  func testCreateAddressStatements() {
    let options = SchemaGenerationOptions()
    options.createTables = true
    options.dropTables   = false
    
    let sf = adaptor.synchronizationFactory
    let statements =
      sf.schemaCreationStatementsForEntities([ model[entity: "Address"]! ],
                                             options: options)
    if verbose { print("statements: \(statements)") }
    
    XCTAssertEqual(statements.count, 1)
    if let stmt = statements.first {
      XCTAssertEqual(stmt.statement,
                     "CREATE TABLE \"address\" ( " +
        "\"address_id\" INT NOT NULL,\n\"street\" VARCHAR NULL,\n" +
        "\"city\" VARCHAR NULL,\n\"state\" VARCHAR NULL,\n" +
        "\"country\" VARCHAR NULL,\n" +
        "\"person_id\" INT NOT NULL )")
    }
  }
}

