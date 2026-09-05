//
//  SchemaSynchronizationFactory.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * Object used to generate database DDL expressions (i.e. `CREATE TABLE` and 
 * such). Similar to ``SQLExpression``.
 *
 * To acquire a `SchemaSynchronizationFactory` use the
 * `Adaptor.synchronizationFactory` property as the adaptor may provide a
 * subclass w/ customized generation.
 *
 * Note: This is a stateful object.
 */
open class SchemaSynchronizationFactory: SchemaGeneration, SchemaSynchronization
{
  public let log     : ZeeQLLogger
  public let adaptor : Adaptor
  
  public var createdTables   = Set<String>()
  public var extraTableJoins = [ SQLExpression ]()
  
  public init(adaptor: Adaptor) {
    self.adaptor = adaptor
    self.log     = self.adaptor.log
  }
  
  open var supportsDirectForeignKeyModification     : Bool { return true }
  open var supportsDirectTableRenaming              : Bool { return true }
  open var supportsDirectColumnCoercion             : Bool { return true }
  open var supportsDirectColumnDeletion             : Bool { return true }
  open var supportsDirectColumnInsertion            : Bool { return true }
  open var supportsDirectColumnNullRuleModification : Bool { return true }
  open var supportsDirectColumnRenaming             : Bool { return true }

  open var reflectsForeignKeyConstraintNames        : Bool { return true }

  /// Execution is opt-in; dry-run statement planning remains available.
  open var supportsSchemaSynchronization            : Bool { return false }

  open func logModelChanges(old: Model, new: Model) {
    // Note: run SQLizer and/or FancyModelMaker before comparing! (TBD)

    log.log("from:", old)
    log.log("to:  ", new)
    log.log("-----------------------------------------")
    
    let changes = new.entities.calculateTableChanges(since: old.entities)
    log.log("  changes:", changes)
    
    log.log("dropped: ", changes.dropped)
    log.log("created: ", changes.created)
    
    for ( old, new ) in changes.same {
      log.log("\nTable:", new.groupExternalName)
      do {
        let changes = new.calculateAttributeChanges(since: old)
        log.log("  dropped: ", changes.dropped)
        log.log("  created: ", changes.created)
        log.log("  same:    ", changes.same)

        for ( old, new ) in changes.same {
          guard let changes = attributeChanges(new: new, since: old)
           else { continue }
          log.log("    attr changes:", new.name, changes)
        }
      }
      do {
        let changes = new.calculateForeignKeyConstraintChanges(since: old)
        log.log("  dropped: ", changes.dropped)
        log.log("  created: ", changes.created)
      }
    }

    log.log("-----------------------------------------")
  }

  /// Builds the same validated statement plan used by ``synchronizeModels``.
  public final func schemaSynchronizationStatements(old: Model, new: Model) 
    throws -> [ SQLExpression ]
  {
    let plan = try makeSynchronizationPlan(old: old, new: new)
    return try statements(for: plan)
  }

  open func synchronizeModels(old: Model, new: Model) throws {
    guard supportsSchemaSynchronization else {
      throw SchemaSynchronizationError.unsupported
    }
    let plan       = try makeSynchronizationPlan(old: old, new: new)
    let statements = try statements(for: plan)
    guard !statements.isEmpty else { return }

    let channel = try adaptor.openChannelFromPool()
    var releaseChannel = false
    defer {
      if releaseChannel {
        adaptor.releaseChannel(channel)
      }
      else {
        log.error("discarding schema synchronization channel")
      }
    }

    try channel.begin()

    do {
      try verifyPreconditions(of: plan, on: channel)
      for statement in statements {
        _ = try channel.evaluateUpdateExpression(statement)
      }
      try verifyEffects(of: plan, on: channel)
    }
    catch let bodyError {
      do {
        try channel.rollback()
        releaseChannel = true
      }
      catch {
        log.warn("could not rollback schema synchronization:", error,
                 "after migration error:", bodyError)
      }
      throw bodyError
    }

    do {
      try channel.commit()
      releaseChannel = true
    }
    catch let commitError {
      do {
        try channel.rollback()
        releaseChannel = true
      }
      catch {
        log.warn("could not rollback schema synchronization:", error,
                 "after commit error:", commitError)
      }
      throw commitError
    }
  }

  open func normalizedColumnType(_ type: String) -> String {
    var normalized = ""
    normalized.reserveCapacity(type.count)
    var quoteEnd: Character?
    var pendingSpace = false
    var index = type.startIndex
    while index < type.endIndex {
      let character = type[index]
      let nextIndex = type.index(after: index)
      let next = nextIndex < type.endIndex ? type[nextIndex] : nil
      if let end = quoteEnd {
        normalized.append(character)
        if character == end {
          if next == end {
            normalized.append(end)
            index = type.index(after: nextIndex)
            continue
          }
          quoteEnd = nil
        }
        index = nextIndex
        continue
      }
      if character.isWhitespace {
        if !normalized.isEmpty { pendingSpace = true }
        index = nextIndex
        continue
      }
      if pendingSpace {
        normalized.append(" ")
        pendingSpace = false
      }
      switch character {
        case "\"", "'", "`": quoteEnd = character
        case "[":           quoteEnd = "]"
        default:            break
      }
      normalized.append(contentsOf: String(character).uppercased())
      index = nextIndex
    }
    switch normalized {
      case "INT", "INT4": return "INTEGER"
      case "INT8":        return "BIGINT"
      case "INT2":        return "SMALLINT"
      case "BOOL":        return "BOOLEAN"
      case "FLOAT4":      return "REAL"
      case "FLOAT8":      return "DOUBLE PRECISION"
      case "DECIMAL":     return "NUMERIC"
      case "TIMESTAMPTZ": return "TIMESTAMP WITH TIME ZONE"
      default:            return normalized
    }
  }

  open func normalizedSchemaObjectName(_ name: String) -> String {
    return name
  }

  open func columnTypesAreEquivalent(_ lhs: Attribute, _ rhs: Attribute) -> Bool
  {
    let expression = adaptor.expressionFactory.createExpression(nil)
    let lhsType = expression.columnTypeStringForAttribute(lhs)
    let rhsType = expression.columnTypeStringForAttribute(rhs)
    return normalizedColumnType(lhsType) == normalizedColumnType(rhsType)
  }

  open func columnTypesMatchForSchemaVerification(_   actual : Attribute,
                                                  _ expected : Attribute)
       -> Bool
  {
    if columnTypesAreEquivalent(actual, expected) { return true }
    guard actual.width == nil || actual.precision == nil else { return false }
    let comparable = ModelAttribute(attribute: expected)
    if actual.width == nil { comparable.width = nil }
    if actual.precision == nil { comparable.precision = nil }
    return columnTypesAreEquivalent(actual, comparable)
  }

  open func synchronizationIssuesForTable(named table: String) -> [ String ] {
    return []
  }

  open func isSystemTableForSynchronization(_ table: String) -> Bool {
    return false
  }

  open func columnNamesForVerification(in table: String,
                                       on channel: AdaptorChannel) throws
       -> Set<String>?
  {
    return nil
  }

  open func preflightSynchronizationIssues(modifyingTables: Set<String>,
                                           droppingTables: Set<String>,
                                           on channel: AdaptorChannel) throws
       -> [ String ]
  {
    return []
  }
}

fileprivate struct SchemaSynchronizationPlan {

  var oldModel           : Model?
  var newModel           : Model?
  var oldTableNames      = Set<String>()
  var newTableNames      = Set<String>()
  var droppedForeignKeys = [ SchemaForeignKeyChange ]()
  var droppedTables      = [ SQLTableGroup ]()
  var renamedTables      = [ SchemaTableRename ]()
  var createdTables      = [ SQLTableGroup ]()
  var droppedColumns     = [ SchemaColumnChange ]()
  var renamedColumns     = [ SchemaColumnRename ]()
  var changedTypes       = [ SchemaColumnPair ]()
  var changedNullability = [ SchemaColumnPair ]()
  var addedColumns       = [ SchemaColumnChange ]()
  var addedForeignKeys   = [ SchemaForeignKeyChange ]()
}

fileprivate struct SchemaSnapshot {

  let tableNames : Set<String>
  let model      : Model

  func group(named table: String) -> SQLTableGroup {
    return model[entityGroup: table]
  }

  func attribute(named column: String, in table: String) -> Attribute? {
    return group(named: table).groupAttributes.first {
      $0.columnNameOrName == column
    }
  }
}

fileprivate struct SchemaForeignKeyChange {

  let table      : String
  let foreignKey : SQLForeignKey
}

fileprivate struct SchemaTableRename {

  let oldName : String
  let newName : String
  let entity  : Entity
}

fileprivate struct SchemaColumnChange {

  let table     : String
  let entity    : Entity
  let attribute : Attribute
}

fileprivate struct SchemaColumnPair {

  let table        : String
  let entity       : Entity
  let oldAttribute : Attribute
  let newAttribute : Attribute
}

fileprivate struct SchemaColumnRename {

  let table        : String
  let entity       : Entity
  let oldAttribute : Attribute
  let oldName      : String
  let newName      : String
}

