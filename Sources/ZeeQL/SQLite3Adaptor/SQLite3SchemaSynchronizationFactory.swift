//
//  SQLite3SchemaSynchronizationFactory.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

open class SQLite3SchemaSynchronizationFactory : SchemaSynchronizationFactory {
  
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
  
}
