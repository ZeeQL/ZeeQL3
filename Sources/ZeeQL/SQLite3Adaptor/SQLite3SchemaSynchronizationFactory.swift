//
//  SQLite3SchemaSynchronizationFactory.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

open class SQLite3SchemaSynchronizationFactory : SchemaSynchronizationFactory {
  
  override open
  var supportsSchemaSynchronization              : Bool { return true }

  override open
  var supportsDirectTableRenaming                : Bool { return false }

  /// Not supported: ALTER TABLE hello ALTER COLUMN doit TYPE INT;
  override open
  var supportsDirectColumnCoercion               : Bool { return false }
  
  /// Not supported: ALTER TABLE hello DROP COLUMN doit;
  override open
  var supportsDirectColumnDeletion               : Bool { return false }
  
  /// Supported: ALTER TABLE x ADD COLUMN y TEXT;
  override open
  var supportsDirectColumnInsertion              : Bool { return true  }

  /**
   * Not supported:
   *   ALTER TABLE table ADD CONSTRAINT table2target
   *         FOREIGN KEY ( target_id ) REFERENCES target( target_id );
   *   ALTER TABLE table DROP CONSTRAINT table2target;
   *     - Note: constraint name must be known!
   */
  override open
  var supportsDirectForeignKeyModification       : Bool { return false }
  
  /// Not supported: ALTER TABLE table ALTER COLUMN column SET [NOT] NULL;
  override open
  var supportsDirectColumnNullRuleModification   : Bool { return false }
  
  /// Not supported: ALTER TABLE hello RENAME COLUMN doit TO testit;
  override open
  var supportsDirectColumnRenaming               : Bool { return false }

  override open
  var reflectsForeignKeyConstraintNames          : Bool { return false }

  override open func normalizedColumnType(_ type: String) -> String {
    let type = super.normalizedColumnType(type)
    if type.contains("INT") { return "INTEGER" }
    if type.contains("CHAR") || type.contains("CLOB") || type.contains("TEXT") {
      return "TEXT"
    }
    if type.isEmpty || type.contains("BLOB") { return "BLOB" }
    if type.contains("REAL") || type.contains("FLOA") || type.contains("DOUB") {
      return "REAL"
    }
    return "NUMERIC"
  }

  override open func normalizedSchemaObjectName(_ name: String) -> String {
    return name.lowercased()
  }

  override open func synchronizationIssuesForTable(named table: String)
       -> [ String ]
  {
    guard table.lowercased().hasPrefix("sqlite_") else { return [] }
    return [ "synchronizing SQLite system table \(table)" ]
  }

  override open func isSystemTableForSynchronization(_ table: String) -> Bool {
    return table.lowercased().hasPrefix("sqlite_")
  }

  override open func columnNamesForVerification(in table: String,
                                                on channel: AdaptorChannel)
       throws -> Set<String>?
  {
    let expression = channel.expressionFactory.createExpression(nil)
    let table = expression.sqlStringFor(schemaObjectName: table)
    let records = try channel.querySQL("PRAGMA main.table_xinfo(\(table))")
    let names = records.compactMap { $0["name"] as? String }
    return names.isEmpty ? nil : Set(names)
  }

  override open
  func preflightSynchronizationIssues(modifyingTables: Set<String>,
                                      droppingTables: Set<String>,
                                      on channel: AdaptorChannel) throws
       -> [ String ]
  {
    var objects = [ SQLiteSchemaObject ]()
    try channel.querySQL(
      "SELECT 'main', type, name, tbl_name, sql FROM sqlite_master " +
      "WHERE type IN ('table', 'view', 'trigger') UNION ALL " +
      "SELECT 'temp', type, name, tbl_name, sql FROM sqlite_temp_master " +
      "WHERE type IN ('table', 'view', 'trigger')") { record in
        guard let schema = record[0] as? String,
              let type = record["type"] as? String,
              let name = record["name"] as? String else { return }
        objects.append(SQLiteSchemaObject(
          schema: schema, type: type, name: name,
          table: record["tbl_name"] as? String,
          sql: record["sql"] as? String))
      }

    var protectedTables = Set<String>()
    var virtualTables = Set<String>()
    for schema in [ "main", "temp" ] {
      try channel.querySQL("PRAGMA \(schema).table_list") { record in
        guard let name = record["name"] as? String,
              let type = record["type"] as? String,
              type == "virtual" || type == "shadow" else { return }
        let normalizedName = name.lowercased()
        protectedTables.insert(normalizedName)
        if type == "virtual" { virtualTables.insert(normalizedName) }
      }
    }
    for object in objects where object.schema == "main" {
      guard object.sql?.uppercased()
                       .hasPrefix("CREATE VIRTUAL TABLE") == true else
      {
        continue
      }
      let root = object.name.lowercased()
      protectedTables.insert(root)
      virtualTables.insert(root)
      for candidate in objects
            where candidate.schema == "main"
               && candidate.name.lowercased().hasPrefix(root + "_")
      {
        protectedTables.insert(candidate.name.lowercased())
      }
    }

    var issues = [ String ]()
    for table in modifyingTables {
      let normalizedTable = table.lowercased()
      if objects.contains(where: {
        $0.schema == "temp" && $0.name.lowercased() == normalizedTable
      }) {
        issues.append("temporary schema object \(table) shadows a table")
      }
      guard let object = objects.first(where: {
        $0.schema == "main" && $0.name.lowercased() == normalizedTable
          && ($0.type == "table" || $0.type == "view")
      }) else { continue }
      if object.type != "table" {
        issues.append("schema object \(table) is a \(object.type), not a table")
      }
      else if object.name != table {
        issues.append(
          "table \(table) differs in case from existing table \(object.name)")
      }
      if protectedTables.contains(normalizedTable) {
        issues.append(
          "cannot synchronize virtual or shadow table \(object.name)")
      }
    }
    if !droppingTables.isEmpty {
      let normalizedDrops = Set(droppingTables.map { $0.lowercased() })
      for table in virtualTables where !normalizedDrops.contains(table) {
        issues.append(
          "cannot safely drop tables while virtual table \(table) exists")
      }
      for object in objects where object.type == "view" {
        issues.append(
          "cannot safely drop tables while view \(object.name) exists")
      }
      for object in objects
            where object.type == "trigger"
               && !normalizedDrops.contains(object.table?.lowercased() ?? "")
      {
        issues.append(
          "cannot safely drop tables while trigger \(object.name) exists")
      }
      let expression = channel.expressionFactory.createExpression(nil)
      for object in objects where object.type == "table" {
        let source = object.name
        guard !isSystemTableForSynchronization(source),
              !normalizedDrops.contains(source.lowercased()) else { continue }
        let table = expression.sqlStringFor(schemaObjectName: source)
        let pragma = "PRAGMA \(object.schema).foreign_key_list(\(table))"
        try channel.querySQL(pragma) { record in
          guard let destination = record["table"] as? String,
                normalizedDrops.contains(destination.lowercased()) else
          {
            return
          }
          issues.append(
            "retained table \(source) references a table being dropped")
        }
      }
    }
    return issues
  }

}

private struct SQLiteSchemaObject {

  let schema : String
  let type   : String
  let name   : String
  let table  : String?
  let sql    : String?
}
