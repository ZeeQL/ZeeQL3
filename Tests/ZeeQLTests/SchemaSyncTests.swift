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
    let options    = SchemaGenerationOptions()
    options.createTables = true
    options.dropTables   = false
    options.embedConstraintsInTable = true
    
    let sf         = adaptor.synchronizationFactory
    let entities   = [ model[entity: "Address"]! ]
    let statements = sf.schemaCreationStatementsForEntities(entities,
                                                            options: options)
    if verbose { print("statements: \(statements)") }
    
    XCTAssertEqual(statements.count, 2)
    if let stmt = statements.first {
      XCTAssertEqual(stmt.statement,
                     "CREATE TABLE \"address\" ( " +
        "\"address_id\" INT NOT NULL PRIMARY KEY,\n\"street\" VARCHAR NULL,\n" +
        "\"city\" VARCHAR NULL,\n\"state\" VARCHAR NULL,\n" +
        "\"country\" VARCHAR NULL,\n" +
        "\"person_id\" INT NOT NULL )")
    }
  }
  
  func testCreateStatementOrdering() {
    let options    = SchemaGenerationOptions()
    options.createTables = true
    options.dropTables   = false
    options.embedConstraintsInTable = true
    
    let sf         = SQLite3SchemaSynchronizationFactory(adaptor: adaptor)
    let entities   = [ model[entity: "Address"]!, model[entity: "Person"]! ]
    let statements = sf.schemaCreationStatementsForEntities(entities,
                                                            options: options)
    if verbose { print("statements: \(statements)") }
    
    XCTAssertEqual(statements.count, 2)
    
    if statements.count > 1 {
      let a = statements[0].statement
      let b = statements[1].statement
      XCTAssertTrue(a.hasPrefix("CREATE TABLE \"person\""))
      XCTAssertTrue(b.hasPrefix("CREATE TABLE \"address\""))
    }
  }

  func testEmbeddedConstraint() {
    let options    = SchemaGenerationOptions()
    options.createTables = true
    options.dropTables   = false
    options.embedConstraintsInTable = true
    
    let sf         = SchemaSynchronizationFactory(adaptor: adaptor)
    let entities   = [ model[entity: "Address"]!, model[entity: "Person"]! ]
    let statements = sf.schemaCreationStatementsForEntities(entities,
                                                            options: options)
    if verbose { print("statements: \(statements)") }
    
    XCTAssertEqual(statements.count, 2)
    
    if statements.count > 1 {
      let a = statements[0].statement
      let b = statements[1].statement
      XCTAssertTrue(a.hasPrefix("CREATE TABLE \"person\""))
      XCTAssertTrue(b.hasPrefix("CREATE TABLE \"address\""))
      
      XCTAssertTrue(b.contains(
        "FOREIGN KEY ( \"person_id\" ) " +
        "REFERENCES \"person\" ( \"person_id\" ) )"))
    }
  }
  
  func testLateConstraint() {
    let options    = SchemaGenerationOptions()
    options.createTables = true
    options.dropTables   = false
    options.embedConstraintsInTable = false
    
    let sf         = SchemaSynchronizationFactory(adaptor: adaptor)
    let entities   = [ model[entity: "Address"]!, model[entity: "Person"]! ]
    let statements = sf.schemaCreationStatementsForEntities(entities,
                                                            options: options)
    if verbose { print("statements: \(statements)") }
    
    XCTAssertEqual(statements.count, 3)
    
    if statements.count > 1 {
      let a = statements[0].statement
      let b = statements[1].statement
      let constraint = statements[2].statement
      XCTAssertTrue(a.hasPrefix("CREATE TABLE \"address\""))
      XCTAssertTrue(b.hasPrefix("CREATE TABLE \"person\""))
      
      if verbose { print("C: \(constraint)") }
      XCTAssertTrue(!a.contains(
        "FOREIGN KEY ( \"person_id\" ) " +
        "REFERENCES \"person\" ( \"person_id\" )"))
      XCTAssertTrue(constraint.contains(
        "FOREIGN KEY ( \"person_id\" ) " +
        "REFERENCES \"person\" ( \"person_id\" )"))
    }
  }
  
  func testSimpleModelSync() {
    // emulate old model
    let dbModel  = RawContactsDBModel.model
    if verbose { print("db: \(dbModel)") }
    
    // create newModel
    let newModel = Model(model: ContactsDBModel.model, deep: true)
    
    
    // changes
    
    if let address = newModel[entity: "Address"] as? ModelEntity {
      // add an attribute to 'Address'
      address.attributes.append(
        ModelAttribute(name: "zip", allowsNull: true,
                       valueType: Optional<String>.self)
      )
      
      // make city non-optional
      if let city = address[attribute: "city"] as? ModelAttribute {
        city.valueType  = String.self
        city.allowsNull = false
      }
      
      // change type of state to Int, just to test
      if let state = address[attribute: "state"] as? ModelAttribute {
        state.valueType = Optional<Int>.self
      }
    }
    
    // add a new entity 'Telephone'
    let phone : ModelEntity = {
      let entity = ModelEntity(name: "Telephone")
      entity.attributes = [
        ModelAttribute(name: "id",     allowsNull: false, valueType: Int.self),
        ModelAttribute(name: "number", allowsNull: true,
                       valueType: Optional<String>.self),
        ModelAttribute(name: "personId", allowsNull: true,
                       valueType: Optional<Int>.self),
      ]
      let toPerson = ModelRelationship(name: "person", isToMany: false,
                                       source: entity,
                                       destination: newModel[entity: "Person"])
      toPerson.joins = [ Join(source: "personId", destination: "id") ]
      entity.relationships = [ toPerson ]
      
      entity.primaryKeyAttributeNames = [ "id" ]
      return entity
    }()
    newModel.entities.append(phone)
    
    // SQLlize model to make sure it has external type info
    let sqlizer = ModelSQLizer()
    let newSQLModel = sqlizer.sqlizeModel(newModel)
    if verbose { print("new: \(newSQLModel)") }

    
    // sync
    
    let sf = adaptor.synchronizationFactory
    
    sf.synchronizeModels(old: dbModel, new: newModel)
    // TODO: sync!!!
  }

  static var allTests = [
    ( "testDropAddressStatement",    testDropAddressStatement ),
    ( "testCreateAddressStatements", testCreateAddressStatements ),
    ( "testCreateStatementOrdering", testCreateStatementOrdering ),
    ( "testEmbeddedConstraint",      testEmbeddedConstraint ),
    ( "testLateConstraint",          testLateConstraint ),
    ( "testSimpleModelSync",         testSimpleModelSync ),
  ]
}