fileprivate extension SchemaSynchronizationFactory {

  func makeSynchronizationPlan(old: Model, new: Model) throws
       -> SchemaSynchronizationPlan
  {
    try validateResolvedModels(old: old, new: new)
    let oldModel = Model(model: old, deep: true)
    let newModel = Model(model: new, deep: true)
    return try synchronizationPlan(old: oldModel, new: newModel)
  }

  func validateResolvedModels(old: Model, new: Model) throws {
    var issues = [ String ]()
    for ( label, model ) in [ ( "old", old ), ( "new", new ) ] {
      let entityIDs = Set(model.entities.map { ObjectIdentifier($0) })
      for entity in model.entities {
        if entity.isPattern {
          issues.append(
            "cannot synchronize pattern table " +
            "\(entity.externalNameOrName) in the \(label) model")
        }
        validateReferences(in: entity, model: model, entityIDs: entityIDs,
                           label: label, issues: &issues)
      }
      validateUniqueEntityNames(in: model, label: label, issues: &issues)
      validateUniqueTables(in: model, label: label, issues: &issues)
      validateUniqueColumns(in: model, label: label, issues: &issues)
      validatePrimaryKeys(in: model, label: label, issues: &issues)
    }
    guard issues.isEmpty else {
      throw SchemaSynchronizationError.invalidModel(
        Array(Set(issues)).sorted())
    }
  }

  func validateUniqueEntityNames(in model: Model, label: String,
                                 issues: inout [ String ])
  {
    var names = Set<String>()
    for entity in model.entities {
      if entity.name.isEmpty {
        issues.append("empty entity name in the \(label) model")
      }
      if !names.insert(entity.name).inserted {
        issues.append(
          "duplicate entity name \(entity.name) in the \(label) model")
      }
    }
  }

  func validateReferences(in entity: Entity, model: Model,
                          entityIDs: Set<ObjectIdentifier>, label: String,
                          issues: inout [ String ])
  {
    let attributeNames = Set(entity.attributes.map { $0.name })
    if attributeNames.count != entity.attributes.count {
      issues.append(
        "duplicate attribute name in \(entity.name) in the \(label) model")
    }
    for attribute in entity.attributes {
      if attribute.name.isEmpty {
        issues.append(
          "empty attribute name in \(entity.name) in the \(label) model")
      }
      if attribute.columnNameOrName.isEmpty {
        issues.append(
          "empty column name in \(entity.name) in the \(label) model")
      }
      else if attribute.columnNameOrName == "*" {
        issues.append(
          "literal * column name in \(entity.name) in the \(label) model")
      }
    }
    let primaryKeyNames = entity.primaryKeyAttributeNames ?? []
    if Set(primaryKeyNames).count != primaryKeyNames.count {
      issues.append(
        "duplicate primary key attribute in \(entity.name) " +
        "in the \(label) model")
    }
    for name in primaryKeyNames
          where !attributeNames.contains(name)
    {
      issues.append(
        "primary key attribute \(entity.name).\(name) does not exist " +
        "in the \(label) model")
    }
    for attribute in entity.attributesUsedForLocking ?? []
          where !attributeNames.contains(attribute.name)
    {
      issues.append(
        "locking attribute \(entity.name).\(attribute.name) does not exist " +
        "in the \(label) model")
    }
    for relationship in entity.relationships {
      let key = entity.name + "." + relationship.name
      if relationship.name.isEmpty {
        issues.append(
          "empty relationship name in \(entity.name) in the \(label) model")
      }
      if let codeRelationship = relationship as? CodeRelationshipType,
         !codeRelationship.isEntityResolved
      {
        issues.append(
          "foreign key \(key) has an unresolved source in the \(label) model")
        continue
      }
      if relationship.entity !== entity {
        issues.append(
          "foreign key \(key) has the wrong source in the \(label) model")
        continue
      }
      let joins: [ Join ]
      if let provider = relationship as? SchemaSynchronizationJoinProvider {
        do {
          joins = try provider.schemaSynchronizationJoins()
        }
        catch {
          issues.append(
            "cannot resolve joins for \(key) in the \(label) model: \(error)")
          continue
        }
      }
      else {
        joins = relationship.joins
      }
      guard !relationship.isToMany, !joins.isEmpty else { continue }
      let destination: Entity
      if let connectedDestination = relationship.destinationEntity {
        if !entityIDs.contains(ObjectIdentifier(connectedDestination)) {
          issues.append(
            "foreign key \(key) has an external destination in the " +
            "\(label) model")
        }
        if let relationship = relationship as? ModelRelationship,
           let name = relationship.destinationEntityName,
           name != connectedDestination.name
        {
          issues.append(
            "foreign key \(key) has inconsistent destination names in the " +
            "\(label) model")
        }
        destination = connectedDestination
      }
      else if let relationship = relationship as? ModelRelationship,
              let name = relationship.destinationEntityName,
              let resolved = model[entity: name]
      {
        destination = resolved
      }
      else {
        issues.append(
          "foreign key \(key) has no destination in the \(label) model")
        continue
      }
      var joinsResolve = true
      for join in joins {
        if let source = join.source {
          if !entity.attributes.contains(where: { $0 === source }) {
            joinsResolve = false
          }
          if let name = join.sourceName, name != source.name {
            joinsResolve = false
          }
        }
        if let target = join.destination {
          if !destination.attributes.contains(where: { $0 === target }) {
            joinsResolve = false
          }
          if let name = join.destinationName, name != target.name {
            joinsResolve = false
          }
        }
        if join.source(in: entity) == nil
           || join.destination(in: destination) == nil
        {
          joinsResolve = false
        }
      }
      if !joinsResolve {
        issues.append(
          "foreign key \(key) has unresolved joins in the \(label) model")
      }
    }
  }

  func validateUniqueTables(in model: Model, label: String,
                            issues: inout [ String ])
  {
    var tables = [ String : Entity ]()
    for entity in model.entities {
      let table = entity.externalNameOrName
      if table.isEmpty {
        issues.append("empty table name in the \(label) model")
      }
      else if table == "*" {
        issues.append("literal * table name in the \(label) model")
      }
      let key = normalizedSchemaObjectName(table)
      guard let existing = tables[key] else {
        tables[key] = entity
        continue
      }
      let existingExternal = existing.externalName
      let external = entity.externalName
      if existingExternal?.isEmpty == false && external == existingExternal
         && existing.schemaName == entity.schemaName
      {
        continue
      }
      issues.append("duplicate table \(table) in the \(label) model")
    }
  }

  func validateUniqueColumns(in model: Model, label: String,
                             issues: inout [ String ])
  {
    for group in model.entities.extractEntityGroups() {
      var columns = [ String : ( Attribute, ObjectIdentifier ) ]()
      for entity in group {
        let entityID = ObjectIdentifier(entity)
        for attribute in entity.attributes {
          let column = attribute.columnNameOrName
          let key = normalizedSchemaObjectName(column)
          guard let existing = columns[key] else {
            columns[key] = ( attribute, entityID )
            continue
          }
          if existing.1 == entityID
             || existing.0.columnNameOrName != column
             || !columnTypesAreEquivalent(existing.0, attribute)
          {
            issues.append(
              "duplicate column \(group.groupExternalName).\(column) " +
              "in the \(label) model")
          }
        }
      }
    }
  }

  func validatePrimaryKeys(in model: Model, label: String,
                           issues: inout [ String ])
  {
    for group in model.entities.extractEntityGroups() {
      let primaryKeys = group.map { entity in
        (entity.primaryKeyAttributeNames ?? []).compactMap {
          entity[attribute: $0]?.columnNameOrName
        }
      }
      guard let first = primaryKeys.first else { continue }
      if primaryKeys.dropFirst().contains(where: { $0 != first }) {
        issues.append(
          "inconsistent primary keys for table \(group.groupExternalName) " +
          "in the \(label) model")
      }
    }
  }

  func tableChangesForSynchronization(old: [ Entity ], new: [ Entity ],
                                      invalid: inout [ String ])
       -> SchemaSyncChangeSet<SQLTableGroup>
  {
    var matchedOld = Set<Int>()
    var matchedNew = Set<Int>()
    var same = [ ( SQLTableGroup, SQLTableGroup ) ]()
    let oldGroups = old.extractEntityGroups()
    let newGroups = new.extractEntityGroups()
    let describe: ( SQLTableGroup ) -> String = { $0.groupExternalName }

    matchUnique(old: oldGroups, new: newGroups,
                matchedOld: &matchedOld, matchedNew: &matchedNew,
                same: &same, noun: "table", describe: describe,
                invalid: &invalid,
                where: tableGroupsShareElementID)
    matchUnique(old: oldGroups, new: newGroups,
                matchedOld: &matchedOld, matchedNew: &matchedNew,
                same: &same, noun: "table", describe: describe,
                invalid: &invalid,
                where: tableGroupsShareLogicalNames)
    matchUnique(old: oldGroups, new: newGroups,
                matchedOld: &matchedOld, matchedNew: &matchedNew,
                same: &same, noun: "table", describe: describe,
                invalid: &invalid,
                where: {
                  normalizedSchemaObjectName($0.groupExternalName)
                    == normalizedSchemaObjectName($1.groupExternalName)
                })

    return SchemaSyncChangeSet(
      created: newGroups.indices.compactMap {
        matchedNew.contains($0) ? nil : newGroups[$0]
      },
      dropped: oldGroups.indices.compactMap {
        matchedOld.contains($0) ? nil : oldGroups[$0]
      },
      same: same)
  }

  func tableGroupsShareElementID(_ lhs: SQLTableGroup,
                                 _ rhs: SQLTableGroup) -> Bool
  {
    let lhsIDs = Set(lhs.compactMap { ($0 as? ModelEntity)?.elementID })
    let rhsIDs = Set(rhs.compactMap { ($0 as? ModelEntity)?.elementID })
    guard !lhsIDs.isEmpty, !rhsIDs.isEmpty else { return false }
    return !lhsIDs.isDisjoint(with: rhsIDs)
  }

  func tableGroupsShareLogicalNames(_ lhs: SQLTableGroup,
                                    _ rhs: SQLTableGroup) -> Bool
  {
    let lhsIDs = Set(lhs.compactMap { ($0 as? ModelEntity)?.elementID })
    let rhsIDs = Set(rhs.compactMap { ($0 as? ModelEntity)?.elementID })
    if !lhsIDs.isEmpty && !rhsIDs.isEmpty { return false }
    return Set(lhs.map { $0.name }) == Set(rhs.map { $0.name })
  }

  func attributeChangesForSynchronization(old: SQLTableGroup,
                                          new: SQLTableGroup,
                                          invalid: inout [ String ])
       -> SchemaSyncChangeSet<Attribute>
  {
    var matchedOld = Set<Int>()
    var matchedNew = Set<Int>()
    var same = [ ( Attribute, Attribute ) ]()
    let oldAttributes = synchronizationAttributes(in: old)
    let newAttributes = synchronizationAttributes(in: new)
    let describe: ( Attribute ) -> String = {
      old.groupExternalName + "." + $0.columnNameOrName
    }

    matchUnique(old: oldAttributes, new: newAttributes,
                matchedOld: &matchedOld, matchedNew: &matchedNew,
                same: &same, noun: "column", describe: describe,
                invalid: &invalid,
                where: attributesShareElementID)
    matchUnique(old: oldAttributes, new: newAttributes,
                matchedOld: &matchedOld, matchedNew: &matchedNew,
                same: &same, noun: "column", describe: describe,
                invalid: &invalid,
                where: attributesShareLogicalName)
    matchUnique(old: oldAttributes, new: newAttributes,
                matchedOld: &matchedOld, matchedNew: &matchedNew,
                same: &same, noun: "column", describe: describe,
                invalid: &invalid,
                where: {
                  normalizedSchemaObjectName($0.columnNameOrName)
                    == normalizedSchemaObjectName($1.columnNameOrName)
                })

    return SchemaSyncChangeSet(
      created: newAttributes.indices.compactMap {
        matchedNew.contains($0) ? nil : newAttributes[$0]
      },
      dropped: oldAttributes.indices.compactMap {
        matchedOld.contains($0) ? nil : oldAttributes[$0]
      },
      same: same)
  }

  func synchronizationAttributes(in group: SQLTableGroup) -> [ Attribute ] {
    var attributes = [ Attribute ]()
    var columns = Set<String>()
    for entity in group.sorted(by: { $0.name < $1.name }) {
      for attribute in entity.attributes {
        let column = normalizedSchemaObjectName(attribute.columnNameOrName)
        if columns.insert(column).inserted { attributes.append(attribute) }
      }
    }
    return attributes
  }

  func hasConsistentNullability(for column: String,
                                in group: SQLTableGroup) -> Bool
  {
    let column = normalizedSchemaObjectName(column)
    var expected: Bool?
    for entity in group {
      for attribute in entity.attributes
            where normalizedSchemaObjectName(attribute.columnNameOrName)
                  == column
      {
        let allowsNull = attribute.allowsNull ?? true
        if let expected, expected != allowsNull { return false }
        expected = allowsNull
      }
    }
    return true
  }

  func attributesShareElementID(_ lhs: Attribute, _ rhs: Attribute) -> Bool {
    guard let lhsID = lhs.elementID, let rhsID = rhs.elementID else {
      return false
    }
    return lhsID == rhsID
  }

  func attributesShareLogicalName(_ lhs: Attribute,
                                  _ rhs: Attribute) -> Bool
  {
    if lhs.elementID != nil && rhs.elementID != nil { return false }
    return lhs.name == rhs.name
  }

  func matchUnique<T>(old: [ T ], new: [ T ],
                      matchedOld: inout Set<Int>,
                      matchedNew: inout Set<Int>,
                      same: inout [ ( T, T ) ], noun: String,
                      describe: ( T ) -> String,
                      invalid: inout [ String ],
                      where matches: ( T, T ) -> Bool)
  {
    let oldIndices = old.indices.filter { !matchedOld.contains($0) }
    let newIndices = new.indices.filter { !matchedNew.contains($0) }
    var oldCandidates = [ Int : [ Int ] ]()
    var newCandidates = [ Int : [ Int ] ]()

    for oldIndex in oldIndices {
      oldCandidates[oldIndex] = newIndices.filter {
        matches(old[oldIndex], new[$0])
      }
    }
    for newIndex in newIndices {
      newCandidates[newIndex] = oldIndices.filter {
        matches(old[$0], new[newIndex])
      }
    }

    for oldIndex in oldIndices {
      guard let candidates = oldCandidates[oldIndex] else { continue }
      if candidates.count > 1 {
        invalid.append(
          "ambiguous replacement for \(noun) \(describe(old[oldIndex]))")
        continue
      }
      guard let newIndex = candidates.first,
            let reverse = newCandidates[newIndex] else { continue }
      if reverse.count > 1 {
        invalid.append(
          "ambiguous origin for \(noun) \(describe(new[newIndex]))")
        continue
      }
      guard reverse.first == oldIndex else { continue }
      matchedOld.insert(oldIndex)
      matchedNew.insert(newIndex)
      same.append(( old[oldIndex], new[newIndex] ))
    }
  }

  func synchronizationPlan(old: Model, new: Model) throws
       -> SchemaSynchronizationPlan
  {
    var invalid     = [ String ]()
    var unsupported = [ String ]()
    let tableChanges = tableChangesForSynchronization(
      old: old.entities, new: new.entities, invalid: &invalid)
    var plan = SchemaSynchronizationPlan()

    plan.oldModel = old
    plan.newModel = new
    plan.oldTableNames = Set(old.entities.extractEntityGroups().map {
      $0.groupExternalName
    })
    plan.newTableNames = Set(new.entities.extractEntityGroups().map {
      $0.groupExternalName
    })
    plan.createdTables = tableChanges.created
    plan.droppedTables = tableChanges.dropped

    for group in plan.createdTables {
      validate(group: group, action: "create", invalid: &invalid,
               unsupported: &unsupported)
      if group.groupAttributes.isEmpty {
        invalid.append(
          "cannot create table \(group.groupExternalName) without columns")
      }
      _ = primaryKeyColumns(in: group, invalid: &invalid)
      validatePrimaryKeyNullability(in: group, invalid: &invalid)
      validateForeignKeys(in: group, invalid: &invalid)
      for attribute in group.groupAttributes {
        validateNewColumnDeclarations(
          attribute, in: group, action: "creating", invalid: &invalid,
          unsupported: &unsupported)
      }
    }
    for group in plan.droppedTables {
      validate(group: group, action: "drop", invalid: &invalid,
               unsupported: &unsupported)
    }

    for ( oldGroup, newGroup ) in tableChanges.same {
      guard let newEntity = newGroup.first else {
        invalid.append("cannot synchronize an empty entity group")
        continue
      }

      let oldTable = oldGroup.groupExternalName
      let newTable = newGroup.groupExternalName
      var tableChanged = false

      let oldSchemas = Set(oldGroup.map { $0.schemaName ?? "" })
      let newSchemas = Set(newGroup.map { $0.schemaName ?? "" })
      if oldSchemas != newSchemas {
        unsupported.append(
          "changing the schema of table \(oldTable)")
        tableChanged = true
      }

      if oldTable != newTable {
        tableChanged = true
        if supportsDirectTableRenaming {
          plan.renamedTables.append(
            SchemaTableRename(oldName: oldTable, newName: newTable,
                              entity: newEntity))
        }
        else {
          unsupported.append(
            "renaming table \(oldTable) to \(newTable)")
        }
      }

      let changedAttributes = attributeChangesForSynchronization(
        old: oldGroup, new: newGroup, invalid: &invalid)
      let renamedColumns = Dictionary(uniqueKeysWithValues:
        changedAttributes.same.compactMap { oldAttribute, newAttribute in
          let oldName = oldAttribute.columnNameOrName
          let newName = newAttribute.columnNameOrName
          return oldName == newName ? nil : ( oldName, newName )
        })
      validateColumnRenameTargets(
        renamedColumns, old: oldGroup,
        created: changedAttributes.created, unsupported: &unsupported)
      let oldPrimaryKey = primaryKeyColumns(in: oldGroup, invalid: &invalid)
                          .map { renamedColumns[$0] ?? $0 }
      let newPrimaryKey = primaryKeyColumns(in: newGroup, invalid: &invalid)
      if oldPrimaryKey != newPrimaryKey {
        unsupported.append("changing the primary key of table \(newTable)")
      }

      for attribute in changedAttributes.dropped {
        tableChanged = true
        if supportsDirectColumnDeletion {
          plan.droppedColumns.append(
            SchemaColumnChange(table: newTable, entity: newEntity,
                               attribute: attribute))
        }
        else {
          unsupported.append(
            "dropping column \(oldTable).\(attribute.columnNameOrName)")
        }
      }

      for attribute in changedAttributes.created {
        tableChanged = true
        let column = attribute.columnNameOrName
        validateNewColumnDeclarations(
          attribute, in: newGroup, action: "adding", invalid: &invalid,
          unsupported: &unsupported)
        if !supportsDirectColumnInsertion {
          unsupported.append("adding column \(newTable).\(column)")
        }
        else if !(attribute.allowsNull ?? true) {
          unsupported.append(
            "adding required column \(newTable).\(column) without backfill")
        }
        else {
          plan.addedColumns.append(
            SchemaColumnChange(table: newTable, entity: newEntity,
                               attribute: attribute))
        }
      }

      for ( oldAttribute, newAttribute ) in changedAttributes.same {
        var hasUnsupportedChange = false
        if (oldAttribute.isAutoIncrement ?? false)
           != (newAttribute.isAutoIncrement ?? false)
        {
          unsupported.append(
            "changing autoincrement of \(newTable)." +
            newAttribute.columnNameOrName)
          hasUnsupportedChange = true
        }
        if !ZeeQL.eq(oldAttribute.defaultValue,
                     newAttribute.defaultValue)
        {
          unsupported.append(
            "changing the default of \(newTable)." +
            newAttribute.columnNameOrName)
          hasUnsupportedChange = true
        }
        if oldAttribute.collation != newAttribute.collation {
          unsupported.append(
            "changing the collation of \(newTable)." +
            newAttribute.columnNameOrName)
          hasUnsupportedChange = true
        }
        if oldAttribute.derivationExpression
           != newAttribute.derivationExpression
        {
          unsupported.append(
            "changing the derivation of \(newTable)." +
            newAttribute.columnNameOrName)
          hasUnsupportedChange = true
        }
        if hasUnsupportedChange { tableChanged = true }

        guard let changes = attributeChanges(new: newAttribute,
                                             since: oldAttribute) else
        {
          continue
        }
        tableChanged = true
        let pair = SchemaColumnPair(table: newTable, entity: newEntity,
                                    oldAttribute: oldAttribute,
                                    newAttribute: newAttribute)

        if let ( oldName, newName ) = changes.name {
          if supportsDirectColumnRenaming {
            plan.renamedColumns.append(
              SchemaColumnRename(table: newTable, entity: newEntity,
                                 oldAttribute: oldAttribute,
                                 oldName: oldName, newName: newName))
          }
          else {
            unsupported.append(
              "renaming column \(newTable).\(oldName) to \(newName)")
          }
        }
        if changes.externalType != nil {
          validateColumnType(newAttribute, table: newTable,
                             invalid: &invalid)
          if supportsDirectColumnCoercion {
            plan.changedTypes.append(pair)
          }
          else {
            unsupported.append(
              "changing the type of \(newTable)." +
              newAttribute.columnNameOrName)
          }
        }
        if changes.nullability != nil {
          if supportsDirectColumnNullRuleModification {
            plan.changedNullability.append(pair)
          }
          else {
            unsupported.append(
              "changing nullability of \(newTable)." +
              newAttribute.columnNameOrName)
          }
        }
      }

      let foreignKeyChanges =
        newGroup.calculateForeignKeyConstraintChanges(since: oldGroup)
      if reflectsForeignKeyConstraintNames {
        let oldForeignKeys = oldGroup.groupForeignKeys
        let newForeignKeys = newGroup.groupForeignKeys
        for oldForeignKey in oldForeignKeys {
          guard let newForeignKey = newForeignKeys.first(where: {
            $0 == oldForeignKey
          }) else { continue }
          let oldName = oldForeignKey.relationship.constraintName
          let newName = newForeignKey.relationship.constraintName
          let normalizedOldName = oldName?.isEmpty == false ? oldName : nil
          let normalizedNewName = newName?.isEmpty == false ? newName : nil
          if normalizedOldName != normalizedNewName {
            unsupported.append(
              "renaming a foreign key on table \(newTable)")
            tableChanged = true
          }
        }
      }
      if !foreignKeyChanges.created.isEmpty
         || !foreignKeyChanges.dropped.isEmpty
      {
        tableChanged = true
      }
      for foreignKey in foreignKeyChanges.dropped {
        if !supportsDirectForeignKeyModification {
          unsupported.append("dropping a foreign key from \(oldTable)")
        }
        else if foreignKey.relationship.constraintName?.isEmpty ?? true {
          invalid.append(
            "cannot drop unnamed foreign key from table \(oldTable)")
        }
        else {
          plan.droppedForeignKeys.append(
            SchemaForeignKeyChange(table: oldTable,
                                   foreignKey: foreignKey))
        }
      }
      for foreignKey in foreignKeyChanges.created {
        validateForeignKey(foreignKey.relationship, table: newTable,
                           invalid: &invalid)
        if !supportsDirectForeignKeyModification {
          unsupported.append("adding a foreign key to \(newTable)")
        }
        else {
          plan.addedForeignKeys.append(
            SchemaForeignKeyChange(table: newTable,
                                   foreignKey: foreignKey))
        }
      }

      if tableChanged {
        validate(group: oldGroup, action: "alter", invalid: &invalid,
                 unsupported: &unsupported)
        validate(group: newGroup, action: "alter", invalid: &invalid,
                 unsupported: &unsupported)
      }
    }

    validateTableRenameTargets(plan.renamedTables,
                               dropped: plan.droppedTables,
                               created: plan.createdTables,
                               unsupported: &unsupported)
    plan.droppedTables = dropOrder(for: plan.droppedTables,
                                   unsupported: &unsupported)
    sort(plan: &plan)

    if !invalid.isEmpty {
      throw SchemaSynchronizationError.invalidModel(
        Array(Set(invalid)).sorted())
    }
    if !unsupported.isEmpty {
      throw SchemaSynchronizationError.unsupportedChanges(
        Array(Set(unsupported)).sorted())
    }
    return plan
  }

  func validate(group: SQLTableGroup, action: String,
                invalid: inout [ String ],
                unsupported: inout [ String ])
  {
    guard !group.isEmpty else {
      invalid.append("cannot \(action) an empty entity group")
      return
    }
    let table = group.groupExternalName
    for entity in group {
      if let schema = entity.schemaName, !schema.isEmpty {
        unsupported.append(
          "\(action) of schema-qualified table \(schema).\(table)")
      }
    }
    unsupported.append(contentsOf:
      synchronizationIssuesForTable(named: table))
  }

  func validateForeignKeys(in group: SQLTableGroup,
                           invalid: inout [ String ])
  {
    var constraintNames = Set<String>()
    for entity in group {
      for relationship in entity.relationships {
        guard relationship.isForeignKeyRelationship else { continue }
        if let name = relationship.constraintName, !name.isEmpty {
          let key = normalizedSchemaObjectName(name)
          if !constraintNames.insert(key).inserted {
            invalid.append(
              "duplicate foreign key name \(name) in " +
              group.groupExternalName)
          }
        }
        validateForeignKey(relationship, table: group.groupExternalName,
                           invalid: &invalid)
      }
    }
  }

  func validateForeignKey(_ relationship: Relationship, table: String,
                          invalid: inout [ String ])
  {
    guard let destination = relationship.destinationEntity else {
      invalid.append(
        "foreign key \(table).\(relationship.name) has no destination entity")
      return
    }
    let source = relationship.entity
    let expression = adaptor.expressionFactory.createExpression(source)
    if expression.sqlForForeignKeyConstraint(relationship) == nil {
      invalid.append(
        "cannot render foreign key \(table).\(relationship.name)")
      return
    }
    let name: String
    if let constraintName = relationship.constraintName,
       !constraintName.isEmpty
    {
      name = constraintName
    }
    else {
      name = relationship.name
    }
    if name == "*" {
      invalid.append("cannot use * as a foreign key name in \(table)")
    }

    var ignored = [ String ]()
    let destinationGroup = [ destination ]
    let primaryKey = primaryKeyColumns(in: destinationGroup,
                                       invalid: &ignored)
    let sourceAttributes = relationship.joins.compactMap {
      $0.source(in: source)
    }
    let sourceColumns = sourceAttributes.map { $0.columnNameOrName }
    let referencedColumns = relationship.joins.compactMap {
      $0.destination(in: destination)?.columnNameOrName
    }
    let joinCount = relationship.joins.count
    if sourceColumns.count != joinCount
       || referencedColumns.count != joinCount
       || Set(sourceColumns).count != joinCount
       || Set(referencedColumns).count != joinCount
       || referencedColumns.count != primaryKey.count
       || Set(referencedColumns) != Set(primaryKey)
    {
      invalid.append(
        "foreign key \(table).\(relationship.name) does not reference " +
        "the destination primary key")
    }
    for ( action, rule ) in [
      ( "update", relationship.updateRule ),
      ( "delete", relationship.deleteRule )
    ] {
      switch rule {
        case .nullify?:
          for attribute in sourceAttributes
                where attribute.allowsNull == false
          {
            invalid.append(
              "foreign key \(table).\(relationship.name) uses SET NULL " +
              "on required column \(attribute.columnNameOrName) for \(action)")
          }
        case .applyDefault?:
          for attribute in sourceAttributes
                where attribute.allowsNull == false
                   && attribute.defaultValue == nil
          {
            invalid.append(
              "foreign key \(table).\(relationship.name) uses SET DEFAULT " +
              "without a default on required column " +
              "\(attribute.columnNameOrName) for \(action)")
          }
        default:
          break
      }
    }
  }

  func validateNewColumnDeclarations(_ attribute: Attribute,
                                     in group: SQLTableGroup,
                                     action: String,
                                     invalid: inout [ String ],
                                     unsupported: inout [ String ])
  {
    let table = group.groupExternalName
    let column = normalizedSchemaObjectName(attribute.columnNameOrName)
    let declarations = group.flatMap { entity in
      entity.attributes.filter {
        normalizedSchemaObjectName($0.columnNameOrName) == column
      }
    }
    guard let first = declarations.first else { return }
    for declaration in declarations {
      validateNewColumn(declaration, table: table, action: action,
                        invalid: &invalid, unsupported: &unsupported)
      if !newColumnDefinitionsMatch(first, declaration) {
        invalid.append(
          "inconsistent definitions for new column \(table)." +
          attribute.columnNameOrName)
      }
    }
  }

  func newColumnDefinitionsMatch(_ lhs: Attribute,
                                 _ rhs: Attribute) -> Bool
  {
    return columnTypesAreEquivalent(lhs, rhs)
        && (lhs.allowsNull ?? true) == (rhs.allowsNull ?? true)
        && (lhs.isAutoIncrement ?? false) == (rhs.isAutoIncrement ?? false)
        && ZeeQL.eq(lhs.defaultValue, rhs.defaultValue)
        && lhs.collation == rhs.collation
        && lhs.derivationExpression == rhs.derivationExpression
  }

  func validateNewColumn(_ attribute: Attribute, table: String,
                         action: String,
                         invalid: inout [ String ],
                         unsupported: inout [ String ])
  {
    let column = table + "." + attribute.columnNameOrName
    validateColumnType(attribute, table: table, invalid: &invalid)
    if attribute.defaultValue != nil {
      unsupported.append("\(action) column \(column) with a default")
    }
    if attribute.isAutoIncrement ?? false {
      unsupported.append("\(action) autoincrement column \(column)")
    }
    if attribute.collation != nil {
      unsupported.append("\(action) column \(column) with a collation")
    }
    if attribute.derivationExpression != nil {
      unsupported.append("\(action) derived column \(column)")
    }
  }

  func validatePrimaryKeyNullability(in group: SQLTableGroup,
                                     invalid: inout [ String ])
  {
    guard let entity = group.first else { return }
    for name in entity.primaryKeyAttributeNames ?? [] {
      guard let attribute = entity[attribute: name],
            attribute.allowsNull != false else { continue }
      invalid.append(
        "primary key column \(group.groupExternalName)." +
        "\(attribute.columnNameOrName) allows null")
    }
  }

  func validateColumnType(_ attribute: Attribute, table: String,
                          invalid: inout [ String ])
  {
    let expression = adaptor.expressionFactory.createExpression(nil)
    let type = expression.columnTypeStringForAttribute(attribute)
    guard columnTypeIsSafeForSynchronization(type) else {
      invalid.append(
        "unsafe column type for \(table).\(attribute.columnNameOrName)")
      return
    }
  }

  func columnTypeIsSafeForSynchronization(_ type: String) -> Bool {
    guard !type.isEmpty else { return false }

    var depth = 0
    var quoteEnd: Character?
    var word = ""
    var words = [ String ]()
    func finishWord() {
      guard !word.isEmpty else { return }
      words.append(word.uppercased())
      word.removeAll(keepingCapacity: true)
    }

    var index = type.startIndex
    while index < type.endIndex {
      let character = type[index]
      let nextIndex = type.index(after: index)
      let next = nextIndex < type.endIndex ? type[nextIndex] : nil
      if let end = quoteEnd {
        if character == end {
          if next == end {
            index = type.index(after: nextIndex)
            continue
          }
          quoteEnd = nil
        }
        index = nextIndex
        continue
      }
      switch character {
        case "\"", "'", "`":
          finishWord()
          quoteEnd = character
        case "[":
          finishWord()
          quoteEnd = "]"
        case "(":
          finishWord()
          depth += 1
        case ")":
          finishWord()
          guard depth > 0 else { return false }
          depth -= 1
        case ",":
          finishWord()
          if depth == 0 { return false }
        case ";":
          return false
        case "-" where next == "-":
          return false
        case "/" where next == "*":
          return false
        case "*" where next == "/":
          return false
        default:
          if depth == 0 && (character.isLetter || character == "_") {
            word.append(character)
          }
          else {
            finishWord()
          }
      }
      index = nextIndex
    }
    finishWord()
    guard depth == 0, quoteEnd == nil else { return false }
    let constraintWords: Set<String> = [
      "AS", "AUTOINCREMENT", "AUTO_INCREMENT", "CHECK", "COLLATE",
      "COMPRESSION", "CONSTRAINT", "DEFAULT", "GENERATED", "IDENTITY",
      "NOT", "NULL", "PRIMARY", "REFERENCES", "STORAGE", "STORED",
      "UNIQUE", "USING", "VIRTUAL"
    ]
    return constraintWords.isDisjoint(with: words)
  }

  func validateTableRenameTargets(_ renames: [ SchemaTableRename ],
                                  dropped: [ SQLTableGroup ],
                                  created: [ SQLTableGroup ],
                                  unsupported: inout [ String ])
  {
    let sources = Set(renames.map {
      normalizedSchemaObjectName($0.oldName)
    })
    let dropped = Set(dropped.map {
      normalizedSchemaObjectName($0.groupExternalName)
    })
    let created = Set(created.map {
      normalizedSchemaObjectName($0.groupExternalName)
    })
    for rename in renames {
      let oldName = normalizedSchemaObjectName(rename.oldName)
      let newName = normalizedSchemaObjectName(rename.newName)
      if sources.contains(newName) || dropped.contains(newName) {
        unsupported.append(
          "renaming table \(rename.oldName) to occupied name " +
          rename.newName)
      }
      if created.contains(oldName) {
        unsupported.append(
          "reusing renamed table name \(rename.oldName)")
      }
    }
  }

  func validateColumnRenameTargets(_ renames: [ String : String ],
                                   old: SQLTableGroup,
                                   created: [ Attribute ],
                                   unsupported: inout [ String ])
  {
    let oldColumns = Set(old.groupAttributes.map {
      normalizedSchemaObjectName($0.columnNameOrName)
    })
    let createdColumns = Set(created.map {
      normalizedSchemaObjectName($0.columnNameOrName)
    })
    for ( source, target ) in renames {
      let oldName = normalizedSchemaObjectName(source)
      let newName = normalizedSchemaObjectName(target)
      if oldColumns.contains(newName) {
        unsupported.append(
          "renaming column \(old.groupExternalName).\(source) to " +
          "occupied name \(target)")
      }
      if createdColumns.contains(oldName) {
        unsupported.append(
          "reusing renamed column name \(old.groupExternalName).\(source)")
      }
    }
  }

  func primaryKeyColumns(in group: SQLTableGroup,
                         invalid: inout [ String ]) -> [ String ]
  {
    guard let entity = group.first,
          let names = entity.primaryKeyAttributeNames else { return [] }
    var columns = [ String ]()
    columns.reserveCapacity(names.count)
    for name in names {
      guard let attribute = entity[attribute: name] else {
        invalid.append(
          "primary key attribute \(entity.name).\(name) does not exist")
        continue
      }
      columns.append(attribute.columnNameOrName)
    }
    return columns
  }

  func attributeChanges(new: Attribute, since old: Attribute)
       -> SQLAttributeChange?
  {
    var change = SQLAttributeChange()
    let oldName = old.columnNameOrName
    let newName = new.columnNameOrName
    if oldName != newName { change.name = ( oldName, newName ) }
    if (old.allowsNull ?? true) != (new.allowsNull ?? true) {
      change.nullability = new.allowsNull ?? true
    }
    if !columnTypesAreEquivalent(old, new) {
      let expression = adaptor.expressionFactory.createExpression(nil)
      change.externalType = expression.columnTypeStringForAttribute(new)
    }
    return change.hasChanges ? change : nil
  }

  func statements(for plan: SchemaSynchronizationPlan) throws
       -> [ SQLExpression ]
  {
    var statements = [ SQLExpression ]()
    for change in plan.droppedForeignKeys {
      statements.append(try dropForeignKeyStatement(change))
    }
    for group in plan.droppedTables {
      statements.append(contentsOf: dropTableStatementsForEntityGroup(group))
    }
    for rename in plan.renamedTables {
      statements.append(renameTableStatement(rename))
    }
    for change in plan.droppedColumns {
      statements.append(dropColumnStatement(change))
    }
    for rename in plan.renamedColumns {
      statements.append(renameColumnStatement(rename))
    }
    for change in plan.changedTypes {
      statements.append(changeColumnTypeStatement(change))
    }
    for change in plan.changedNullability {
      statements.append(changeColumnNullabilityStatement(change))
    }
    for change in plan.addedColumns {
      statements.append(addColumnStatement(change))
    }
    if !plan.createdTables.isEmpty {
      let options = SchemaGenerationOptions()
      options.dropTables = false
      options.createTables = true
      options.embedConstraintsInTable = true
      let entities = plan.createdTables.flatMap { $0 }
      statements.append(contentsOf:
        schemaCreationStatementsForEntities(entities, options: options))
    }
    for change in plan.addedForeignKeys {
      statements.append(try addForeignKeyStatement(change))
    }
    return statements
  }

  func dropForeignKeyStatement(_ change: SchemaForeignKeyChange) throws
       -> SQLExpression
  {
    let relationship = change.foreignKey.relationship
    guard let name = relationship.constraintName, !name.isEmpty else {
      throw SchemaSynchronizationError.invalidModel([
        "cannot drop unnamed foreign key from table \(change.table)"
      ])
    }
    let expression = adaptor.expressionFactory.createExpression(
      relationship.entity)
    expression.statement = "ALTER TABLE " + quoted(change.table, expression)
                         + " DROP CONSTRAINT " + quoted(name, expression)
    return expression
  }

  func addForeignKeyStatement(_ change: SchemaForeignKeyChange) throws
       -> SQLExpression
  {
    let relationship = change.foreignKey.relationship
    let expression = adaptor.expressionFactory.createExpression(
      relationship.entity)
    guard let foreignKey = expression.sqlForForeignKeyConstraint(relationship)
     else {
      throw SchemaSynchronizationError.invalidModel([
        "cannot render foreign key \(change.table).\(relationship.name)"
      ])
     }
    let name = expectedAddedForeignKeyName(change.foreignKey)
    guard !name.isEmpty else {
      throw SchemaSynchronizationError.invalidModel([
        "foreign key on table \(change.table) has no name"
      ])
    }
    expression.statement = "ALTER TABLE " + quoted(change.table, expression)
                         + " ADD CONSTRAINT " + quoted(name, expression)
                         + " " + foreignKey
    return expression
  }

  func renameTableStatement(_ change: SchemaTableRename) -> SQLExpression {
    let expression = adaptor.expressionFactory.createExpression(change.entity)
    expression.statement = "ALTER TABLE "
                         + quoted(change.oldName, expression) + " RENAME TO "
                         + quoted(change.newName, expression)
    return expression
  }

  func dropColumnStatement(_ change: SchemaColumnChange) -> SQLExpression {
    let expression = adaptor.expressionFactory.createExpression(change.entity)
    expression.statement = "ALTER TABLE " + quoted(change.table, expression)
                         + " DROP COLUMN "
                         + quoted(change.attribute.columnNameOrName, expression)
    return expression
  }

  func renameColumnStatement(_ change: SchemaColumnRename) -> SQLExpression {
    let expression = adaptor.expressionFactory.createExpression(change.entity)
    expression.statement = "ALTER TABLE " + quoted(change.table, expression)
                         + " RENAME COLUMN "
                         + quoted(change.oldName, expression) + " TO "
                         + quoted(change.newName, expression)
    return expression
  }

  func changeColumnTypeStatement(_ change: SchemaColumnPair) -> SQLExpression {
    let expression = adaptor.expressionFactory.createExpression(change.entity)
    let column = quoted(change.newAttribute.columnNameOrName, expression)
    let type = expression.columnTypeStringForAttribute(change.newAttribute)
    expression.statement = "ALTER TABLE " + quoted(change.table, expression)
                         + " ALTER COLUMN " + column + " TYPE " + type
    return expression
  }

  func changeColumnNullabilityStatement(_ change: SchemaColumnPair)
       -> SQLExpression
  {
    let expression = adaptor.expressionFactory.createExpression(change.entity)
    let column = quoted(change.newAttribute.columnNameOrName, expression)
    let action = (change.newAttribute.allowsNull ?? true)
               ? " DROP NOT NULL" : " SET NOT NULL"
    expression.statement = "ALTER TABLE " + quoted(change.table, expression)
                         + " ALTER COLUMN " + column + action
    return expression
  }

  func addColumnStatement(_ change: SchemaColumnChange) -> SQLExpression {
    let expression = adaptor.expressionFactory.createExpression(change.entity)
    expression.addCreateClauseForAttribute(change.attribute)
    expression.statement = "ALTER TABLE " + quoted(change.table, expression)
                         + " ADD COLUMN " + expression.listString
    return expression
  }

  func quoted(_ name: String, _ expression: SQLExpression) -> String {
    return expression.sqlStringFor(schemaObjectName: name)
  }

  func verifyPreconditions(of plan: SchemaSynchronizationPlan,
                           on channel: AdaptorChannel) throws
  {
    let needsAllTables = !plan.droppedTables.isEmpty
                      || !plan.droppedForeignKeys.isEmpty
                      || !plan.addedForeignKeys.isEmpty
                      || plan.createdTables.contains {
                           !$0.groupForeignKeys.isEmpty
                         }
    let snapshot = try schemaSnapshot(
      describing: plan.sourceTableNames, includeAllTables: needsAllTables,
      on: channel)
    var issues = [ String ]()

    for group in plan.createdTables {
      let table = group.groupExternalName
      if snapshot.tableNames.contains(table) {
        issues.append("table \(table) already exists")
      }
    }
    for group in plan.droppedTables {
      let table = group.groupExternalName
      if !snapshot.tableNames.contains(table) {
        issues.append("table \(table) does not exist")
      }
    }
    for rename in plan.renamedTables {
      if !snapshot.tableNames.contains(rename.oldName) {
        issues.append("table \(rename.oldName) does not exist")
      }
      if snapshot.tableNames.contains(rename.newName)
      {
        issues.append("rename target table \(rename.newName) already exists")
      }
    }

    if !plan.droppedTables.isEmpty {
      try verifyDropScope(of: plan, in: snapshot, on: channel,
                          issues: &issues)
    }
    if let oldModel = plan.oldModel {
      for table in plan.retainedModifiedTableNames.sorted() {
        let oldTable = plan.oldTableName(for: table)
        verifyModeledTable(oldModel[entityGroup: oldTable], named: oldTable,
                           in: snapshot, prefix: "old", issues: &issues)
      }
    }

    for change in plan.droppedColumns {
      let table = plan.oldTableName(for: change.table)
      verifyOldColumn(change.attribute, in: table, snapshot: snapshot,
                      issues: &issues)
    }
    for rename in plan.renamedColumns {
      let table = plan.oldTableName(for: rename.table)
      verifyOldColumn(rename.oldAttribute, in: table, snapshot: snapshot,
                      issues: &issues)
      rejectExistingColumn(rename.newName, in: table, snapshot: snapshot,
                           issues: &issues)
    }
    for change in plan.changedTypes {
      let table = plan.oldTableName(for: change.table)
      verifyOldColumn(change.oldAttribute, in: table, snapshot: snapshot,
                      issues: &issues)
    }
    for change in plan.changedNullability {
      let table = plan.oldTableName(for: change.table)
      verifyOldColumn(change.oldAttribute, in: table, snapshot: snapshot,
                      issues: &issues)
    }
    for change in plan.addedColumns {
      let table = plan.oldTableName(for: change.table)
      let column = change.attribute.columnNameOrName
      rejectExistingColumn(column, in: table, snapshot: snapshot,
                           issues: &issues)
    }

    verifyForeignKeyPreconditions(of: plan, in: snapshot, issues: &issues)
    issues.append(contentsOf: try preflightSynchronizationIssues(
      modifyingTables: plan.modifyingTableNames,
      droppingTables: plan.droppedTableNames, on: channel))
    guard issues.isEmpty else {
      throw SchemaSynchronizationError.preconditionFailed(
        Array(Set(issues)).sorted())
    }
  }

  func verifyEffects(of plan: SchemaSynchronizationPlan,
                     on channel: AdaptorChannel) throws
  {
    let needsAllTables = !plan.droppedForeignKeys.isEmpty
                      || !plan.addedForeignKeys.isEmpty
                      || !plan.createdTables.isEmpty
    let snapshot = try schemaSnapshot(
      describing: plan.targetTableNames, includeAllTables: needsAllTables,
      on: channel)
    var issues = [ String ]()

    for group in plan.droppedTables {
      let table = group.groupExternalName
      if snapshot.tableNames.contains(table) {
        issues.append("dropped table \(table) still exists")
      }
    }
    for rename in plan.renamedTables {
      if snapshot.tableNames.contains(rename.oldName) {
        issues.append("renamed table \(rename.oldName) still exists")
      }
      if !snapshot.tableNames.contains(rename.newName) {
        issues.append("renamed table \(rename.newName) does not exist")
      }
    }
    if let newModel = plan.newModel {
      for table in plan.retainedModifiedTableNames.sorted() {
        verifyModeledTable(newModel[entityGroup: table], named: table,
                           in: snapshot, prefix: "new", issues: &issues)
      }
    }
    for group in plan.createdTables {
      verifyCreatedTable(group, in: snapshot, issues: &issues)
    }
    for change in plan.droppedColumns {
      let column = change.attribute.columnNameOrName
      rejectExistingColumn(column, in: change.table, snapshot: snapshot,
                           issues: &issues, prefix: "dropped")
    }
    for rename in plan.renamedColumns {
      rejectExistingColumn(rename.oldName, in: rename.table,
                           snapshot: snapshot, issues: &issues,
                           prefix: "renamed")
      verifyColumn(rename.oldAttribute, in: rename.table,
                   checkType: false, checkNullability: false,
                   snapshot: snapshot, issues: &issues,
                   columnName: rename.newName)
    }
    for change in plan.changedTypes {
      verifyColumn(change.newAttribute, in: change.table,
                   checkType: true, checkNullability: true,
                   snapshot: snapshot, issues: &issues)
    }
    for change in plan.changedNullability {
      verifyColumn(change.newAttribute, in: change.table,
                   checkType: true, checkNullability: true,
                   snapshot: snapshot, issues: &issues)
    }
    for change in plan.addedColumns {
      verifyColumn(change.attribute, in: change.table,
                   checkType: true, checkNullability: true,
                   snapshot: snapshot, issues: &issues)
    }
    verifyForeignKeyEffects(of: plan, in: snapshot, issues: &issues)

    guard issues.isEmpty else {
      throw SchemaSynchronizationError.verificationFailed(
        Array(Set(issues)).sorted())
    }
  }

  func schemaSnapshot(describing tables: Set<String>,
                      includeAllTables: Bool,
                      on channel: AdaptorChannel) throws -> SchemaSnapshot
  {
    let tableNames = Set(try channel.describeTableNames())
    let names = includeAllTables ? tableNames : tables.intersection(tableNames)
    let entities = try channel.describeEntitiesWithTableNames(names.sorted())
    let model = Model(entities: entities)
    model.connectRelationships()
    return SchemaSnapshot(tableNames: tableNames, model: model)
  }

  @discardableResult
  func requireColumn(_ column: String, in table: String,
                     snapshot: SchemaSnapshot,
                     issues: inout [ String ]) -> Attribute?
  {
    guard snapshot.tableNames.contains(table) else {
      issues.append("table \(table) does not exist")
      return nil
    }
    guard let attribute = snapshot.attribute(named: column, in: table) else {
      issues.append("column \(table).\(column) does not exist")
      return nil
    }
    return attribute
  }

  func rejectExistingColumn(_ column: String, in table: String,
                            snapshot: SchemaSnapshot,
                            issues: inout [ String ],
                            prefix: String = "target")
  {
    guard snapshot.tableNames.contains(table) else {
      issues.append("table \(table) does not exist")
      return
    }
    if snapshot.attribute(named: column, in: table) != nil {
      issues.append("\(prefix) column \(table).\(column) already exists")
    }
  }

  func verifyColumn(_ expected: Attribute, in table: String,
                    checkType: Bool, checkNullability: Bool,
                    snapshot: SchemaSnapshot, issues: inout [ String ],
                    columnName: String? = nil)
  {
    let column = columnName ?? expected.columnNameOrName
    guard let actual = requireColumn(column, in: table, snapshot: snapshot,
                                     issues: &issues) else { return }
    if checkType && !columnTypesMatchForSchemaVerification(
      actual, expected)
    {
      issues.append("type of \(table).\(column) does not match the model")
    }
    if checkNullability, let actualNull = actual.allowsNull,
       (expected.allowsNull ?? true) != actualNull
    {
      issues.append(
        "nullability of \(table).\(column) does not match the model")
    }
  }

  func verifyOldColumn(_ expected: Attribute, in table: String,
                       checkNullability: Bool = true,
                       snapshot: SchemaSnapshot,
                       issues: inout [ String ])
  {
    let column = expected.columnNameOrName
    guard let actual = requireColumn(column, in: table, snapshot: snapshot,
                                     issues: &issues) else { return }
    if !columnTypesMatchForSchemaVerification(actual, expected) {
      issues.append("type of \(table).\(column) is stale")
    }
    if checkNullability, let actualNull = actual.allowsNull,
       (expected.allowsNull ?? true) != actualNull
    {
      issues.append("nullability of \(table).\(column) is stale")
    }
  }

  func verifyCreatedTable(_ group: SQLTableGroup,
                          in snapshot: SchemaSnapshot,
                          issues: inout [ String ])
  {
    let table = group.groupExternalName
    guard snapshot.tableNames.contains(table) else {
      issues.append("created table \(table) does not exist")
      return
    }
    var ignored = [ String ]()
    let primaryKeyColumns = primaryKeyColumns(in: group, invalid: &ignored)
    let primaryKey = Set(primaryKeyColumns)
    let expectedColumns = Set(group.groupAttributes.map {
      $0.columnNameOrName
    })
    let actualColumns = Set(snapshot.group(named: table).groupAttributes.map {
      $0.columnNameOrName
    })
    if expectedColumns != actualColumns {
      issues.append("columns of created table \(table) do not match")
    }
    let actualPrimaryKey = self.primaryKeyColumns(
      in: snapshot.group(named: table), invalid: &ignored)
    if primaryKeyColumns != actualPrimaryKey {
      issues.append("primary key of created table \(table) does not match")
    }
    for attribute in group.groupAttributes {
      verifyColumn(attribute, in: table, checkType: true,
                   checkNullability:
                     !primaryKey.contains(attribute.columnNameOrName),
                   snapshot: snapshot, issues: &issues)
    }
    let expectedForeignKeys = group.groupForeignKeys
    let actualForeignKeys = snapshot.group(named: table).groupForeignKeys
    let foreignKeysMatch = expectedForeignKeys.count == actualForeignKeys.count
      && expectedForeignKeys.allSatisfy { expected in
        actualForeignKeys.contains { actual in
          reflectedForeignKey(actual, matches: expected,
                              expectedName:
                                expected.relationship.constraintName)
        }
      }
    if !foreignKeysMatch {
      issues.append("foreign keys of created table \(table) do not match")
    }
  }

  func verifyModeledTable(_ group: SQLTableGroup, named table: String,
                          in snapshot: SchemaSnapshot, prefix: String,
                          issues: inout [ String ])
  {
    guard snapshot.tableNames.contains(table) else {
      issues.append("\(prefix) table \(table) does not exist")
      return
    }
    var ignored = [ String ]()
    let expectedPrimaryKey = primaryKeyColumns(in: group, invalid: &ignored)
    let actualGroup = snapshot.group(named: table)
    let actualPrimaryKey = primaryKeyColumns(in: actualGroup,
                                             invalid: &ignored)
    if expectedPrimaryKey != actualPrimaryKey {
      issues.append("\(prefix) primary key of table \(table) does not match")
    }
    let primaryKey = Set(expectedPrimaryKey)
    for attribute in synchronizationAttributes(in: group) {
      let column = attribute.columnNameOrName
      verifyColumn(
        attribute, in: table, checkType: true,
        checkNullability: !primaryKey.contains(column)
                       && hasConsistentNullability(for: column, in: group),
        snapshot: snapshot, issues: &issues)
    }
  }

  func verifyDropScope(of plan: SchemaSynchronizationPlan,
                       in snapshot: SchemaSnapshot,
                       on channel: AdaptorChannel,
                       issues: inout [ String ]) throws
  {
    let actualTables = Set(snapshot.tableNames.filter {
      !isSystemTableForSynchronization($0)
    })
    let unmodeled = actualTables.subtracting(plan.oldTableNames)
    if !unmodeled.isEmpty {
      issues.append("cannot safely drop tables with unmodeled tables: " +
                    unmodeled.sorted().joined(separator: ", "))
    }

    for group in plan.droppedTables {
      let table = group.groupExternalName
      guard snapshot.tableNames.contains(table) else { continue }
      let attributes = synchronizationAttributes(in: group)
      let expectedColumns = Set(attributes.map {
        $0.columnNameOrName
      })
      let actualGroup = snapshot.group(named: table)
      let reflectedColumns = Set(actualGroup.groupAttributes.map {
        $0.columnNameOrName
      })
      let actualColumns = try columnNamesForVerification(
        in: table, on: channel) ?? reflectedColumns
      if expectedColumns != actualColumns {
        issues.append("cannot safely drop partially modeled table \(table)")
        continue
      }

      var ignored = [ String ]()
      let expectedPrimaryKey = primaryKeyColumns(in: group, invalid: &ignored)
      let actualPrimaryKey = primaryKeyColumns(in: actualGroup,
                                               invalid: &ignored)
      if expectedPrimaryKey != actualPrimaryKey {
        issues.append("primary key of table \(table) is stale")
      }
      if group.groupForeignKeys != actualGroup.groupForeignKeys {
        issues.append("foreign keys of table \(table) are stale")
      }
      let primaryKey = Set(expectedPrimaryKey)
      for attribute in attributes {
        verifyOldColumn(
          attribute, in: table,
          checkNullability: !primaryKey.contains(attribute.columnNameOrName),
          snapshot: snapshot, issues: &issues)
      }
    }

    for group in snapshot.model.entities.extractEntityGroups() {
      let source = group.groupExternalName
      guard !plan.droppedTableNames.contains(source) else { continue }
      for foreignKey in group.groupForeignKeys
            where plan.droppedTableNames.contains(
              foreignKey.destinationTableName)
      {
        let hasDrop = plan.droppedForeignKeys.contains {
          $0.table == source
            && foreignKeysShareStructure($0.foreignKey, foreignKey)
        }
        if !hasDrop {
          issues.append(
            "retained table \(source) references a table being dropped")
        }
      }
    }
  }

  func verifyForeignKeyPreconditions(of plan: SchemaSynchronizationPlan,
                                     in snapshot: SchemaSnapshot,
                                     issues: inout [ String ])
  {
    let createdTables = Set(plan.createdTables.map { $0.groupExternalName })
    for group in plan.createdTables {
      for foreignKey in group.groupForeignKeys {
        verifyForeignKeyDestination(
          foreignKey, plan: plan, createdTables: createdTables,
          snapshot: snapshot, issues: &issues)
      }
    }
    for change in plan.droppedForeignKeys {
      let actual = snapshot.group(named: change.table).groupForeignKeys
      let name = change.foreignKey.relationship.constraintName
      if !actual.contains(where: {
        reflectedForeignKey($0, matches: change.foreignKey,
                            expectedName: name)
      }) {
        issues.append("foreign key on \(change.table) does not exist")
      }
    }
    for change in plan.addedForeignKeys {
      verifyForeignKeyDestination(
        change.foreignKey, plan: plan, createdTables: createdTables,
        snapshot: snapshot, issues: &issues)
      let table = plan.oldTableName(for: change.table)
      let actual = snapshot.group(named: table).groupForeignKeys
      let hasUnreplacedForeignKey = actual.contains { existing in
        guard foreignKeysShareStructure(existing, change.foreignKey)
         else { return false }
        return !plan.droppedForeignKeys.contains { dropped in
          guard dropped.table == table else { return false }
          return reflectedForeignKey(
            existing, matches: dropped.foreignKey,
            expectedName: dropped.foreignKey.relationship.constraintName)
        }
      }
      if hasUnreplacedForeignKey {
        issues.append("foreign key on \(table) already exists")
      }
    }
  }

  func reflectedForeignKey(_ actual: SQLForeignKey,
                           matches expected: SQLForeignKey,
                           expectedName: String?) -> Bool
  {
    guard actual == expected else { return false }
    guard reflectsForeignKeyConstraintNames,
          let expectedName, !expectedName.isEmpty else { return true }
    guard let actualName = actual.relationship.constraintName,
          !actualName.isEmpty else { return false }
    return normalizedSchemaObjectName(actualName)
        == normalizedSchemaObjectName(expectedName)
  }

  func expectedAddedForeignKeyName(_ foreignKey: SQLForeignKey) -> String {
    let relationship = foreignKey.relationship
    if let name = relationship.constraintName, !name.isEmpty { return name }
    return relationship.name
  }

  func verifyForeignKeyDestination(_ foreignKey: SQLForeignKey,
                                   plan: SchemaSynchronizationPlan,
                                   createdTables: Set<String>,
                                   snapshot: SchemaSnapshot,
                                   issues: inout [ String ])
  {
    let destination = foreignKey.destinationTableName
    if createdTables.contains(destination) { return }
    let oldDestination = plan.oldTableName(for: destination)
    guard snapshot.tableNames.contains(oldDestination) else {
      issues.append("foreign key destination table \(destination) " +
                    "does not exist")
      return
    }

    var ignored = [ String ]()
    let actualPrimaryKey = primaryKeyColumns(
      in: snapshot.group(named: oldDestination), invalid: &ignored)
    let expectedPrimaryKey = foreignKey.sortedJoinColumns.map {
      plan.oldColumnName(for: $0.1, in: destination)
    }
    if expectedPrimaryKey.count != actualPrimaryKey.count
       || Set(expectedPrimaryKey) != Set(actualPrimaryKey)
    {
      issues.append("foreign key destination key \(destination) is stale")
    }
  }

  func verifyForeignKeyEffects(of plan: SchemaSynchronizationPlan,
                               in snapshot: SchemaSnapshot,
                               issues: inout [ String ])
  {
    for change in plan.droppedForeignKeys {
      let table = plan.newTableName(for: change.table)
      let actual = snapshot.group(named: table).groupForeignKeys
      if actual.contains(change.foreignKey) {
        issues.append("dropped foreign key on \(table) still exists")
      }
    }
    for change in plan.addedForeignKeys {
      let actual = snapshot.group(named: change.table).groupForeignKeys
      let name = expectedAddedForeignKeyName(change.foreignKey)
      if !actual.contains(where: {
        reflectedForeignKey($0, matches: change.foreignKey,
                            expectedName: name)
      }) {
        issues.append("added foreign key on \(change.table) does not exist")
      }
    }
  }

  func foreignKeysShareStructure(_ lhs: SQLForeignKey,
                                 _ rhs: SQLForeignKey) -> Bool
  {
    return lhs.destinationTableName == rhs.destinationTableName
        && lhs.sortedJoinColumns.elementsEqual(
             rhs.sortedJoinColumns, by: { $0.0 == $1.0 && $0.1 == $1.1 })
  }

  func sort(plan: inout SchemaSynchronizationPlan) {
    plan.createdTables.sort {
      $0.groupExternalName < $1.groupExternalName
    }
    plan.renamedTables.sort { $0.oldName < $1.oldName }
    plan.droppedForeignKeys.sort { $0.sortKey < $1.sortKey }
    plan.addedForeignKeys.sort { $0.sortKey < $1.sortKey }
    plan.droppedColumns.sort { $0.sortKey < $1.sortKey }
    plan.renamedColumns.sort { $0.sortKey < $1.sortKey }
    plan.changedTypes.sort { $0.sortKey < $1.sortKey }
    plan.changedNullability.sort { $0.sortKey < $1.sortKey }
    plan.addedColumns.sort { $0.sortKey < $1.sortKey }
  }

  func dropOrder(for groups: [ SQLTableGroup ],
                 unsupported: inout [ String ]) -> [ SQLTableGroup ]
  {
    var remaining = groups.sorted {
      $0.groupExternalName < $1.groupExternalName
    }
    var result = [ SQLTableGroup ]()
    result.reserveCapacity(groups.count)
    while !remaining.isEmpty {
      let index = remaining.firstIndex { candidate in
        !remaining.contains { other in
          other.groupExternalName != candidate.groupExternalName
            && other.countReferencesToEntityGroup(candidate) > 0
        }
      }
      guard let index = index else {
        let tables = remaining.map { $0.groupExternalName }.sorted()
        unsupported.append(
          "dropping tables with cyclic foreign keys: " +
          tables.joined(separator: ", "))
        result.append(contentsOf: remaining)
        break
      }
      result.append(remaining.remove(at: index))
    }
    return result
  }
}

