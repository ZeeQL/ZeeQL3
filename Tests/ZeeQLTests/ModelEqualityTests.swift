//
//  ModelEqualityTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

class ModelEqualityTests: XCTestCase {

  func testDeepCopiedModelHasStructuralValueEquality() throws {
    let model = makeModel()
    let copy  = Model(model: model, deep: true)

    XCTAssertEqual(model, copy)
    XCTAssertEqual(copy, model)
    XCTAssertFalse(model.entities[0] === copy.entities[0])
    copy.entities.reverse()
    XCTAssertEqual(model, copy)

    let address = try XCTUnwrap(copy[entity: "Address"] as? ModelEntity)
    address.externalName = "postal_address"
    XCTAssertNotEqual(model, copy)
    XCTAssertNotEqual(copy, model)
  }

  func testCopiedModelPreservesTag() {
    let model = makeModel()
    model.tag = VersionTag(value: 1)

    for deep in [ false, true ] {
      let copy = Model(model: model, deep: deep)
      XCTAssertTrue(eq(model.tag, copy.tag))
      XCTAssertEqual(model, copy)

      copy.tag = VersionTag(value: 2)
      XCTAssertNotEqual(model, copy)
      copy.tag = nil
      XCTAssertNotEqual(model, copy)
    }
  }

  func testModelEqualityAccountsForRepeatedEntities() {
    let person  = ModelEntity(name: "Person")
    let address = ModelEntity(name: "Address")
    let model   = Model(entities: [ person, person, address ])
    let other   = Model(entities: [ person, address, address ])

    XCTAssertNotEqual(model, other)
    XCTAssertNotEqual(other, model)
    XCTAssertEqual(model, Model(model: model, deep: true))
    XCTAssertEqual(Model(entities: []), Model(entities: []))
    XCTAssertNotEqual(model, Model(entities: [ person, address ]))
  }

  func testModelEqualityDetectsChangedAttribute() throws {
    let model  = makeModel()
    let copy   = Model(model: model, deep: true)
    let person = try XCTUnwrap(copy[entity: "Person"])
    let id     = try XCTUnwrap(person[attribute: "id"] as? ModelAttribute)
    id.columnName = "different_id"

    XCTAssertNotEqual(model, copy)
    XCTAssertNotEqual(copy, model)
  }

  func testModelEqualityDetectsChangedRelationship() throws {
    let model  = makeModel()
    let copy   = Model(model: model, deep: true)
    let person = try XCTUnwrap(copy[entity: "Person"])
    let relationship = try XCTUnwrap(
      person[relationship: "addresses"] as? ModelRelationship)
    relationship.updateRule = .cascade

    XCTAssertNotEqual(model, copy)
    XCTAssertNotEqual(copy, model)
  }

  func testAttributeEqualityThroughTypeErasure() {
    let lhs: Attribute = ModelAttribute(name: "id", column: "person_id")
    let rhs = AlternateAttribute(name: "id", column: "person_id")

    XCTAssertTrue(lhs.isEqual(to: rhs as Any))
    XCTAssertTrue(rhs.isEqual(to: lhs as Any))
    XCTAssertTrue(eq(lhs, rhs))
    rhs.columnName = "other_id"
    XCTAssertFalse(eq(lhs, rhs))
    XCTAssertFalse(lhs.isEqual(to: nil))
    XCTAssertFalse(lhs.isEqual(to: "id"))
  }

  func testEntityEqualityThroughTypeErasure() throws {
    let model = makeModel()
    let copy  = Model(model: model, deep: true)
    let lhs   = try XCTUnwrap(model[entity: "Person"])
    let rhs   = try XCTUnwrap(copy[entity: "Person"] as? ModelEntity)

    XCTAssertTrue(lhs.isEqual(to: rhs as Any))
    XCTAssertTrue(rhs.isEqual(to: lhs as Any))
    XCTAssertTrue(eq(lhs, rhs))
    rhs.schemaName = "other_schema"
    XCTAssertFalse(eq(lhs, rhs))
    XCTAssertFalse(lhs.isEqual(to: nil))
    XCTAssertFalse(lhs.isEqual(to: "Person"))
  }

