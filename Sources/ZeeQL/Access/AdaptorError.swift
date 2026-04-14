//
//  AdaptorError.swift
//  ZeeQL3
//
//  Created by Helge Hess on 29/04/17.
//  Copyright © 2017-2026 ZeeZide GmbH. All rights reserved.
//

/**
 * Errors which are thrown by ``Adaptor`` and ``AdaptorChannel`` objects.
 */
public enum AdaptorChannelError : Swift.Error {

  /// The operation (e.g. an INSERT or UPDATE) was assumed to affect exactly
  /// one record, but didn't.
  case operationDidNotAffectOne

  /// Failed to access the primary key after INSERTing a record
  case failedToGrabNewPrimaryKey(entity: Entity, row: AdaptorRow)

  /// Attempt to do a insert w/ refetchall, but missing the required entity
  case insertRefetchRequiresEntity

  case failedToRefetchInsertedRow(entity: Entity?, row: AdaptorRow)

  case unexpectedOperation

  case missingRecordToInsert
  case missingRecordToUpdate
  case missingQualification

  case transactionInProgress

  case notImplemented(String)

  case queryFailed(sql: String, error: Swift.Error)

  case couldNotOpenChannel(Swift.Error?)

  case couldNotDescribeTable(String)

  case recordNotFound
}

#if swift(>=5.5)
// @unchecked because associated values include `Entity` (a protocol, not
// automatically Sendable) and `AdaptorRow` (`[String: Any?]` -- Any isn't
// Sendable). At runtime the Entity refs are immutable model objects and
// AdaptorRow values are database primitives (String, Int64, Double, Data, nil).
extension AdaptorChannelError: @unchecked Sendable {}
#endif

// TODO: consolidate on just AdaptorError
public typealias AdaptorError = AdaptorChannelError
