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

  func testPlansDirectSchemaChanges() throws {
    let oldEntity = modelEntity(
      table: "person",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("name", type: "VARCHAR", allowsNull: true),
        modelAttribute("obsolete", type: "TEXT", allowsNull: true)
      ], primaryKey: [ "id" ])
    let newEntity = modelEntity(
      table: "person",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("name", column: "display_name", type: "TEXT",
                       allowsNull: false),
        modelAttribute("age", type: "INTEGER", allowsNull: true)
      ], primaryKey: [ "id" ])
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())
    let statements = try factory.schemaSynchronizationStatements(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ])).map { $0.statement }

    XCTAssertFalse(factory.supportsSchemaSynchronization)
    XCTAssertEqual(statements, [
      "ALTER TABLE \"person\" DROP COLUMN \"obsolete\"",
      "ALTER TABLE \"person\" RENAME COLUMN \"name\" TO \"display_name\"",
      "ALTER TABLE \"person\" ALTER COLUMN \"display_name\" TYPE TEXT",
      "ALTER TABLE \"person\" ALTER COLUMN \"display_name\" SET NOT NULL",
      "ALTER TABLE \"person\" ADD COLUMN \"age\" INTEGER NULL"
    ])
  }

  func testPlansChangesFromCodeEntities() throws {
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())
    let statements = try factory.schemaSynchronizationStatements(
      old: RawContactsDBModel.model,
      new: ActiveRecordContactsDBModel.model).map { $0.statement }

    XCTAssertEqual(statements, [
      "ALTER TABLE \"address\" ALTER COLUMN \"person_id\" SET NOT NULL"
    ])
  }

  func testRejectsPatternModels() throws {
    let oldEntity = modelEntity(
      table: "person",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let pattern = ModelEntity(name: "person", table: "person")
    pattern.attributes = [ ModelAttribute(name: "*") ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ pattern ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsDuplicateTargetColumns() throws {
    let oldEntity = modelEntity(
      table: "person",
      attributes: [
        modelAttribute("first", type: "TEXT", allowsNull: true),
        modelAttribute("second", type: "TEXT", allowsNull: true)
      ], primaryKey: [])
    let newEntity = modelEntity(
      table: "person",
      attributes: [
        modelAttribute("first", column: "value", type: "TEXT",
                       allowsNull: true),
        modelAttribute("second", column: "value", type: "TEXT",
                       allowsNull: true)
      ], primaryKey: [])
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsDuplicateLogicalEntityNames() throws {
    let first = modelEntity(
      table: "parent_a",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    first.name = "Parent"
    let second = modelEntity(
      table: "parent_b",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    second.name = "Parent"
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: second)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ first, second, child ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsDuplicatePrimaryKeyAttributes() throws {
    let entity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id", "id" ])
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ entity ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsForeignKeyWithWrongSource() throws {
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let other = modelEntity(
      table: "other",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: other,
                                         destination: parent)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ parent, child, other ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsUnattachedCodeRelationshipWithoutCrashing() throws {
    let entity = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let toOne =
      ToOneRelationship<ActiveRecordContactsDBModel.Person>(
        from: "parentId", on: "id")
    let toMany =
      ToManyRelationship<ActiveRecordContactsDBModel.Person>(
        from: "parentId", on: "id")
    toOne.name  = "parent"
    toMany.name = "parents"
    entity.relationships = [ toOne, toMany ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ entity ]))) { error in
      guard case SchemaSynchronizationError.invalidModel(let issues) =
              error else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertTrue(issues.contains(
        "foreign key child.parent has an unresolved source in the new model"))
      XCTAssertTrue(issues.contains(
        "foreign key child.parents has an unresolved source in the new model"))
    }
  }

  func testValidatesCodeRelationshipWithCustomSource() throws {
    let parent = modelEntity(table: "parent", attributes: [
      modelAttribute("id", type: "INTEGER", allowsNull: false)
    ], primaryKey: [ "id" ])
    let child = modelEntity(table: "child", attributes: [
      modelAttribute("parentId", type: "INTEGER", allowsNull: true)
    ], primaryKey: [])
    let relationship = ResolvedSourceCodeRelationship(source: child,
                                                       destination: parent)
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())
    let model = Model(entities: [ parent, child ])

    XCTAssertNil(relationship.codeEntity)
    XCTAssertTrue((relationship as CodeRelationshipType).isEntityResolved)
    let statements = try factory.schemaSynchronizationStatements(
      old: Model(entities: []), new: model)
    XCTAssertTrue(statements.contains { $0.statement.contains("FOREIGN KEY") })

    relationship.entity = parent
    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []), new: model)) { error in
      guard case SchemaSynchronizationError.invalidModel(let issues) =
              error else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertTrue(issues.contains(
        "foreign key child.parent has the wrong source in the new model"))
    }
  }

  func testRejectsEmptyRelationshipName() throws {
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "", source: child,
                                         destination: parent)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ parent, child ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsInconsistentForeignKeyDestination() throws {
    let first = modelEntity(
      table: "first",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let second = modelEntity(
      table: "second",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: first)
    relationship.destinationEntity = second
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ first, second, child ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsUnresolvedForeignKeyDestination() throws {
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: child)
    relationship.destinationEntityName = "missing"
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ child ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsForeignKeyWithForeignJoinAttribute() throws {
    let first = modelEntity(
      table: "first",
      attributes: [
        modelAttribute("id", column: "first_id", type: "INTEGER",
                       allowsNull: false)
      ], primaryKey: [ "id" ])
    let second = modelEntity(
      table: "second",
      attributes: [
        modelAttribute("id", column: "second_id", type: "INTEGER",
                       allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let source = try XCTUnwrap(child[attribute: "parentId"])
    let wrongDestination = try XCTUnwrap(first[attribute: "id"])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: second)
    relationship.joins = [
      Join(source: source, destination: wrongDestination)
    ]
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ first, second, child ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsForeignKeyConstraintRename() throws {
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: parent)
    relationship.constraintName = "old_fk"
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let oldModel = Model(entities: [ parent, child ])
    let newModel = Model(model: oldModel, deep: true)
    let newChild = try XCTUnwrap(newModel[entity: "child"])
    let newRelationship = try XCTUnwrap(
      newChild[relationship: "parent"] as? ModelRelationship)
    newRelationship.constraintName = "new_fk"
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: oldModel, new: newModel)) { error in
      guard case SchemaSynchronizationError.unsupportedChanges = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsUnsupportedDefaultChange() throws {
    let oldAttribute = modelAttribute("name", type: "TEXT", allowsNull: true)
    oldAttribute.defaultValue = "old"
    let newAttribute = modelAttribute("name", type: "TEXT", allowsNull: true)
    newAttribute.defaultValue = "new"
    let oldEntity = modelEntity(table: "person",
                                attributes: [ oldAttribute ], primaryKey: [])
    let newEntity = modelEntity(table: "person",
                                attributes: [ newAttribute ], primaryKey: [])
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ]))) { error in
      guard case SchemaSynchronizationError.unsupportedChanges = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testSQLiteSynchronizesSupportedChanges() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL(
      "CREATE TABLE parent(id INTEGER PRIMARY KEY, name TEXT NULL)")
    try adaptor.performSQL("INSERT INTO parent VALUES (1, 'Alice')")
    try adaptor.performSQL("CREATE TABLE obsolete(id INTEGER PRIMARY KEY)")

    let oldParent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("name", type: "TEXT", allowsNull: true)
      ], primaryKey: [ "id" ])
    let obsolete = modelEntity(
      table: "obsolete",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let oldModel = Model(entities: [ oldParent, obsolete ])

    let newParent = ModelEntity(entity: oldParent, deep: true)
    newParent.attributes.append(
      modelAttribute("nickname", type: "TEXT", allowsNull: true))
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: false)
      ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: newParent)
    relationship.constraintName = "child parent fk"
    relationship.updateRule = .cascade
    relationship.deleteRule = .deny
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let newModel = Model(entities: [ newParent, child ])
    let factory = adaptor.synchronizationFactory

    XCTAssertTrue(factory is SQLite3SchemaSynchronizationFactory)
    XCTAssertTrue(factory.supportsSchemaSynchronization)
    let statements = try factory.schemaSynchronizationStatements(
      old: oldModel, new: newModel).map { $0.statement }
    XCTAssertFalse(statements.contains {
      $0.contains("ALTER TABLE \"child\" ADD CONSTRAINT")
    })
    XCTAssertTrue(statements.contains {
      $0.contains("CONSTRAINT \"child parent fk\" FOREIGN KEY")
    })

    try factory.synchronizeModels(old: oldModel, new: newModel)

    let rows = try adaptor.querySQL("SELECT id, name FROM parent")
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?["name"] as? String, "Alice")
    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    XCTAssertFalse(channel.isTransactionInProgress)
    XCTAssertEqual(Set(try channel.describeTableNames()),
                   Set([ "parent", "child" ]))
    let parent = try XCTUnwrap(
      channel.describeEntityWithTableName("parent"))
    XCTAssertNotNil(parent[columnName: "nickname"])
    let reflectedChild = try XCTUnwrap(
      channel.describeEntityWithTableName("child"))
    XCTAssertEqual(reflectedChild.relationships.count, 1)
    let reflectedRelationship = try XCTUnwrap(
      reflectedChild.relationships.first)
    XCTAssertEqual(reflectedRelationship.updateRule, .cascade)
    XCTAssertEqual(reflectedRelationship.deleteRule, .deny)
  }

  func testSQLiteCreatesForeignKeyToUnchangedTable() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("PRAGMA foreign_keys = ON")
    try adaptor.performSQL("CREATE TABLE parent(id INTEGER PRIMARY KEY)")
    let oldParent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let newParent = ModelEntity(entity: oldParent, deep: true)
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: newParent)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]

    try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ oldParent ]),
      new: Model(entities: [ newParent, child ]))

    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    let reflected = try XCTUnwrap(
      channel.describeEntityWithTableName("child"))
    XCTAssertEqual(reflected.relationships.count, 1)
    XCTAssertThrowsError(try channel.performSQL(
      "INSERT INTO child(id, parent_id) VALUES (1, 999)"))
  }

  func testRejectsForeignKeyToNonPrimaryColumn() throws {
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: parent)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ parent, child ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsDuplicateForeignKeyColumns() throws {
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("first", type: "INTEGER", allowsNull: true),
        modelAttribute("second", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: parent)
    relationship.joins = [
      Join(source: "first", destination: "id"),
      Join(source: "second", destination: "id")
    ]
    child.relationships = [ relationship ]
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ parent, child ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsImpossibleForeignKeyActions() throws {
    let rules: [ ( ConstraintRule?, ConstraintRule? ) ] = [
      ( .nullify, nil ), ( nil, .nullify ),
      ( .applyDefault, nil ), ( nil, .applyDefault )
    ]
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    for ( updateRule, deleteRule ) in rules {
      let parent = modelEntity(
        table: "parent",
        attributes: [
          modelAttribute("id", type: "INTEGER", allowsNull: false)
        ], primaryKey: [ "id" ])
      let child = modelEntity(
        table: "child",
        attributes: [
          modelAttribute("parentId", type: "INTEGER", allowsNull: false)
        ], primaryKey: [])
      let relationship = ModelRelationship(name: "parent", source: child,
                                           destination: parent)
      relationship.updateRule = updateRule
      relationship.deleteRule = deleteRule
      relationship.joins = [ Join(source: "parentId", destination: "id") ]
      child.relationships = [ relationship ]

      XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
        old: Model(entities: []),
        new: Model(entities: [ parent, child ]))) { error in
        guard case SchemaSynchronizationError.invalidModel = error else {
          return XCTFail("unexpected error: \(error)")
        }
      }
    }
  }

  func testAllowsNullableForeignKeyActions() throws {
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", type: "INTEGER", allowsNull: true)
      ], primaryKey: [])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: parent)
    relationship.updateRule = .nullify
    relationship.deleteRule = .applyDefault
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    let statements = try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ parent, child ]))
    XCTAssertEqual(statements.count, 2)
    let sql = statements.map { $0.statement }.joined(separator: "\n")
    XCTAssertTrue(sql.contains("ON UPDATE SET NULL"))
    XCTAssertTrue(sql.contains("ON DELETE SET DEFAULT"))
  }

  func testRejectsInconsistentSharedTablePrimaryKeys() throws {
    let first = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("code", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    first.name = "First"
    let second = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("code", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "code" ])
    second.name = "Second"
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ first, second ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testAllowsSharedTableLogicalNullabilityDifferences() throws {
    let first = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: false)
      ], primaryKey: [])
    first.name = "First"
    let second = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: true)
      ], primaryKey: [])
    second.name = "Second"
    let oldModel = Model(entities: [ first, second ])
    let newModel = Model(model: oldModel, deep: true)
    let newFirst = try XCTUnwrap(newModel[entity: "First"] as? ModelEntity)
    newFirst.attributes.append(
      modelAttribute("extra", type: "TEXT", allowsNull: true))
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    let statements = try factory.schemaSynchronizationStatements(
      old: oldModel, new: newModel).map { $0.statement }
    XCTAssertEqual(statements, [
      "ALTER TABLE \"shared\" ADD COLUMN \"extra\" TEXT NULL"
    ])
  }

  func testSynchronizesSharedTableWithLogicalNullabilityDifferences() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("CREATE TABLE shared(value TEXT NULL)")
    let first = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: false)
      ], primaryKey: [])
    first.name = "First"
    let second = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: true)
      ], primaryKey: [])
    second.name = "Second"
    let oldModel = Model(entities: [ second, first ])
    let newModel = Model(model: oldModel, deep: true)
    let newFirst = try XCTUnwrap(newModel[entity: "First"] as? ModelEntity)
    newFirst.attributes.append(
      modelAttribute("extra", type: "TEXT", allowsNull: true))

    try adaptor.synchronizationFactory.synchronizeModels(
      old: oldModel, new: newModel)

    XCTAssertEqual(try columns(of: "shared", using: adaptor),
                   [ "value", "extra" ])
  }

  func testSharedTableEntityOrderDoesNotChangeSchema() throws {
    let first = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: false)
      ], primaryKey: [])
    first.name = "First"
    let second = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: true)
      ], primaryKey: [])
    second.name = "Second"
    let oldModel = Model(entities: [ first, second ])
    let copiedModel = Model(model: oldModel, deep: true)
    let newModel = Model(entities: Array(copiedModel.entities.reversed()))
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertTrue(try factory.schemaSynchronizationStatements(
      old: oldModel, new: newModel).isEmpty)
  }

  func testRejectsInconsistentSharedCreatedColumn() throws {
    let first = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: true)
      ], primaryKey: [])
    first.name = "First"
    let second = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("value", type: "TEXT", allowsNull: false)
      ], primaryKey: [])
    second.name = "Second"
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ first, second ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsInconsistentSharedAddedColumn() throws {
    let first = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    first.name = "First"
    let second = modelEntity(
      table: "shared",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    second.name = "Second"
    let oldModel = Model(entities: [ first, second ])
    let newModel = Model(model: oldModel, deep: true)
    let newFirst = try XCTUnwrap(newModel[entity: "First"] as? ModelEntity)
    let newSecond = try XCTUnwrap(newModel[entity: "Second"] as? ModelEntity)
    newFirst.attributes.append(
      modelAttribute("extra", type: "TEXT", allowsNull: true))
    newSecond.attributes.append(
      modelAttribute("extra", type: "TEXT", allowsNull: false))
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: oldModel, new: newModel)) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsNullableCreatedPrimaryKey() throws {
    let entity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("id", type: "TEXT", allowsNull: true)
      ], primaryKey: [ "id" ])
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ entity ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsCreatedTableWithoutColumns() throws {
    let entity = modelEntity(table: "empty", attributes: [], primaryKey: [])
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ entity ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsMissingLockingAttribute() throws {
    let entity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    entity.attributesUsedForLocking = [
      modelAttribute("missing", type: "INTEGER", allowsNull: false)
    ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: []),
      new: Model(entities: [ entity ]))) { error in
      guard case SchemaSynchronizationError.invalidModel = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsSchemaMove() throws {
    let oldEntity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    oldEntity.elementID = "sample-id"
    oldEntity.schemaName = "public"
    let newEntity = ModelEntity(entity: oldEntity, deep: true)
    newEntity.schemaName = "archive"
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ]))) { error in
      guard case SchemaSynchronizationError.unsupportedChanges = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsCyclicTableDrops() throws {
    let first = modelEntity(
      table: "first",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("secondId", column: "second_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [ "id" ])
    let second = modelEntity(
      table: "second",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("firstId", column: "first_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [ "id" ])
    let toSecond = ModelRelationship(name: "second", source: first,
                                     destination: second)
    toSecond.joins = [ Join(source: "secondId", destination: "id") ]
    first.relationships = [ toSecond ]
    let toFirst = ModelRelationship(name: "first", source: second,
                                    destination: first)
    toFirst.joins = [ Join(source: "firstId", destination: "id") ]
    second.relationships = [ toFirst ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: [ first, second ]),
      new: Model(entities: []))) { error in
      guard case SchemaSynchronizationError.unsupportedChanges = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testRejectsRecycledTableRenameTarget() throws {
    let first = modelEntity(
      table: "first",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    first.elementID = "first-id"
    let second = modelEntity(
      table: "second",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    second.elementID = "second-id"
    let replacement = ModelEntity(entity: first, deep: true)
    replacement.externalName = "second"
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
      old: Model(entities: [ first, second ]),
      new: Model(entities: [ replacement ]))) { error in
      guard case SchemaSynchronizationError.unsupportedChanges = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testPlansParentAlterBeforeDependentTableCreation() throws {
    let oldParent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let newParent = ModelEntity(entity: oldParent, deep: true)
    let id = try XCTUnwrap(newParent[attribute: "id"] as? ModelAttribute)
    id.externalType = "BIGINT"
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("parentId", column: "parent_id", type: "BIGINT",
                       allowsNull: true)
      ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: newParent)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    let statements = try factory.schemaSynchronizationStatements(
      old: Model(entities: [ oldParent ]),
      new: Model(entities: [ newParent, child ])).map { $0.statement }
    let alterIndex = try XCTUnwrap(statements.firstIndex {
      $0.contains("ALTER COLUMN \"id\" TYPE BIGINT")
    })
    let createIndex = try XCTUnwrap(statements.firstIndex {
      $0.hasPrefix("CREATE TABLE \"child\"")
    })
    XCTAssertLessThan(alterIndex, createIndex)
  }

  func testRejectsUnsafeColumnType() throws {
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory

    let unsafeTypes = [
      "TEXT, \"extra\" TEXT", "INTEGER AS (1) STORED", "TEXT USING 0",
      "TEXT STORAGE EXTERNAL", "TEXT COMPRESSION pglz"
    ]
    for type in unsafeTypes {
      let entity = modelEntity(
        table: "sample",
        attributes: [
          modelAttribute("value", type: type, allowsNull: true)
        ], primaryKey: [])
      XCTAssertThrowsError(try factory.schemaSynchronizationStatements(
        old: Model(entities: []),
        new: Model(entities: [ entity ]))) { error in
        guard case SchemaSynchronizationError.invalidModel = error else {
          return XCTFail("unexpected error for \(type): \(error)")
        }
      }
    }
  }

  func testAcceptsSafeComplexColumnTypes() throws {
    let factory = SQLite3Adaptor(":memory:").synchronizationFactory
    let safeTypes = [
      "TIMESTAMP WITHOUT TIME ZONE", "DOUBLE PRECISION",
      "CHARACTER VARYING(255)", "NUMERIC(10, 2)", "\"storage\""
    ]
    for ( index, type ) in safeTypes.enumerated() {
      let entity = modelEntity(
        table: "sample_\(index)",
        attributes: [
          modelAttribute("value", type: type, allowsNull: true)
        ], primaryKey: [])
      XCTAssertNoThrow(try factory.schemaSynchronizationStatements(
        old: Model(entities: []),
        new: Model(entities: [ entity ])))
    }
  }

  func testQuotedColumnTypeCaseIsSignificant() throws {
    let oldEntity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("value", type: "\"storage\"", allowsNull: true)
      ], primaryKey: [])
    let newEntity = ModelEntity(entity: oldEntity, deep: true)
    let value = try XCTUnwrap(
      newEntity[attribute: "value"] as? ModelAttribute)
    value.externalType = "\"STORAGE\""
    let factory = SchemaSynchronizationFactory(adaptor: FakeAdaptor())

    let statements = try factory.schemaSynchronizationStatements(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ]))
    XCTAssertTrue(statements.contains {
      $0.statement.contains("ALTER COLUMN \"value\" TYPE \"STORAGE\"")
    })
  }

  func testSQLiteRejectsUnsupportedPlanBeforeExecuting() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL(
      "CREATE TABLE parent(id INTEGER PRIMARY KEY, name TEXT NULL)")
    let oldEntity = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("name", type: "TEXT", allowsNull: true)
      ], primaryKey: [ "id" ])
    let newEntity = ModelEntity(entity: oldEntity, deep: true)
    let name = try XCTUnwrap(
      newEntity[attribute: "name"] as? ModelAttribute)
    name.allowsNull = false
    newEntity.attributes.append(
      modelAttribute("nickname", type: "TEXT", allowsNull: true))
    let factory = adaptor.synchronizationFactory

    XCTAssertThrowsError(try factory.synchronizeModels(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ]))) { error in
      guard case SchemaSynchronizationError.unsupportedChanges = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try columns(of: "parent", using: adaptor),
                   [ "id", "name" ])
  }

  func testSQLiteRejectsCaseOnlyTableReplacement() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("CREATE TABLE Foo(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL("INSERT INTO Foo VALUES (1)")
    let oldEntity = modelEntity(
      table: "Foo",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    oldEntity.name = "Old"
    oldEntity.elementID = "old-id"
    let newEntity = modelEntity(
      table: "foo",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    newEntity.name = "New"
    newEntity.elementID = "new-id"

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ]))) { error in
      guard case SchemaSynchronizationError.unsupportedChanges = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    let rows = try adaptor.querySQL("SELECT id FROM Foo")
    XCTAssertEqual(rows.first?["id"] as? Int64, 1)
  }

  func testSQLiteRollsBackFailedPlan() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("CREATE TABLE sample(id INTEGER PRIMARY KEY)")
    let oldEntity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let newEntity = ModelEntity(entity: oldEntity, deep: true)
    newEntity.attributes.append(
      modelAttribute("first", type: "TEXT", allowsNull: true))
    newEntity.attributes.append(
      modelAttribute("second", type: "BROKEN +", allowsNull: true))
    let factory = adaptor.synchronizationFactory

    XCTAssertThrowsError(try factory.synchronizeModels(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ])))
    XCTAssertEqual(try columns(of: "sample", using: adaptor), [ "id" ])
    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    XCTAssertFalse(channel.isTransactionInProgress)
  }

  func testSQLiteRejectsStaleOldSchemaBeforeExecuting() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL(
      "CREATE TABLE sample(id INTEGER PRIMARY KEY, first TEXT NULL)")
    let oldEntity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let newEntity = ModelEntity(entity: oldEntity, deep: true)
    newEntity.attributes.append(
      modelAttribute("first", type: "TEXT", allowsNull: true))
    let factory = adaptor.synchronizationFactory

    XCTAssertThrowsError(try factory.synchronizeModels(
      old: Model(entities: [ oldEntity ]),
      new: Model(entities: [ newEntity ]))) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try columns(of: "sample", using: adaptor), [ "id", "first" ])
  }

  func testSQLiteLeavesNoOpSynchronizationAlone() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    let entity = modelEntity(
      table: "missing",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let model = Model(entities: [ entity ])

    let factory = adaptor.synchronizationFactory
    XCTAssertTrue(try factory.schemaSynchronizationStatements(
      old: model, new: model).isEmpty)
    try factory.synchronizeModels(old: model, new: model)
    XCTAssertTrue(try adaptor.fetchModel().entities.isEmpty)
  }

  func testSQLiteCreatesCompositePrimaryKey() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    let entity = modelEntity(
      table: "translation",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("language", type: "TEXT", allowsNull: false),
        modelAttribute("value", type: "TEXT", allowsNull: true)
      ], primaryKey: [ "id", "language" ])
    let factory = adaptor.synchronizationFactory

    try factory.synchronizeModels(
      old: Model(entities: []), new: Model(entities: [ entity ]))

    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    let reflected = try XCTUnwrap(
      channel.describeEntityWithTableName("translation"))
    XCTAssertEqual(reflected.primaryKeyAttributeNames, [ "id", "language" ])
  }

  func testSQLiteIgnoresToOneRelationshipWithoutJoins() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    child.relationships = [
      ModelRelationship(name: "parent", source: child,
                        destination: parent)
    ]

    try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: []),
      new: Model(entities: [ parent, child ]))

    XCTAssertEqual(Set(try adaptor.fetchModel().entityNames),
                   Set([ "parent", "child" ]))
  }

  func testSQLiteRejectsUnsafeDropWithUnmodeledReference() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("PRAGMA foreign_keys = ON")
    try adaptor.performSQL("CREATE TABLE parent(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL(
      "CREATE TABLE external_child(parent_id INTEGER REFERENCES parent(id))")
    let parent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ parent ]), new: Model(entities: []))) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertEqual(Set(try adaptor.fetchModel().entityNames),
                   Set([ "parent", "external_child" ]))
  }

  func testSQLiteRejectsStaleForeignKeyDestinationKey() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("CREATE TABLE parent(id INTEGER)")
    let oldParent = modelEntity(
      table: "parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let newParent = ModelEntity(entity: oldParent, deep: true)
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: newParent)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ oldParent ]),
      new: Model(entities: [ newParent, child ]))) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertEqual(Set(try adaptor.fetchModel().entityNames), [ "parent" ])
  }

  func testRejectsStaleForeignKeyConstraintNameBeforeExecuting() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("PRAGMA foreign_keys = ON")
    try adaptor.performSQL("CREATE TABLE parent_a(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL("CREATE TABLE parent_b(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL(
      "CREATE TABLE child(id INTEGER PRIMARY KEY, a_id INTEGER, " +
      "b_id INTEGER, FOREIGN KEY(a_id) REFERENCES parent_a(id), " +
      "FOREIGN KEY(b_id) REFERENCES parent_b(id))")
    let oldModel = try adaptor.fetchModel()
    let oldChild = try XCTUnwrap(oldModel[entity: "child"])
    let toA = try XCTUnwrap(oldChild.relationships.first {
      $0.destinationEntity?.externalNameOrName == "parent_a"
    } as? ModelRelationship)
    let toB = try XCTUnwrap(oldChild.relationships.first {
      $0.destinationEntity?.externalNameOrName == "parent_b"
    } as? ModelRelationship)
    let nameA = try XCTUnwrap(toA.constraintName)
    let nameB = try XCTUnwrap(toB.constraintName)
    XCTAssertNotEqual(nameA, nameB)
    toA.constraintName = nameB
    toB.constraintName = nameA
    let newModel = Model(model: oldModel, deep: true)
    let newChild = try XCTUnwrap(newModel[entity: "child"])
    let newToA = try XCTUnwrap(newChild.relationships.first {
      $0.destinationEntity?.externalNameOrName == "parent_a"
    } as? ModelRelationship)
    newToA.deleteRule = .cascade
    let factory = NamedForeignKeySQLiteSynchronizationFactory(
      adaptor: adaptor)

    XCTAssertThrowsError(try factory.synchronizeModels(
      old: oldModel, new: newModel)) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    let reflected = try adaptor.fetchModel()
    let child = try XCTUnwrap(reflected[entity: "child"])
    XCTAssertTrue(child.relationships.allSatisfy {
      $0.deleteRule == .noAction
    })
  }

  func testSQLiteRejectsShorthandCaseInsensitiveInboundForeignKey() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("PRAGMA foreign_keys = ON")
    try adaptor.performSQL("CREATE TABLE Parent(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL(
      "CREATE TABLE child(parent_id INTEGER REFERENCES parent)")
    let parent = modelEntity(
      table: "Parent",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [])
    let newChild = ModelEntity(entity: child, deep: true)

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ parent, child ]),
      new: Model(entities: [ newChild ]))) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertEqual(Set(try adaptor.fetchModel().entityNames),
                   Set([ "Parent", "child" ]))
  }

  func testSQLiteRejectsUnmodeledGeneratedColumnBeforeDrop() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL(
      "CREATE TABLE sample(id INTEGER PRIMARY KEY, " +
      "doubled INTEGER GENERATED ALWAYS AS (id * 2) STORED)")
    let entity = modelEntity(
      table: "sample",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ entity ]),
      new: Model(entities: []))) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try adaptor.fetchModel().entityNames, [ "sample" ])
  }

  func testSQLiteRejectsImplicitNullableStaleDrop() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL(
      "CREATE TABLE sample(id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
    let entity = ModelEntity(name: "sample", table: "sample")
    entity.attributes = [
      modelAttribute("id", type: "INTEGER", allowsNull: false),
      ImplicitNullableAttribute(name: "name", externalType: "TEXT")
    ]
    entity.primaryKeyAttributeNames = [ "id" ]

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ entity ]), new: Model(entities: []))) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try columns(of: "sample", using: adaptor), [ "id", "name" ])
  }

  func testSQLiteRejectsStaleDroppedTableForeignKeys() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("PRAGMA foreign_keys = ON")
    try adaptor.performSQL("CREATE TABLE parent_a(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL("CREATE TABLE parent_b(id INTEGER PRIMARY KEY)")
    try adaptor.performSQL(
      "CREATE TABLE child(id INTEGER PRIMARY KEY, parent_id INTEGER, " +
      "FOREIGN KEY(parent_id) REFERENCES parent_b(id))")
    let parentA = modelEntity(
      table: "parent_a",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let parentB = modelEntity(
      table: "parent_b",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: parentA)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: Model(entities: [ parentA, parentB, child ]),
      new: Model(entities: [ parentA, parentB ]))) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertTrue(try adaptor.fetchModel().entityNames.contains("child"))
  }

  func testSQLiteRejectsVirtualTableShadowModification() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("CREATE VIRTUAL TABLE docs USING fts5(body)")
    let oldModel = try adaptor.fetchModel()
    let newModel = Model(entities: oldModel.entities.filter {
      $0.externalNameOrName != "docs_data"
    })

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: oldModel, new: newModel)) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertTrue(try adaptor.fetchModel().entityNames.contains("docs_data"))
  }

  func testSQLiteRejectsDropWithRetainedVirtualTable() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL(
      "CREATE TABLE docs(id INTEGER PRIMARY KEY, body TEXT)")
    try adaptor.performSQL(
      "CREATE VIRTUAL TABLE search USING fts5(" +
      "body, content='docs', content_rowid='id')")
    let oldModel = try adaptor.fetchModel()
    let newModel = Model(entities: oldModel.entities.filter {
      $0.externalNameOrName != "docs"
    })

    XCTAssertThrowsError(try adaptor.synchronizationFactory.synchronizeModels(
      old: oldModel, new: newModel)) { error in
      guard case SchemaSynchronizationError.preconditionFailed = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
    XCTAssertTrue(try adaptor.fetchModel().entityNames.contains("docs"))
  }

  func testSynchronizesForeignKeyAcrossTableRename() throws {
    let pool = SingleConnectionPool(maxAge: 60)
    let adaptor = SQLite3Adaptor(":memory:", pool: pool)
    try adaptor.performSQL("PRAGMA foreign_keys = ON")
    try adaptor.performSQL("CREATE TABLE parent_old(id INTEGER PRIMARY KEY)")
    let oldParent = modelEntity(
      table: "parent_old",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false)
      ], primaryKey: [ "id" ])
    oldParent.elementID = "parent-id"
    let newParent = ModelEntity(entity: oldParent, deep: true)
    newParent.externalName = "parent_new"
    let child = modelEntity(
      table: "child",
      attributes: [
        modelAttribute("id", type: "INTEGER", allowsNull: false),
        modelAttribute("parentId", column: "parent_id", type: "INTEGER",
                       allowsNull: true)
      ], primaryKey: [ "id" ])
    let relationship = ModelRelationship(name: "parent", source: child,
                                         destination: newParent)
    relationship.joins = [ Join(source: "parentId", destination: "id") ]
    child.relationships = [ relationship ]
    let factory = TestSQLiteSchemaSynchronizationFactory(adaptor: adaptor)

    try factory.synchronizeModels(
      old: Model(entities: [ oldParent ]),
      new: Model(entities: [ newParent, child ]))

    XCTAssertEqual(Set(try adaptor.fetchModel().entityNames),
                   Set([ "parent_new", "child" ]))
    XCTAssertThrowsError(try adaptor.performSQL(
      "INSERT INTO child(id, parent_id) VALUES (1, 999)"))
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

  private func columns(of table: String, using adaptor: Adaptor) throws
       -> [ String ]
  {
    let channel = try adaptor.openChannelFromPool()
    defer { adaptor.releaseChannel(channel) }
    let entity = try XCTUnwrap(
      channel.describeEntityWithTableName(table))
    return entity.attributes.map { $0.columnNameOrName }
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
    ( "testCompositePrimaryKeyCreation", testCompositePrimaryKeyCreation ),
    ( "testDropAddressStatement",    testDropAddressStatement ),
    ( "testCreateAddressStatements", testCreateAddressStatements ),
    ( "testCreateStatementOrdering", testCreateStatementOrdering ),
    ( "testCreateStatementOrderingForDependencyChain",
      testCreateStatementOrderingForDependencyChain ),
    ( "testNonDirectAdaptorForcesEmbeddedConstraints",
      testNonDirectAdaptorForcesEmbeddedConstraints ),
    ( "testCyclicCreationOrderIsStable",
      testCyclicCreationOrderIsStable ),
    ( "testEmbeddedConstraint",      testEmbeddedConstraint ),
    ( "testLateConstraint",          testLateConstraint ),
    ( "testPlansDirectSchemaChanges", testPlansDirectSchemaChanges ),
    ( "testPlansChangesFromCodeEntities",
      testPlansChangesFromCodeEntities ),
    ( "testRejectsPatternModels", testRejectsPatternModels ),
    ( "testRejectsDuplicateTargetColumns",
      testRejectsDuplicateTargetColumns ),
    ( "testRejectsDuplicateLogicalEntityNames",
      testRejectsDuplicateLogicalEntityNames ),
    ( "testRejectsDuplicatePrimaryKeyAttributes",
      testRejectsDuplicatePrimaryKeyAttributes ),
    ( "testRejectsForeignKeyWithWrongSource",
      testRejectsForeignKeyWithWrongSource ),
    ( "testRejectsUnattachedCodeRelationshipWithoutCrashing",
      testRejectsUnattachedCodeRelationshipWithoutCrashing ),
    ( "testValidatesCodeRelationshipWithCustomSource",
      testValidatesCodeRelationshipWithCustomSource ),
    ( "testRejectsEmptyRelationshipName",
      testRejectsEmptyRelationshipName ),
    ( "testRejectsInconsistentForeignKeyDestination",
      testRejectsInconsistentForeignKeyDestination ),
    ( "testRejectsUnresolvedForeignKeyDestination",
      testRejectsUnresolvedForeignKeyDestination ),
    ( "testRejectsForeignKeyWithForeignJoinAttribute",
      testRejectsForeignKeyWithForeignJoinAttribute ),
    ( "testRejectsForeignKeyConstraintRename",
      testRejectsForeignKeyConstraintRename ),
    ( "testRejectsUnsupportedDefaultChange",
      testRejectsUnsupportedDefaultChange ),
    ( "testSQLiteSynchronizesSupportedChanges",
      testSQLiteSynchronizesSupportedChanges ),
    ( "testSQLiteCreatesForeignKeyToUnchangedTable",
      testSQLiteCreatesForeignKeyToUnchangedTable ),
    ( "testRejectsForeignKeyToNonPrimaryColumn",
      testRejectsForeignKeyToNonPrimaryColumn ),
    ( "testRejectsDuplicateForeignKeyColumns",
      testRejectsDuplicateForeignKeyColumns ),
    ( "testRejectsImpossibleForeignKeyActions",
      testRejectsImpossibleForeignKeyActions ),
    ( "testAllowsNullableForeignKeyActions",
      testAllowsNullableForeignKeyActions ),
    ( "testRejectsInconsistentSharedTablePrimaryKeys",
      testRejectsInconsistentSharedTablePrimaryKeys ),
    ( "testAllowsSharedTableLogicalNullabilityDifferences",
      testAllowsSharedTableLogicalNullabilityDifferences ),
    ( "testSynchronizesSharedTableWithLogicalNullabilityDifferences",
      testSynchronizesSharedTableWithLogicalNullabilityDifferences ),
    ( "testSharedTableEntityOrderDoesNotChangeSchema",
      testSharedTableEntityOrderDoesNotChangeSchema ),
    ( "testRejectsInconsistentSharedCreatedColumn",
      testRejectsInconsistentSharedCreatedColumn ),
    ( "testRejectsInconsistentSharedAddedColumn",
      testRejectsInconsistentSharedAddedColumn ),
    ( "testRejectsNullableCreatedPrimaryKey",
      testRejectsNullableCreatedPrimaryKey ),
    ( "testRejectsCreatedTableWithoutColumns",
      testRejectsCreatedTableWithoutColumns ),
    ( "testRejectsMissingLockingAttribute",
      testRejectsMissingLockingAttribute ),
    ( "testRejectsSchemaMove", testRejectsSchemaMove ),
    ( "testRejectsCyclicTableDrops", testRejectsCyclicTableDrops ),
    ( "testRejectsRecycledTableRenameTarget",
      testRejectsRecycledTableRenameTarget ),
    ( "testPlansParentAlterBeforeDependentTableCreation",
      testPlansParentAlterBeforeDependentTableCreation ),
    ( "testRejectsUnsafeColumnType", testRejectsUnsafeColumnType ),
    ( "testAcceptsSafeComplexColumnTypes",
      testAcceptsSafeComplexColumnTypes ),
    ( "testQuotedColumnTypeCaseIsSignificant",
      testQuotedColumnTypeCaseIsSignificant ),
    ( "testSQLiteRejectsUnsupportedPlanBeforeExecuting",
      testSQLiteRejectsUnsupportedPlanBeforeExecuting ),
    ( "testSQLiteRejectsCaseOnlyTableReplacement",
      testSQLiteRejectsCaseOnlyTableReplacement ),
    ( "testSQLiteRollsBackFailedPlan", testSQLiteRollsBackFailedPlan ),
    ( "testSQLiteRejectsStaleOldSchemaBeforeExecuting",
      testSQLiteRejectsStaleOldSchemaBeforeExecuting ),
    ( "testSQLiteLeavesNoOpSynchronizationAlone",
      testSQLiteLeavesNoOpSynchronizationAlone ),
    ( "testSQLiteCreatesCompositePrimaryKey",
      testSQLiteCreatesCompositePrimaryKey ),
    ( "testSQLiteIgnoresToOneRelationshipWithoutJoins",
      testSQLiteIgnoresToOneRelationshipWithoutJoins ),
    ( "testSQLiteRejectsUnsafeDropWithUnmodeledReference",
      testSQLiteRejectsUnsafeDropWithUnmodeledReference ),
    ( "testSQLiteRejectsStaleForeignKeyDestinationKey",
      testSQLiteRejectsStaleForeignKeyDestinationKey ),
    ( "testRejectsStaleForeignKeyConstraintNameBeforeExecuting",
      testRejectsStaleForeignKeyConstraintNameBeforeExecuting ),
    ( "testSQLiteRejectsShorthandCaseInsensitiveInboundForeignKey",
      testSQLiteRejectsShorthandCaseInsensitiveInboundForeignKey ),
    ( "testSQLiteRejectsUnmodeledGeneratedColumnBeforeDrop",
      testSQLiteRejectsUnmodeledGeneratedColumnBeforeDrop ),
    ( "testSQLiteRejectsImplicitNullableStaleDrop",
      testSQLiteRejectsImplicitNullableStaleDrop ),
    ( "testSQLiteRejectsStaleDroppedTableForeignKeys",
      testSQLiteRejectsStaleDroppedTableForeignKeys ),
    ( "testSQLiteRejectsVirtualTableShadowModification",
      testSQLiteRejectsVirtualTableShadowModification ),
    ( "testSQLiteRejectsDropWithRetainedVirtualTable",
      testSQLiteRejectsDropWithRetainedVirtualTable ),
    ( "testSynchronizesForeignKeyAcrossTableRename",
      testSynchronizesForeignKeyAcrossTableRename ),
  ]
}

private final class ResolvedSourceCodeRelationship:
                    CodeRelationship<ActiveRecord>
{
  private var resolvedSource : Entity

  override var isEntityResolved : Bool { return true }
  override var entity : Entity {
    set { resolvedSource = newValue }
    get { return resolvedSource }
  }

  init(source: Entity, destination: Entity) {
    resolvedSource = source
    super.init(name: "parent", source: source, destination: destination)
    sourceAttributeName = "parentId"
    targetAttributeName = "id"
  }
}

private final class TestSQLiteSchemaSynchronizationFactory:
                    SQLite3SchemaSynchronizationFactory
{
  override var supportsDirectTableRenaming: Bool { return true }
}

private final class NamedForeignKeySQLiteSynchronizationFactory:
                    SQLite3SchemaSynchronizationFactory
{
  override var supportsDirectForeignKeyModification: Bool { return true }
  override var reflectsForeignKeyConstraintNames: Bool { return true }
}

private final class ImplicitNullableAttribute: Attribute {

  let name         : String
  let externalType : String?
  let userData     = [ String : Any ]()
  let elementID    : String? = nil

  init(name: String, externalType: String) {
    self.name = name
    self.externalType = externalType
  }
}
