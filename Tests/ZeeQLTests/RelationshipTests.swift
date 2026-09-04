//
//  RelationshipTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

final class RelationshipTests: XCTestCase {

  func testFlattenedRelationshipReturnsPathComponents() throws {
    let people     = ModelEntity(name: "People")
    let employments = ModelEntity(name: "Employments")
    let companies  = ModelEntity(name: "Companies")
    let addresses  = ModelEntity(name: "Addresses")

    let employment = ModelRelationship(
      name: "employments", source: people, destination: employments)
    let company = ModelRelationship(
      name: "company", source: employments, destination: companies)
    let address = ModelRelationship(
      name: "addresses", source: companies, destination: addresses)
    let flattened = ModelRelationship(
      name: "companyAddresses", source: people, destination: addresses)
    flattened.relationshipPath = "employments.company.addresses"

    people.relationships      = [ employment, flattened ]
    employments.relationships = [ company ]
    companies.relationships   = [ address ]

    let components = try XCTUnwrap(flattened.componentRelationships)
    XCTAssertEqual(components.count, 3)
    XCTAssertTrue(components[0] === employment)
    XCTAssertTrue(components[1] === company)
    XCTAssertTrue(components[2] === address)
    XCTAssertTrue(flattened.references(property: company))
  }

  func testToOneDefaultMinimumCountMatchesMandatoryState() {
    let source   = ModelEntity(name: "Source")
    let target   = ModelEntity(name: "Target")
    let targetID = ModelAttribute(name: "id", allowsNull: false)
    target.attributes = [ targetID ]

    let requiredID = ModelAttribute(name: "requiredID", allowsNull: false)
    let optionalID = ModelAttribute(name: "optionalID", allowsNull: true)
    source.attributes = [ requiredID, optionalID ]

    let required = ModelRelationship(
      name: "required", source: source, destination: target)
    required.joins = [ Join(source: requiredID, destination: targetID) ]
    let optional = ModelRelationship(
      name: "optional", source: source, destination: target)
    optional.joins = [ Join(source: optionalID, destination: targetID) ]

    XCTAssertTrue(required.isMandatory)
    XCTAssertEqual(required.minCount, 1)
    XCTAssertFalse(optional.isMandatory)
    XCTAssertEqual(optional.minCount, 0)
  }
}
