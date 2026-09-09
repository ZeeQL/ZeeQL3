//
//  SchemaSynchronization.swift
//  ZeeQL3
//
//  Created by Helge Hess on 08.06.17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

public enum SchemaSynchronizationError: Error, Equatable {

  case unsupported
  case invalidModel([ String ])
  case unsupportedChanges([ String ])
  case preconditionFailed([ String ])
  case verificationFailed([ String ])
}

public protocol SchemaSynchronization : SchemaGeneration {
  
  var adaptor : Adaptor     { get }
  var log     : ZeeQLLogger { get }

  /**
   * Builds a validated, ordered migration without changing the database.
   * Tables present in `old` but absent from `new` produce `DROP TABLE`.
   */
  func schemaSynchronizationStatements(old: Model, new: Model) throws
       -> [ SQLExpression ]

  /**
   * Applies a validated migration and verifies it before committing. The
   * caller must supply a complete `old` model when tables may be removed.
   */
  func synchronizeModels(old: Model, new: Model) throws

  /**
   * Whether this adaptor can safely execute schema synchronization. Opting in
   * requires transactional DDL and reflection of uncommitted schema changes.
   */
  var supportsSchemaSynchronization : Bool { get }

  /// Supports: ALTER TABLE oldName RENAME TO newName;
  var supportsDirectTableRenaming              : Bool { get }

  /// Supports: ALTER TABLE table ALTER COLUMN column TYPE newType
  ///           [USING CAST(column AS newType)]
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

  @inlinable
  var supportsSchemaSynchronization : Bool { return false }
  @inlinable
  var supportsDirectTableRenaming   : Bool { return false }

  func schemaSynchronizationStatements(old: Model, new: Model) throws
       -> [ SQLExpression ]
  {
    throw SchemaSynchronizationError.unsupported
  }

  func synchronizeModels(old: Model, new: Model) throws {
    throw SchemaSynchronizationError.unsupported
  }
}