  func testRelationshipEqualityThroughTypeErasure() throws {
    let model  = makeModel()
    let copy   = Model(model: model, deep: true)
    let person = try XCTUnwrap(model[entity: "Person"])
    let other  = try XCTUnwrap(copy[entity: "Person"])
    let lhs    = try XCTUnwrap(person[relationship: "addresses"])
    let rhs    = try XCTUnwrap(other[relationship: "addresses"])

    XCTAssertTrue(lhs.isEqual(to: rhs as Any))
    XCTAssertTrue(rhs.isEqual(to: lhs as Any))
    XCTAssertTrue(eq(lhs, rhs))
    XCTAssertFalse(lhs.isEqual(to: nil))
    XCTAssertFalse(lhs.isEqual(to: "addresses"))
  }

  func testDisconnectedRelationshipsKeepDestinationNames() throws {
    let model  = makeModel()
    let person = try XCTUnwrap(model[entity: "Person"])
    let source = try XCTUnwrap(person[relationship: "addresses"])
    let lhs    = ModelRelationship(relationship: source, disconnect: true)
    let rhs    = ModelRelationship(relationship: source, disconnect: true)

    XCTAssertTrue(lhs == rhs)
    XCTAssertTrue(source.isEqual(to: lhs as Any))
    XCTAssertTrue(lhs.isEqual(to: source as Any))
    rhs.destinationEntityName = "OtherAddress"
    XCTAssertFalse(lhs == rhs)
  }

  func testRelationshipIdentityShortcutsAvoidEndpointNames() {
    let source = NameTrackingEntity(name: "Person")
    let target = NameTrackingEntity(name: "Address")
    let lhs = ModelRelationship(name: "addresses", isToMany: true,
                                source: source, destination: target)
    let rhs = ModelRelationship(relationship: lhs)
    source.nameReadCount = 0
    target.nameReadCount = 0

    XCTAssertTrue(lhs == rhs)
    XCTAssertEqual(source.nameReadCount, 0)
    XCTAssertEqual(target.nameReadCount, 0)

    rhs.constraintName = "different_constraint"
    XCTAssertFalse(lhs == rhs)
    rhs.constraintName = nil
    rhs.joins = [ Join(source: "id", destination: "personID") ]
    XCTAssertFalse(lhs == rhs)
    XCTAssertEqual(source.nameReadCount, 0)
    XCTAssertEqual(target.nameReadCount, 0)
  }

  func testRelationshipDifferentEndpointsFallBackToNames() {
    let source      = NameTrackingEntity(name: "Person")
    let otherSource = NameTrackingEntity(name: "Person")
    let target      = NameTrackingEntity(name: "Address")
    let otherTarget = NameTrackingEntity(name: "Address")
    let lhs = ModelRelationship(name: "addresses", isToMany: true,
                                source: source, destination: target)
    let rhs = ModelRelationship(name: "addresses", isToMany: true,
                                source: otherSource, destination: otherTarget)
    source.nameReadCount      = 0
    otherSource.nameReadCount = 0
    target.nameReadCount      = 0
    otherTarget.nameReadCount = 0

    XCTAssertTrue(lhs == rhs)
    XCTAssertEqual(source.nameReadCount, 1)
    XCTAssertEqual(otherSource.nameReadCount, 1)
    XCTAssertEqual(target.nameReadCount, 1)
    XCTAssertEqual(otherTarget.nameReadCount, 1)

    let differentTarget = NameTrackingEntity(name: "OtherAddress")
    rhs.destinationEntity = differentTarget
    XCTAssertFalse(lhs == rhs)
    XCTAssertFalse(rhs == lhs)
  }

  func testRelationshipEqualityIncludesFlattenedPath() {
    let entity = ModelEntity(name: "Person")
    let lhs    = ModelRelationship(name: "addresses", source: entity)
    let rhs    = ModelRelationship(name: "addresses", source: entity)
    lhs.relationshipPath = "employer.addresses"
    rhs.relationshipPath = "company.addresses"

    XCTAssertFalse(lhs == rhs)
  }

  func testUnconnectedJoinsCompareNames() {
    let join = Join(source: "id", destination: "personID")

    XCTAssertEqual(join, Join(source: "id", destination: "personID"))
    XCTAssertNotEqual(join, Join(source: "otherID", destination: "personID"))
    XCTAssertNotEqual(join, Join(source: "id", destination: "otherID"))
  }

