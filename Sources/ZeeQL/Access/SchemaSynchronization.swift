//
//  SchemaSynchronization.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.06.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol SchemaSynchronization : SchemaGeneration {
  
  var adaptor : Adaptor     { get }
  var log     : ZeeQLLogger { get }

  /// Supports: ALTER TABLE table ALTER COLUMN column TYPE newType;
  var supportsDirectColumnCoercion             : Bool { get }
  
  /// Supports: ALTER TABLE table DROP COLUMN column [CASCADE];
  var supportsDirectColumnDeletion             : Bool { get }
  /// Supports: ALTER TABLE table ADD COLUMN column TEXT;
  var supportsDirectColumnInsertion            : Bool { get }
  
  /// Supports: ALTER TABLE table ALTER COLUMN column SET  NOT NULL;
  ///           ALTER TABLE table ALTER COLUMN column DROP NOT NULL;
  var supportsDirectColumnNullRuleModification : Bool { get }
  
  /// Supports: ALTER TABLE table RENAME COLUMN column TO newName;
  var supportsDirectColumnRenaming             : Bool { get }
  
}

public extension SchemaSynchronization {
}
