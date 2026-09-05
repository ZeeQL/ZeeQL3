//
//  SQLite3ModelFetch.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14/04/17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

public enum SQLite3ModelFetchError: Swift.Error {

  case notImplemented
  case gotNoSchemaVersion
}

/**
 * Wraps queries which do SQLite3 schema reflection.
 */
open class SQLite3ModelFetch: AdaptorModelFetch {

  let log : ZeeQLLogger = globalZeeQLLogger
  
  public var channel    : AdaptorChannel
  public let nameMapper : ModelNameMapper
  
  public init(channel: AdaptorChannel) {
    self.channel    = channel
    self.nameMapper = self.channel
  }

  
  // MARK: - Model tags
  
  public func fetchModelTag() throws -> ModelTag {
    var tagOpt : SQLite3ModelTag? = nil
    try channel.select("PRAGMA main.schema_version") { ( version : Int ) in
      tagOpt = SQLite3ModelTag(version: version)
    }
    guard let tag = tagOpt else { throw SQLite3ModelFetchError.gotNoSchemaVersion }
    return tag
  }
  
  
  // MARK: - Old-style reflection methods

  public func describeSequenceNames() throws -> [ String ] { return [] } // TODO

  public func describeDatabaseNames() throws -> [String] {
    return try describeDatabaseNames(like: nil)
  }
  public func describeDatabaseNames(like: String?) throws -> [String] {
    // TBD: what about the _like? Which syntax is expected?
    var dbNames = [ String ]()
    try channel.querySQL("PRAGMA database_list") { record in
      if let name = record["name"] as? String, name != "temp" {
        dbNames.append(name)
      }
    }
    return dbNames
  }

  public func describeTableNames() throws -> [ String ] {
    return try describeTableNames(like: nil)
  }
  public func describeTableNames(like: String?) throws -> [ String ] {
    // TBD: iterate on all returned describeDatabaseNames
    // (via dbname.sqlite_master)
    // ATTACH DATABASE 'DatabaseName' As 'Alias-Name';
    var names = [ String ]()
    let expression = channel.expressionFactory.createExpression(nil)
    expression.statement =
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
    if let like {
      expression.statement += " AND name LIKE ?"
      expression.bindVariables = [
        SQLExpression.BindVariable(attribute: nil, value: like)
      ]
    }
    try channel.evaluateQueryExpression(expression, nil) { record in
      if let name = record[0] as? String { names.append(name) }
    }
    return names
  }

  public func describeEntityWithTableName(_ table: String) throws -> Entity {
    let columnInfos = try _fetchColumnsOfTable(table)
    let attributes  = attributesFromColumnInfos(columnInfos)

    let entity = ModelEntity(name: nameMapper.entityNameForTableName(table),
                             table: table)
    entity.attributes = attributes
    entity.primaryKeyAttributeNames =
                    primaryKeyNamesFromColumnInfos(columnInfos, attributes)
    entity.relationships = try relationshipsForTableName(table, entity)
    return entity
  }
  
  func _fetchColumnsOfTable(_ table: String) throws -> [ AdaptorRecord ] {
    // keys: cid, name, type, notnull, dflt_value, pk
    let table = quotedIdentifier(table)
    let records = try channel.querySQL("PRAGMA table_info(\(table))")
    return records
  }
  
  func _fetchForeignKeysOfTable(_ table: String) throws -> [ AdaptorRecord ] {
    // keys: id, seq, table, from, to, on_update, on_delete, match
    let table = quotedIdentifier(table)
    let records = try channel.querySQL("PRAGMA foreign_key_list(\(table))")
    return records
  }

  private func quotedIdentifier(_ identifier: String) -> String {
    return channel.expressionFactory.createExpression(nil)
                  .sqlStringFor(schemaObjectName: identifier)
  }
  
  func primaryKeyNamesFromColumnInfos(_ columnInfos : [ AdaptorRecord ],
                                      _ attributes  : [ Attribute ])
       -> [ String ]
  {
    guard !columnInfos.isEmpty else { return [] }

    var firstPKey : ( ordinal: Int, name: String )?
    var pkeys     : [ ( ordinal: Int, name: String ) ]?

    func integerValue(_ value: Any) -> Int? {
      if let value = value as? Int               { return value      }
      if let value = value as? Int32             { return Int(value) }
      if let value = value as? Int64             { return Int(value) }
      if let value = value as? String            { return Int(value) }
      if let value = value as? any BinaryInteger { return Int(value) }
      return nil
    }

    for i in 0..<columnInfos.count {
      let colInfo = columnInfos[i]
      guard let value = colInfo["pk"],
            let ordinal = integerValue(value), ordinal > 0,
            i < attributes.count
       else { continue }
      
      let pkey = ( ordinal: ordinal, name: attributes[i].name )
      if let firstPKey {
        if pkeys == nil { pkeys = [ firstPKey, pkey ] }
        else { pkeys?.append(pkey) }
      }
      else {
        firstPKey = pkey
      }
    }

    guard var pkeys else {
      guard let firstPKey else { return [] }
      return [ firstPKey.name ]
    }
    pkeys.sort { $0.ordinal < $1.ordinal }
    return pkeys.map { $0.name }
  }

