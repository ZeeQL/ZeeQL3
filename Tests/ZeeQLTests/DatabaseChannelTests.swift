//
//  DatabaseChannelTests.swift
//  ZeeQL
//
import XCTest
@testable import ZeeQL

class DatabaseChannelTests: XCTestCase {

  func testWithTransactionPreservesBodyError() throws {
    let adaptor = TransactionTestAdaptor()
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    XCTAssertThrowsError(try channel.withTransaction { _ in
      throw TransactionTestError.body
    }) { error in
      XCTAssertEqual(error as? TransactionTestError, .body)
    }
    XCTAssertEqual(adaptor.channel.operations, [ .begin, .rollback ])
  }

  func testWithTransactionPreservesBeginError() throws {
    let adaptor = TransactionTestAdaptor(failing: .begin)
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    XCTAssertThrowsError(try channel.withTransaction { _ in }) { error in
      XCTAssertEqual(error as? TransactionTestError, .begin)
    }
    XCTAssertEqual(adaptor.channel.operations, [ .begin ])
  }

  func testWithTransactionReportsCommitError() throws {
    let adaptor = TransactionTestAdaptor(failing: .commit)
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    XCTAssertThrowsError(try channel.withTransaction { _ in }) { error in
      assertFinishError(error, wraps: .commit)
    }
    XCTAssertEqual(adaptor.channel.operations,
                   [ .begin, .commit, .rollback ])
  }

  func testWithTransactionPreservesBodyErrorWhenRollbackFails() throws {
    let adaptor = TransactionTestAdaptor(failing: .rollback)
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    XCTAssertThrowsError(try channel.withTransaction { _ in
      throw TransactionTestError.body
    }) { error in
      XCTAssertEqual(error as? TransactionTestError, .body)
    }
    XCTAssertEqual(adaptor.channel.operations, [ .begin, .rollback ])
  }

  @available(*, deprecated)
  func testManualTransactionRetainsChannelUntilCommit() throws {
    let adaptor = TransactionTestAdaptor()
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    try channel.begin()
    XCTAssertNotNil(channel.adaptorChannel)
    XCTAssertTrue(channel.isInTransaction)
    XCTAssertEqual(adaptor.channel.operations, [ .begin ])

    try channel.commit()
    XCTAssertNil(channel.adaptorChannel)
    XCTAssertFalse(channel.isInTransaction)
    XCTAssertEqual(adaptor.channel.operations, [ .begin, .commit ])
  }

  @available(*, deprecated)
  func testManualTransactionRetainsChannelUntilRollback() throws {
    let adaptor = TransactionTestAdaptor()
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    try channel.begin()
    try channel.rollback()

    XCTAssertNil(channel.adaptorChannel)
    XCTAssertEqual(adaptor.channel.operations, [ .begin, .rollback ])
  }

  @available(*, deprecated)
  func testManualBeginFailureReleasesInactiveChannel() {
    let adaptor = TransactionTestAdaptor(failing: .begin)
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    XCTAssertThrowsError(try channel.begin())

    XCTAssertNil(channel.adaptorChannel)
    XCTAssertEqual(adaptor.channel.operations, [ .begin ])
  }

  @available(*, deprecated)
  func testManualCommitFailureRetainsActiveChannel() throws {
    let adaptor = TransactionTestAdaptor(failing: .commit)
    let channel = DatabaseChannelBase(database: Database(adaptor: adaptor))

    try channel.begin()
    XCTAssertThrowsError(try channel.commit()) { error in
      assertFinishError(error, wraps: .commit)
    }
    XCTAssertNotNil(channel.adaptorChannel)
    XCTAssertTrue(channel.isInTransaction)

    try channel.rollback()
    XCTAssertNil(channel.adaptorChannel)
    XCTAssertEqual(adaptor.channel.operations, [ .begin, .commit, .rollback ])
  }

  private func assertFinishError(_ error: Error,
                                 wraps expected: TransactionTestError)
  {
    guard case DatabaseChannelError.couldNotFinishTX(let underlying) = error
    else {
      return XCTFail("Unexpected transaction error: \(error)")
    }
    XCTAssertEqual(underlying as? TransactionTestError, expected)
  }
}

private enum TransactionTestError: Error, Equatable {

  case begin
  case body
  case commit
  case rollback
}

private final class TransactionTestAdaptor: FakeAdaptor {

  let channel: TransactionTestChannel

  init(failing operation: TransactionTestChannel.Operation? = nil) {
    channel = TransactionTestChannel(failing: operation)
    super.init()
  }

  override func openChannel() throws -> AdaptorChannel { return channel }
}

private final class TransactionTestChannel: AdaptorChannel {

  enum Operation: Equatable {

    case begin
    case commit
    case rollback
  }

  let expressionFactory = SQLExpressionFactory()
  private let failingOperation: Operation?
  private(set) var operations = [ Operation ]()
  private(set) var isTransactionInProgress = false

  init(failing operation: Operation?) {
    failingOperation = operation
  }

  func begin() throws {
    operations.append(.begin)
    if failingOperation == .begin { throw TransactionTestError.begin }
    isTransactionInProgress = true
  }

  func commit() throws {
    operations.append(.commit)
    if failingOperation == .commit { throw TransactionTestError.commit }
    isTransactionInProgress = false
  }

  func rollback() throws {
    operations.append(.rollback)
    if failingOperation == .rollback { throw TransactionTestError.rollback }
    isTransactionInProgress = false
  }

  func querySQL(_ sql: String, _ attributes: [ Attribute ]?,
                cb: ( AdaptorRecord ) throws -> Void) throws {}

  func performSQL(_ sql: String) throws -> Int { return 0 }

  func evaluateQueryExpression(_ expression: SQLExpression,
                               _ attributes: [ Attribute ]?,
                               result: ( AdaptorRecord ) throws -> Void) throws
  {}

  func evaluateUpdateExpression(_ expression: SQLExpression) throws -> Int {
    return 0
  }

  func describeTableNames() throws -> [ String ] { return [] }
  func describeSequenceNames() throws -> [ String ] { return [] }
  func describeDatabaseNames() throws -> [ String ] { return [] }

  func describeEntityWithTableName(_ table: String) throws -> Entity? {
    return nil
  }
}