  func testJoinEqualityIgnoresConnectionIdentity() {
    let source      = ModelAttribute(name: "id")
    let destination = ModelAttribute(name: "personID")
    let otherSource = ModelAttribute(attribute: source)
    let otherTarget = ModelAttribute(attribute: destination)
    let lhs = Join(source: source, destination: destination)
    var rhs = Join(source: otherSource, destination: otherTarget)

    XCTAssertEqual(lhs, rhs)
    rhs.disconnect()
    XCTAssertEqual(lhs, rhs)
    rhs.source = source
    XCTAssertEqual(lhs, rhs)
  }

  func testEntityEqualityHonorsCustomAttributeEquality() {
    let lhs = ModelEntity(name: "Person")
    let rhs = ModelEntity(name: "Person")
    lhs.attributes = [ TaggedAttribute(value: 1) ]
    rhs.attributes = [ TaggedAttribute(value: 2) ]

    XCTAssertNotEqual(lhs, rhs)
    rhs.attributes = [ TaggedAttribute(value: 1) ]
    XCTAssertEqual(lhs, rhs)
  }

  func testEntityEqualityHonorsCustomRelationshipEquality() {
    let lhs = ModelEntity(name: "Person")
    let rhs = ModelEntity(name: "Person")
    lhs.relationships = [ TaggedRelationship(entity: lhs, value: 1) ]
    rhs.relationships = [ TaggedRelationship(entity: rhs, value: 2) ]

    XCTAssertNotEqual(lhs, rhs)
    rhs.relationships = [ TaggedRelationship(entity: rhs, value: 1) ]
    XCTAssertEqual(lhs, rhs)
  }

  // MARK: - Helpers

  private func makeModel() -> Model {
    let person   = ModelEntity(name: "Person", table: "person")
    let address  = ModelEntity(name: "Address", table: "address")
    let personID = ModelAttribute(name: "id", externalType: "INTEGER")
    let addressPersonID = ModelAttribute(name: "personID",
                                         externalType: "INTEGER")
    person.attributes  = [ personID ]
    address.attributes = [ addressPersonID ]

    let addresses = ModelRelationship(name: "addresses", isToMany: true,
                                      source: person, destination: address)
    addresses.joins = [ Join(source: personID, destination: addressPersonID) ]
    let owner = ModelRelationship(name: "person", source: address,
                                  destination: person)
    owner.joins = [ Join(source: addressPersonID, destination: personID) ]
    person.relationships  = [ addresses ]
    address.relationships = [ owner ]
    return Model(entities: [ person, address ])
  }

  private final class AlternateAttribute: ModelAttribute {}

  private final class NameTrackingEntity: Entity {

    let storedName    : String
    let attributes    = [ Attribute ]()
    let relationships = [ Relationship ]()
    let isPattern     = false
    var nameReadCount = 0

    var name: String {
      nameReadCount += 1
      return storedName
    }

    init(name: String) { storedName = name }
  }

  private final class TaggedAttribute: Attribute {

    let name      = "id"
    let elementID : String? = nil
    let userData  = [ String : Any ]()
    let value     : Int

    init(value: Int) { self.value = value }

    func isEqual(to object: Any?) -> Bool {
      guard let other = object as? TaggedAttribute else { return false }
      return value == other.value
    }
  }

  private final class TaggedRelationship: Relationship {

    unowned let entity: Entity

    let name              = "children"
    let destinationEntity : Entity? = nil
    let relationshipPath  : String? = nil
    let isToMany          = true
    let isPattern         = false
    let joins             = [ Join ]()
    let value             : Int

    init(entity: Entity, value: Int) {
      self.entity = entity
      self.value  = value
    }

    func isEqual(to object: Any?) -> Bool {
      guard let other = object as? TaggedRelationship else { return false }
      return value == other.value
    }
  }

  private struct VersionTag: ModelTag {

    let value: Int

    func isEqual(to object: Any?) -> Bool {
      guard let other = object as? VersionTag else { return false }
      return value == other.value
    }
  }
}
