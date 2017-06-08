//
//  SchemaSynchronizationFactory.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Object used to generate database DDL expressions (i.e. CREATE TABLE and 
 * such). Similar to `SQLExpression`.
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
  open var supportsDirectColumnCoercion             : Bool { return true }
  open var supportsDirectColumnDeletion             : Bool { return true }
  open var supportsDirectColumnInsertion            : Bool { return true }
  open var supportsDirectColumnNullRuleModification : Bool { return true }
  open var supportsDirectColumnRenaming             : Bool { return true }
  open var supportsSchemaSynchronization            : Bool { return true }
  
}

public extension Adaptor {
  
  /// Note: Returns a stateful object (a new one every time it is accessed).
  var synchronizationFactory : SchemaSynchronizationFactory {
    return SchemaSynchronizationFactory(adaptor: self)
  }
  
}