fileprivate extension SchemaForeignKeyChange {

  var sortKey: String {
    var key = table + "."
    func append(_ component: String) {
      key += String(component.utf8.count) + ":" + component
    }
    append(foreignKey.destinationTableName)
    for columns in foreignKey.sortedJoinColumns {
      append(columns.0)
      append(columns.1)
    }
    append(foreignKey.updateRule.sqlString)
    append(foreignKey.deleteRule.sqlString)
    return key
  }
}

fileprivate extension SchemaColumnChange {

  var sortKey: String { return table + "." + attribute.columnNameOrName }
}

fileprivate extension SchemaColumnPair {

  var sortKey: String {
    return table + "." + newAttribute.columnNameOrName
  }
}

fileprivate extension SchemaColumnRename {

  var sortKey: String { return table + "." + oldName + "." + newName }
}

fileprivate extension SchemaSynchronizationPlan {

  var droppedTableNames: Set<String> {
    return Set(droppedTables.map { $0.groupExternalName })
  }

  func oldTableName(for newName: String) -> String {
    return renamedTables.first { $0.newName == newName }?.oldName ?? newName
  }

  func newTableName(for oldName: String) -> String {
    return renamedTables.first { $0.oldName == oldName }?.newName ?? oldName
  }

  func oldColumnName(for newName: String, in table: String) -> String {
    return renamedColumns.first {
      $0.table == table && $0.newName == newName
    }?.oldName ?? newName
  }

  var sourceTableNames: Set<String> {
    var names = droppedTableNames
    names.formUnion(renamedTables.map { $0.oldName })
    names.formUnion(droppedForeignKeys.map { $0.table })
    names.formUnion(droppedColumns.map { oldTableName(for: $0.table) })
    names.formUnion(renamedColumns.map { oldTableName(for: $0.table) })
    names.formUnion(changedTypes.map { oldTableName(for: $0.table) })
    names.formUnion(changedNullability.map { oldTableName(for: $0.table) })
    names.formUnion(addedColumns.map { oldTableName(for: $0.table) })
    names.formUnion(addedForeignKeys.map { oldTableName(for: $0.table) })
    return names
  }

  var targetTableNames: Set<String> {
    var names = Set(createdTables.map { $0.groupExternalName })
    names.formUnion(renamedTables.map { $0.newName })
    names.formUnion(droppedForeignKeys.map { newTableName(for: $0.table) })
    names.formUnion(droppedColumns.map { $0.table })
    names.formUnion(renamedColumns.map { $0.table })
    names.formUnion(changedTypes.map { $0.table })
    names.formUnion(changedNullability.map { $0.table })
    names.formUnion(addedColumns.map { $0.table })
    names.formUnion(addedForeignKeys.map { $0.table })
    return names
  }

  var modifyingTableNames: Set<String> {
    var names = sourceTableNames
    names.formUnion(targetTableNames)
    return names
  }

  var retainedModifiedTableNames: Set<String> {
    var names = Set(renamedTables.map { $0.newName })
    names.formUnion(droppedForeignKeys.map { newTableName(for: $0.table) })
    names.formUnion(droppedColumns.map { $0.table })
    names.formUnion(renamedColumns.map { $0.table })
    names.formUnion(changedTypes.map { $0.table })
    names.formUnion(changedNullability.map { $0.table })
    names.formUnion(addedColumns.map { $0.table })
    names.formUnion(addedForeignKeys.map { $0.table })
    names.subtract(Set(createdTables.map { $0.groupExternalName }))
    names.subtract(Set(droppedTables.map { $0.groupExternalName }))
    return names
  }
}

