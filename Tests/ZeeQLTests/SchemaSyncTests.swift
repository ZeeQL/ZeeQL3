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
  
  let model   = ActiveRecordContactsDBModel.model
  let adaptor = FakeAdaptor(model: ActiveRecordContactsDBModel.model)
  
  let verbose = true

  func testForeignKeyResolvesDestinationColumns() throws {
    let source = modelEntity(table: "child", attributes: [
      modelAttribute("parentId", column: "owner_id", type: "INTEGER",
                     allowsNull: true)
    ], primaryKey: [])
    let destination = modelEntity(table: "parent", attributes: [
      modelAttribute("id", column: "object_id", type: "INTEGER",
                     allowsNull: false)
    ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: source,
                                         destination: destination)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]

    let key = try XCTUnwrap(relationship.foreignKey)
    XCTAssertEqual(key.destinationTableName, "parent")
    XCTAssertEqual(key.sortedJoinColumns.map { $0.0 }, [ "owner_id" ])
    XCTAssertEqual(key.sortedJoinColumns.map { $0.1 }, [ "object_id" ])
  }

  func testCompositeForeignKeyIdentityIncludesRules() throws {
    let source = modelEntity(table: "child", attributes: [
      modelAttribute("parentId", type: "INTEGER", allowsNull: true),
      modelAttribute("language", type: "TEXT", allowsNull: true)
    ], primaryKey: [])
    let destination = modelEntity(table: "parent", attributes: [
      modelAttribute("id", type: "INTEGER", allowsNull: false),
      modelAttribute("locale", type: "TEXT", allowsNull: false)
    ], primaryKey: [ "id", "locale" ])
    let first = ModelRelationship(name: "first", source: source,
                                  destination: destination)
    first.joins = [ Join(source: "parentId", destination: "id"),
                    Join(source: "language", destination: "locale") ]
    let second = ModelRelationship(relationship: first)
    second.name = "second"
    second.joins.reverse()
    source.relationships = [ first, second ]

    let key = try XCTUnwrap(first.foreignKey)
    let sameKey = try XCTUnwrap(second.foreignKey)
    XCTAssertEqual(key, sameKey)
    XCTAssertEqual(Set([ key, sameKey ]).count, 1)
    XCTAssertEqual([ source ].groupRelationships.count, 1)

    second.updateRule = .cascade
    let updateKey = try XCTUnwrap(second.foreignKey)
    XCTAssertNotEqual(key, updateKey)
    XCTAssertEqual([ source ].groupRelationships.count, 2)
    second.deleteRule = .nullify
    XCTAssertNotEqual(updateKey, try XCTUnwrap(second.foreignKey))

    second.updateRule = nil
    second.deleteRule = nil
    second.joins = [ Join(source: "parentId", destination: "locale"),
                     Join(source: "language", destination: "id") ]
    XCTAssertNotEqual(key, try XCTUnwrap(second.foreignKey))
  }

  func testForeignKeyRejectsEmptyAndUnresolvedJoins() {
    let source = modelEntity(table: "child", attributes: [
      modelAttribute("parentId", type: "INTEGER", allowsNull: true)
    ], primaryKey: [])
    let destination = modelEntity(table: "parent", attributes: [
      modelAttribute("id", type: "INTEGER", allowsNull: false)
    ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: source,
                                         destination: destination)
    XCTAssertNil(relationship.foreignKey)
    relationship.joins = [ Join(source: "parentId", destination: "id"),
                           Join(source: "missing", destination: "id") ]
    XCTAssertNil(relationship.foreignKey)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    relationship.isToMany = true
    XCTAssertNil(relationship.foreignKey)
  }

  func testSQLiteConstraintRuleParsing() {
    let rules: [ ( String, ConstraintRule ) ] = [
      ( "NO ACTION", .noAction ), ( "RESTRICT", .deny ),
      ( "CASCADE", .cascade ), ( "SET NULL", .nullify ),
      ( "SET DEFAULT", .applyDefault )
    ]
    for ( sql, rule ) in rules {
      XCTAssertEqual(ConstraintRule(sqliteRule: sql), rule)
      XCTAssertEqual(ConstraintRule(sqliteRule: sql.lowercased()), rule)
    }
    XCTAssertNil(ConstraintRule(sqliteRule: ""))
    XCTAssertNil(ConstraintRule(sqliteRule: "UNKNOWN"))
  }

  func testSQLiteReflectsAndCopiesForeignKeyActions() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("CREATE TABLE parent(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL(
      "CREATE TABLE child(parent_id INTEGER REFERENCES parent(id) " +
      "ON UPDATE CASCADE ON DELETE SET NULL)")
    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    let entity = try XCTUnwrap(channel.describeEntityWithTableName("child"))
    let relationship = try XCTUnwrap(entity.relationships.first)

    XCTAssertEqual(relationship.updateRule, .cascade)
    XCTAssertEqual(relationship.deleteRule, .nullify)
    let copy = ModelRelationship(relationship: relationship)
    XCTAssertEqual(copy.updateRule, .cascade)
    XCTAssertEqual(copy.deleteRule, .nullify)
  }

  func testCompositePrimaryKeyCreation() throws {
    let entity = modelEntity(table: "translation", attributes: [
      modelAttribute("id", type: "INTEGER", allowsNull: false),
      modelAttribute("language", type: "TEXT", allowsNull: false)
    ], primaryKey: [ "id", "language" ])
    let adaptor = SQLite3Adaptor(":memory:")
    let factory = SQLite3SchemaSynchronizationFactory(adaptor: adaptor)
    let options = SchemaGenerationOptions()
    options.dropTables = false
    let statements =
      factory.schemaCreationStatementsForEntities([ entity ], options: options)
    let statement = try XCTUnwrap(statements.first)
    XCTAssertTrue(statement.statement.contains(
      "PRIMARY KEY ( \"id\", \"language\" )"))

    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    _ = try channel.evaluateUpdateExpression(statement)
    let reflected = try XCTUnwrap(
      channel.describeEntityWithTableName("translation"))
    XCTAssertEqual(reflected.primaryKeyAttributeNames, [ "id", "language" ])
  }

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

  func testCreateStatementOrderingForDependencyChain() {
    let grandparent = modelEntity(
      table: "grandparent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("grandparentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [ "id" ])
    let toGrandparent = ModelRelationship(
      name: "grandparent", source: parent, destination: grandparent)
    toGrandparent.joins = [
      Join(source: "grandparentId", destination: "id")
    ]
    parent.relationships = [ toGrandparent ]
    let toParent = ModelRelationship(name: "parent", source: child,
                                     destination: parent)
    toParent.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ toParent ]
    let options = SchemaGenerationOptions()
    options.dropTables = false

    let statements = adaptor.synchronizationFactory
      .schemaCreationStatementsForEntities(
        [ child, grandparent, parent ], options: options)
    let prefixes = statements.prefix(3).map {
      $0.statement.split(separator: " ").prefix(3).joined(separator: " ")
    }
    XCTAssertEqual(prefixes, [
      "CREATE TABLE \"grandparent\"", "CREATE TABLE \"parent\"",
      "CREATE TABLE \"child\""
    ])
  }

  func testNonDirectAdaptorForcesEmbeddedConstraints() throws {
    let options = SchemaGenerationOptions()
    options.dropTables = false
    options.embedConstraintsInTable = false
    let factory = SQLite3SchemaSynchronizationFactory(adaptor: adaptor)
    let address = try XCTUnwrap(model[entity: "Address"])
    let person  = try XCTUnwrap(model[entity: "Person"])
    let statements = factory.schemaCreationStatementsForEntities(
      [ address, person ], options: options)

    XCTAssertEqual(statements.count, 2)
    XCTAssertTrue(statements[1].statement.contains("FOREIGN KEY"))
    XCTAssertFalse(statements.contains {
      $0.statement.hasPrefix("ALTER TABLE")
    })
  }

  func testCyclicCreationOrderIsStable() {
    let first = modelEntity(
      table: "first",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("secondId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [ "id" ])
    let second = modelEntity(
      table: "second",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("firstId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [ "id" ])
    let toSecond = ModelRelationship(name: "second", source: first,
                                     destination: second)
    toSecond.constraintName = ""
    toSecond.joins = [ Join(source: "secondId", destination: "id") ]
    first.relationships = [ toSecond ]
    let toFirst = ModelRelationship(name: "first", source: second,
                                    destination: first)
    toFirst.joins = [ Join(source: "firstId", destination: "id") ]
    second.relationships = [ toFirst ]
    let options = SchemaGenerationOptions()
    options.dropTables = false
    let factory = SchemaSynchronizationFactory(adaptor: adaptor)

    let forward = factory.schemaCreationStatementsForEntities(
      [ first, second ], options: options).map { $0.statement }
    let reverse = factory.schemaCreationStatementsForEntities(
      [ second, first ], options: options).map { $0.statement }
    XCTAssertEqual(forward, reverse)
    XCTAssertTrue(forward.first?.hasPrefix("CREATE TABLE \"first\"") == true)
    XCTAssertTrue(forward.last?.contains("ADD CONSTRAINT \"second\"") == true)
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
    let newModel = Model(model: ActiveRecordContactsDBModel.model, deep: true)
    
    
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

  private func modelAttribute(_ name: String, column: String? = nil,
                              type: String, allowsNull: Bool)
       -> ModelAttribute
  {
    return ModelAttribute(name: name, column: column, externalType: type,
                          allowsNull: allowsNull)
  }

  private func modelEntity(table: String,
                           attributes: [ ModelAttribute ],
                           primaryKey: [ String ]) -> ModelEntity
  {
    let entity = ModelEntity(name: table, table: table)
    entity.attributes = attributes
    entity.primaryKeyAttributeNames = primaryKey
    return entity
  }

  static var allTests = [
    ( "testForeignKeyResolvesDestinationColumns",
      testForeignKeyResolvesDestinationColumns ),
    ( "testCompositeForeignKeyIdentityIncludesRules",
      testCompositeForeignKeyIdentityIncludesRules ),
    ( "testForeignKeyRejectsEmptyAndUnresolvedJoins",
      testForeignKeyRejectsEmptyAndUnresolvedJoins ),
    ( "testSQLiteConstraintRuleParsing", testSQLiteConstraintRuleParsing ),
    ( "testSQLiteReflectsAndCopiesForeignKeyActions",
      testSQLiteReflectsAndCopiesForeignKeyActions ),
    ( "testCompositePrimaryKeyCreation",
      testCompositePrimaryKeyCreation ),
    ( "testDropAddressStatement",
      testDropAddressStatement ),
    ( "testCreateAddressStatements",
      testCreateAddressStatements ),
    ( "testCreateStatementOrdering",
      testCreateStatementOrdering ),
    ( "testCreateStatementOrderingForDependencyChain",
      testCreateStatementOrderingForDependencyChain ),
    ( "testNonDirectAdaptorForcesEmbeddedConstraints",
      testNonDirectAdaptorForcesEmbeddedConstraints ),
    ( "testCyclicCreationOrderIsStable",
      testCyclicCreationOrderIsStable ),
    ( "testEmbeddedConstraint",
      testEmbeddedConstraint ),
    ( "testLateConstraint",
      testLateConstraint ),
    ( "testSimpleModelSync",
      testSimpleModelSync )
  ]
}
