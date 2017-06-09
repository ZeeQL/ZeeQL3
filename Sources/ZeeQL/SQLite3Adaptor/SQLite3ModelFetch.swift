//
//  SQLite3ModelFetch.swift
//  ZeeQL3
//
//  Created by Helge Hess on 14/04/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Wraps queries which do SQLite3 schema reflection.
 */
open class SQLite3ModelFetch: AdaptorModelFetch {
  
  public enum Error : Swift.Error {
    case NotImplemented
    case GotNoSchemaVersion
  }
  
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
    guard let tag = tagOpt else { throw Error.GotNoSchemaVersion }
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
    try channel.querySQL("pragma database_list") { record in
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
    var sql = "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
    if let like = like {
      sql += " AND name LIKE '" + like + "'"; // TODO: escape!
    }
    var names = [ String ]()
    try channel.select(sql) { ( name : String ) in names.append(name) }
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
    let records : [ AdaptorRecord ] =
                      try channel.querySQL("pragma table_info(\(table))")
    return records
  }
  
  func _fetchForeignKeysOfTable(_ table: String) throws -> [ AdaptorRecord ] {
    // keys: id, seq, table, from, to, on_update, on_delete, match
    let records : [ AdaptorRecord ] =
                      try channel.querySQL("pragma foreign_key_list(\(table))")
    return records
  }
  
  func primaryKeyNamesFromColumnInfos(_ columnInfos : [ AdaptorRecord ],
                                      _ attributes  : [ Attribute ])
       -> [ String ]
  {
    guard !columnInfos.isEmpty else { return [] }

    var pkeys = [ String ]()
    
    for i in 0..<columnInfos.count {
      let colInfo = columnInfos[i]
      guard let v = colInfo["pk"] else { continue }
      
      let doAdd : Bool
      switch v {
        case let typedValue as String: doAdd = typedValue == "1"
        case let typedValue as Int:    doAdd = typedValue != 0
        case let typedValue as Int32:  doAdd = typedValue != 0
        case let typedValue as Int64:  doAdd = typedValue != 0
        default: doAdd = false
      }
      if doAdd { pkeys.append(attributes[i].name) }
    }

    return pkeys
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
      if let idx = exttype.characters.index(of: "(") {
        let ws = exttype[idx..<exttype.endIndex]
        exttype = exttype[exttype.startIndex..<idx]
        
        if let eidx = ws.characters.index(of: ")") {
          let iv = ws[ws.startIndex..<eidx]
          width = Int(iv)
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
        else if let i = v as? Int {
          attribute.allowsNull = i == 0
        }
        else if let i = v as? Int32 {
          attribute.allowsNull = i == 0
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

    let fkeysByConstraint : [ Int : [ AdaptorRecord ] ] = {
      var grouped = [ Int : [ AdaptorRecord ] ]()
      for record in foreignKeyRecords {
        guard let rawkey = record["id"] else {
          log.warn("fkey record has no id:", record)
          continue
        }
        
        let key : Int
        if let ikey = rawkey as? Int {
          key = ikey
        }
        else if let ikey = rawkey as? Int64 {
          key = Int(ikey)
        }
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
        // TODO: match (e.g. NONE), on_update(updateRule)
        guard let destname     = fkey["table"] as? String,
              let sourceColumn = fkey["from"]  as? String,
              let targetColumn = fkey["to"]    as? String
         else { continue }
        
        relship.destinationEntityName = destname
        
        let join = Join(source: sourceColumn, destination: targetColumn)
        relship.joins.append(join)
        
        if let deleteRule = (fkey["on_delete"] as? String)?.characters.first {
          switch deleteRule {
            case "n", "N": relship.deleteRule = .noAction
            case "r", "R": relship.deleteRule = .deny
            case "c", "C": relship.deleteRule = .cascade
            
            case "s":
              let n = (fkey["on_delete"] as? String)?.uppercased() ?? ""
              if      n == "SET NULL"    { relship.deleteRule = .nullify      }
              else if n == "SET DEFAULT" { relship.deleteRule = .applyDefault }
              else {
                fallthrough
              }
            
            default:
              log.warn("unexpected foreign-key delete rule:", fkey["on_delete"])
          }
        }
      }
      
      if !relship.joins.isEmpty {
        relships.append(relship)
      }
    }
    
    return relships
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
