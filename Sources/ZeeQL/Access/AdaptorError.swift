//
//  AdaptorError.swift
//  ZeeQL3
//
//  Created by Helge Hess on 29/04/17.
//  Copyright © 2017-2020 ZeeZide GmbH. All rights reserved.
//

/**
 * Errors which are thrown by `Adaptor` and `AdaptorChannel` objects.
 */
public enum AdaptorChannelError : Swift.Error {
  
  /// The operation (e.g. an INSERT or UPDATE) was assumed to affect exactly
  /// one record, but didn't.
  case OperationDidNotAffectOne
  
  /// Failed to access the primary key after INSERTing a record
  case FailedToGrabNewPrimaryKey(entity: Entity, row: AdaptorRow)
  
  /// Attempt to do a insert w/ refetchall, but missing the required entity
  case InsertRefetchRequiresEntity
  
  case FailedToRefetchInsertedRow(entity: Entity?, row: AdaptorRow)
  
  case UnexpectedOperation
  
  case MissingRecordToInsert
  case MissingRecordToUpdate
  case MissingQualification
  
  case TransactionInProgress
  
  case NotImplemented(String)
  
  case QueryFailed(sql: String, error: Swift.Error)
  
  case CouldNotOpenChannel(Swift.Error?)
  
  case RecordNotFound
}

// TODO: consolidate on just AdaptorError
public typealias AdaptorError = AdaptorChannelError
