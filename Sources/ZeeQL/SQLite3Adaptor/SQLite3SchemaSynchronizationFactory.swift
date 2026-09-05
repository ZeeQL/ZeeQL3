//
//  SQLite3SchemaSynchronizationFactory.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

open class SQLite3SchemaSynchronizationFactory : SchemaSynchronizationFactory {
  
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

}