fileprivate protocol SchemaSynchronizationJoinProvider {

  func schemaSynchronizationJoins() throws -> [ Join ]
}

extension CodeRelationshipBase: SchemaSynchronizationJoinProvider {

  fileprivate func schemaSynchronizationJoins() throws -> [ Join ] {
    return [ try calculateJoin() ]
  }
}

extension Sequence where Iterator.Element == Entity { // an array of entities

  /// This takes two sequences of entities, NOT groups. It does *return*
  /// groups though.
  func calculateTableChanges<T: Sequence>(since oldSeq: T)
       -> SchemaSyncChangeSet<[Entity]>
         where T.Iterator.Element == Iterator.Element
  {
    // TODO: optimize ;->
    let oldGroups = oldSeq.extractEntityGroups()
    let newGroups = self.extractEntityGroups()
    let oldTables = Set<String>(oldGroups.map { $0.groupExternalName })
    let newTables = Set<String>(newGroups.map { $0.groupExternalName })
    
    var createdGroups = [ [ Entity ] ]()
    var droppedGroups = [ [ Entity ] ]()
    var oldSame    = [ String : [ Entity ] ]()
    var sameGroups    = [ ( [ Entity ], [ Entity ] ) ]()
    
    for oldGroup in oldGroups {
      let tableName = oldGroup.groupExternalName
      if !newTables.contains(tableName) {
        droppedGroups.append(oldGroup)
      }
      oldSame[tableName] = oldGroup
    }
    
    for group in newGroups {
      guard !group.isEmpty else { continue }
      
      let tableName = group.groupExternalName
      
      if !oldTables.contains(tableName) { // group is new
        createdGroups.append(group)
        continue
      }

      guard let oldGroup = oldSame[tableName]
       else {
        assert(false, "internal inconsistency on table \(tableName)")
        continue
       }
      
      sameGroups.append( ( oldGroup, group ) )
    }
    
    return SchemaSyncChangeSet(created : createdGroups,
                               dropped : droppedGroups,
                               same    : sameGroups)
  }
}

