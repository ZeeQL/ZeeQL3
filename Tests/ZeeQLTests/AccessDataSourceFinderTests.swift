//
//  AccessDataSourceFinderTests.swift
//  ZeeQL
//
import XCTest
@testable import ZeeQL

final class AccessDataSourceFinderTests: XCTestCase {

  func testCompositePrimaryKeyRequiresExactValueCount() throws {
    let dataSource = makeCompositeDataSource()
    assertInvalidPrimaryKey {
      _ = try dataSource.fetchSpecificationForFind([ 1 ])
    }
    assertInvalidPrimaryKey {
      _ = try dataSource.fetchSpecificationForFind([ 1, 2, 3 ])
    }
    assertInvalidPrimaryKey {
      _ = try dataSource.fetchSpecificationForFind([])
    }
  }

  func testCompositePrimaryKeyAcceptsExactValueCount() throws {
    let dataSource = makeCompositeDataSource()
    let fetch = try XCTUnwrap(
      dataSource.fetchSpecificationForFind([ 1, "en" ]))
    let qualifier = try XCTUnwrap(fetch.qualifier as? CompoundQualifier)
    XCTAssertEqual(qualifier.op, .and)
    XCTAssertEqual(qualifier.qualifiers.count, 2)
  }

  private func makeCompositeDataSource() -> AdaptorDataSource {
    let entity = ModelEntity(name: "LocalizedItem")
    entity.attributes = [
      ModelAttribute(name: "id"), ModelAttribute(name: "language")
    ]
    entity.primaryKeyAttributeNames = [ "id", "language" ]
    let adaptor = FakeAdaptor(model: Model(entities: [ entity ]))
    return AdaptorDataSource(adaptor: adaptor, entity: entity)
  }

  private func assertInvalidPrimaryKey(_ operation: () throws -> Void) {
    XCTAssertThrowsError(try operation()) { error in
      guard case AccessDataSourceError.cannotConstructFetchSpecification(
        .invalidPrimaryKey) = error else {
        return XCTFail("Unexpected finder error: \(error)")
      }
    }
  }
}