  func attributesFromColumnInfos(_ columnInfos: [ AdaptorRecord ])
       -> [ Attribute ]
  {
    // map: a.attnum, a.attname, t.typname, a.attlen, a.attnotnull, a.pkey "

    var attributes = [ Attribute ]()
    attributes.reserveCapacity(columnInfos.count)

    for colinfo in columnInfos {
      guard let colname = colinfo["name"] as? String else { continue } // Hm
      guard var exttype = colinfo["type"] as? String else { continue }
    
      var width : Int? = nil

      /* process external type, eg: VARCHAR(40) */
      if let start = exttype.firstIndex(of: "(") {
        let suffix = exttype[exttype.index(after: start)...]
        exttype = String(exttype[..<start])

        if let end = suffix.firstIndex(of: ")") {
          width = Int(suffix[..<end])
        }
      }
      exttype = exttype.uppercased()
      
      // TODO: complete information
      let attribute =
            ModelAttribute(name: nameMapper.attributeNameForColumnName(colname),
                           column: colname,
                           externalType: exttype)
      // TODO: autoincrement
      if let v = colinfo["notnull"] {
        if let s = v as? String {
          attribute.allowsNull = s != "1" // notnull
        }
        else if let i = v as? Int   { attribute.allowsNull = i == 0 }
        else if let i = v as? Int32 { attribute.allowsNull = i == 0 }
        else if let i = v as? Int64 { attribute.allowsNull = i == 0 }
        else {
          log.warn("unexpected type for notnull column:", v, type(of:v))
        }
      }
      if let v = colinfo["dflt_value"] {
        attribute.defaultValue = v
      }
      if let width = width {
        attribute.width = width
      }

      attribute.valueType =
        ZeeQLTypes.valueTypeForExternalType(exttype,
                                      allowsNull: attribute.allowsNull ?? true)
      
      attributes.append(attribute)
    }

    return attributes
  }

  func relationshipsForTableName(_ table: String, _ entity: Entity) throws
       -> [ Relationship ]
  {
    let foreignKeyRecords = try _fetchForeignKeysOfTable(table)
    guard !foreignKeyRecords.isEmpty else { return [] }

    func constraintRule(_ value: Any?, column: String) -> ConstraintRule? {
      guard let value = value as? String else { return nil }
      guard let rule = ConstraintRule(sqliteRule: value) else {
        log.warn("unexpected foreign-key \(column) rule:", value)
        return nil
      }
      return rule
    }

    let fkeysByConstraint : [ Int : [ AdaptorRecord ] ] = {
      var grouped = [ Int : [ AdaptorRecord ] ]()
      for record in foreignKeyRecords {
        guard let rawkey = record["id"] else {
          log.warn("fkey record has no id:", record)
          continue
        }
        
        let key : Int
        if      let ikey = rawkey as? Int   { key = ikey      }
        else if let ikey = rawkey as? Int32 { key = Int(ikey) }
        else if let ikey = rawkey as? Int64 { key = Int(ikey) }
        else if let skey = rawkey as? String, let ikey = Int(skey) {
          key = ikey
        }
        else {
          log.warn("unexpected foreign key id value:", rawkey, type(of: rawkey))
          continue
        }
        
        if case nil = grouped[key]?.append(record) {
          grouped[key] = [ record ]
        }
      }
      return grouped
    }()
    
    var relships = [ Relationship ]()
    relships.reserveCapacity(fkeysByConstraint.count)
    
    for ( constraintId, fkeys ) in fkeysByConstraint {
      // Note: maybe we should apply a better name, for now we assume this is
      //       done by the model beautifier
      let name    = "constraint\(constraintId)"
      let relship = ModelRelationship(name: name, isToMany: false,
                                      source: entity, destination: nil)
      relship.constraintName = name
      
      for fkey in fkeys {
        guard let destname     = fkey["table"] as? String,
              let sourceColumn = fkey["from"]  as? String,
              let targetColumn = fkey["to"]    as? String
         else { continue }
        
        relship.destinationEntityName = destname
        
        let join = Join(source: sourceColumn, destination: targetColumn)
        relship.joins.append(join)

        relship.updateRule = constraintRule(fkey["on_update"], column: "update")
        relship.deleteRule = constraintRule(fkey["on_delete"], column: "delete")
      }
      
      if !relship.joins.isEmpty {
        relships.append(relship)
      }
    }
    
    return relships
  }
}

public extension ConstraintRule {

  /// Parses an action returned by SQLite's foreign_key_list pragma.
  init?(sqliteRule: String) {
    switch sqliteRule.uppercased() {
      case "NO ACTION":   self = .noAction
      case "RESTRICT":    self = .deny
      case "CASCADE":     self = .cascade
      case "SET NULL":    self = .nullify
      case "SET DEFAULT": self = .applyDefault
      default:            return nil
    }
  }
}

public struct SQLite3ModelTag : ModelTag, Equatable {
  let version : Int
  
  public func isEqual(to object: Any?) -> Bool {
    guard let object = object else { return false }
    guard let other = object as? SQLite3ModelTag else { return false }
    return self == other
  }
  public static func ==(lhs: SQLite3ModelTag, rhs: SQLite3ModelTag) -> Bool {
    return lhs.version == rhs.version
  }
}