fileprivate extension Sequence where Iterator.Element == Entity { // an egroup
  
  func calculateForeignKeyConstraintChanges<T: Sequence>(since oldEntity: T)
       -> SchemaSyncChangeSet<SQLForeignKey>
         where T.Iterator.Element == Iterator.Element
  {
    let oldFKeys = oldEntity.groupForeignKeys
    let newFKeys = self.groupForeignKeys
    
    // Note: We don't track 'same' here, the ForeignKey value is a natural
    //       value. (and for schema sync we are not really interested in the
    //       'modelling' aspect of a relationship, just in the externals)
    
    let dropped = oldFKeys.compactMap { newFKeys.contains($0) ? nil : $0 }
    let created = newFKeys.compactMap { oldFKeys.contains($0) ? nil : $0 }
    
    return SchemaSyncChangeSet(created: created, dropped: dropped)
  }
  
  func calculateAttributeChanges<T: Sequence>(since oldEntity: T)
       -> SchemaSyncChangeSet<Attribute>
         where T.Iterator.Element == Iterator.Element
  {
    let oldAttrs   = oldEntity.groupAttributes
    let newAttrs   = self.groupAttributes
    let oldColumns = Set<String>(oldAttrs.map { $0.columnName ?? $0.name })
    let newColumns = Set<String>(newAttrs.map { $0.columnName ?? $0.name })
    
    var oldSame = [ String : Attribute ]()
    var created = [ Attribute ]()
    var dropped = [ Attribute ]()
    var same    = [ ( Attribute, Attribute ) ]()
    
    for attr in oldAttrs {
      let column = attr.columnName ?? attr.name
      if !newColumns.contains(column) { dropped.append(attr)   }
      else                            { oldSame[column] = attr }
    }
    
    for attr in newAttrs {
      let column = attr.columnName ?? attr.name
      if !oldColumns.contains(column)       { created.append(attr)             }
      else if let oldAttr = oldSame[column] { same.append( ( oldAttr, attr ) ) }
      else { assert(false, "internal inconsistency: \(attr)") }
    }
    
    return SchemaSyncChangeSet(created: created, dropped: dropped, same: same)
  }
}

final class SchemaSyncChangeSet<T> {
  let created : [ T ]
  let dropped : [ T ]
  let same    : [ ( T, T ) ]
  
  init(created: [ T ] = [], dropped: [ T ] = [], same: [ ( T, T ) ] = []) {
    self.created = created
    self.dropped = dropped
    self.same    = same
  }
}
