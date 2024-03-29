//
//  CodableModelTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 13.12.17.
//  Copyright © 2017-2019 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class CodableModelTests: XCTestCase {
  func testBasicSchema() {
    
    class Address : CodableObjectType {
      var objectVersion : Int = 0
      var id            : Int
      var dbStatus      : String
      var companyId     : Int
      var type          : String
      
      var name1         : String?
      var name2         : String?
      var name3         : String?
      var street        : String?
      var zip           : String?
      var zipcity       : String?
      var country       : String?
      var state         : String?
      var district      : String?
    }
    
    let modelOpt = try? Model.createFromTypes(Address.self)
    guard let model = modelOpt else {
      XCTAssertNotNil(modelOpt)
      return
    }
    
    guard let entity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    
    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 14,
                   "attribute counts do not match: \(attrs)")
    
    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")

    let filledModel = ModelSQLizer().sqlizeModel(model)
    // filledModel.dump()
    guard let filledEntity = filledModel[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    XCTAssertEqual(filledEntity.externalName, "address")
  }
  
  
  func testSchemaWithKeyMappings() {
    
    class Person : CodableObjectType {
      var id            : Int
      var isPerson      : Int
      
      var lastname      : String?
      var firstname     : String?
      
      var nonEncodedKey : String = "hidden"
      
      enum CodingKeys: String, CodingKey {
        case id
        case isPerson = "is_person"
        case lastname
        case firstname
      }
    }
    
    let modelOpt = try? Model.createFromTypes(Person.self)
    guard let model = modelOpt else {
      XCTAssertNotNil(modelOpt)
      return
    }
    
    guard let entity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    model.dump()

    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 4,
                   "attribute counts do not match: \(attrs)")
    
    if let attr = entity[attribute: "is_person"] {
      XCTAssertEqual(attr.name, "is_person")
      XCTAssertNil(attr.columnName)
    }
    else {
      XCTFail("entity has no is_person attribute: \(entity)")
    }

    if let attr = entity[attribute: "firstname"] {
      // should not have an external type
      XCTAssertEqual(attr.name, "firstname")
      XCTAssertNil(attr.externalType)
    }
    else {
      XCTFail("entity has no firstname attribute: \(entity)")
    }

    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    let filledModel = ModelSQLizer().sqlizeModel(model)
    // filledModel.dump()
    guard let filledEntity = filledModel[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    XCTAssertEqual(filledEntity.externalName, "person")
  }
  
  func testSchemaWithOptionalAttribute() {
    class Address : CodableObjectType {
      var id            : Int
      var name1         : String?
    }
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    addressEntity.dump()
    XCTAssertEqual(addressEntity.attributes.count, 2,
                   "attribute counts do not match: \(addressEntity.attributes)")
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    guard let name1Attr = addressEntity[attribute: "name1"] else {
      XCTFail("Address entity has no name1 attribute: \(addressEntity)")
      return
    }
    
    XCTAssert(name1Attr.valueType == String.self)
    XCTAssertNotNil(name1Attr.allowsNull, "name1.allowsNull is not set")
    XCTAssertTrue(name1Attr.allowsNull ?? false,
                   "name1.allowsNull is false")
  }
  
  func testSchemaWithoutPrimaryKey() {
    class Address : CodableObjectType {
      var name1 : String?
    }
    // sqlize adds the primary key
    /* w/o SQLize vs w/ SQLize
     entity: <CodableObjectEntity<Address #1> Address Address #1 pkey=id #attrs=2>
       props: name1
       attr: <ModelAttribute id Int>
       attr: <CodeAttribute<Optional<String>> name1 String?>
     entity: <ModelEntity pattern Address[address] 'Address' pkey=id #attrs=2>
       props: id,name1
       attr: <ModelAttribute id Int>
       attr: <ModelAttribute name1 String?>
     */
    let reflector = CodableModelDecoder(options:
                      CodableModelDecoder.Options(sqlize: false))
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    addressEntity.dump()
    XCTAssertEqual(addressEntity.attributes.count, 2) // + generated pkey
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?.first ?? "", "id")
    if let pkey = pkeys?.first {
      XCTAssertNotNil(addressEntity[attribute: pkey])
      XCTAssertFalse(addressEntity[attribute: pkey]?.allowsNull ?? true)
    }
    
    XCTAssertNotNil(addressEntity[attribute: "name1"])
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 1)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
    }
  }

  func testSchemaWithRelationshipsAndForeignKey() {
    class Person : CodableObjectType {
      // TBD: support: let table = "person"
      var id            : Int
      var addresses     : ToMany<Address>
    }
    class Address : CodableObjectType {
      var id            : Int
      var personId      : Int // this is the reverse we want to locate
      var name1         : String?
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person.self))
    #if false // automagic
      XCTAssertNoThrow(try reflector.add(Address.self))
    #endif
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }

    XCTAssertEqual(personEntity .attributes.count, 1)
    XCTAssertEqual(addressEntity.attributes.count, 3)
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")

    XCTAssertEqual(personEntity .relationships.count, 1)
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // original, in-code relationship
    XCTAssertNotNil(personEntity[relationship: "addresses"])
    if let toMany = personEntity[relationship: "addresses"] {
      XCTAssertTrue(toMany.isToMany)
      XCTAssertEqual(toMany.joins.count, 1)
      if let join = toMany.joins.first {
        XCTAssertEqual(join.sourceName,      "id")
        XCTAssertEqual(join.destinationName, "personId")
      }
      XCTAssertEqual(toMany.entity.name,             "Person")
      XCTAssertEqual(toMany.destinationEntity?.name, "Address")
    }
    
    // generated, reverse relationship
    XCTAssertNotNil(addressEntity[relationship: "person"])
    if let toOne = personEntity[relationship: "person"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "personId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
    }
  }
  
  func testSchemaWithToManyWithoutForeignKey() {
    class Person : CodableObjectType {
      // TBD: support: let table = "person"
      var id            : Int
      var addresses     : ToMany<Address>
    }
    class Address : CodableObjectType {
      var id            : Int
      var name1         : String?
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person.self))
    #if false // automagic
      XCTAssertNoThrow(try reflector.add(Address.self))
    #endif
    let model = reflector.buildModel()
    
    #if false // this also needs proper relationships setup
      let filledModel = ModelSQLizer().sqlizeModel(model)
      filledModel.dump()
    #else
      model.dump()
    #endif
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 1)
    XCTAssertEqual(addressEntity.attributes.count, 3) // +1, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(personEntity .relationships.count, 1)
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // original, in-code relationship
    XCTAssertNotNil(personEntity[relationship: "addresses"])
    if let toMany = personEntity[relationship: "addresses"] {
      XCTAssertTrue(toMany.isToMany)
      XCTAssertEqual(toMany.joins.count, 1)
      if let join = toMany.joins.first {
        XCTAssertEqual(join.sourceName,      "id")
        XCTAssertEqual(join.destinationName, "personId")
      }
      XCTAssertEqual(toMany.entity.name,             "Person")
      XCTAssertEqual(toMany.destinationEntity?.name, "Address")
    }
    
    // generated, reverse relationship
    XCTAssertNotNil(addressEntity[relationship: "person"])
    if let toOne = personEntity[relationship: "person"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "personId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("id"))
      XCTAssertTrue(names.contains("name1"))
    }
  }
  
  func testSchemaWithOptionalToOne() {
    class Person : CodableObjectType {
      var firstname : String
    }
    class Address : CodableObjectType {
      var name1     : String?
      // var owner  : ToOne<Person?> // this would be better
      var owner     : ToOne<Person>?
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person .self))
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // +1, generated pkey
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated pkey+fkey
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // original, in-code relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
    }
    
    XCTAssertNotNil(addressEntity[attribute: "ownerId"])
    if let fkey = addressEntity[attribute: "ownerId"] {
      XCTAssertNotNil(fkey.allowsNull, "opt foreign key nullabilty not set")
      XCTAssertTrue(fkey.allowsNull ?? false,
                    "opt foreign key does not allow null")
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testSchemaWithToOne() {
    class Person : CodableObjectType {
      var firstname : String
    }
    class Address : CodableObjectType {
      var name1     : String?
      var owner     : ToOne<Person>
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person .self))
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // +1, generated pkey
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated pkey+fkey
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // original, in-code relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
    }
    
    XCTAssertNotNil(addressEntity[attribute: "ownerId"])
    if let fkey = addressEntity[attribute: "ownerId"] {
      XCTAssertNotNil(fkey.allowsNull, "opt foreign key nullabilty not set")
      XCTAssertFalse(fkey.allowsNull ?? true, "opt foreign key does allow null")
    }

    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }


  func testSchemaWithInlineToOneInOrder() {
    // TODO: test the case where Address is added *before* Person
    class Person : CodableObjectType {
      var name  : String
    }
    class Address : CodableObjectType {
      var name1 : String?
      var owner : Person
    }
    
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person.self))
    XCTAssertNoThrow(try reflector.add(Address.self))
      // this is NOT automagic with full typing info, because the keyed
      // container is type erased!
    let model = reflector.buildModel()

    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // 1 generated
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
      XCTAssertTrue(toOne.isMandatory)
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testSchemaWithInlineToOneSourceBeforeTarget() {
    // test the case where Address is added *before* Person
    class Person : CodableObjectType {
      var name  : String
    }
    class Address : CodableObjectType {
      var name1 : String?
      var owner : Person
    }
    
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Address.self))
    XCTAssertNoThrow(try reflector.add(Person.self))
      // ^^ this needs to trigger the entity-replacement logic!
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // 1 generated
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
      XCTAssertTrue(toOne.isMandatory)
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
    // do not included generated, but does include relationships
    // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testSchemaWithInlineToOneSourceNoExplicitTarget() {
    // test the case where Address is added *before* Person
    class Person : CodableObjectType {
      var name  : String
    }
    class Address : CodableObjectType {
      var name1 : String?
      var owner : Person
    }
    
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Address.self))
      // ^^ this needs to trigger the use-temporary-entity logic!
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // 1 generated
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
      XCTAssertTrue(toOne.isMandatory)
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
    // do not included generated, but does include relationships
    // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testSchemaWithOptionalInlineToOneSourceNoExplicitTarget() {
    // test the case where Address is added *before* Person
    class Person : CodableObjectType {
      var name  : String
    }
    class Address : CodableObjectType {
      var name1 : String?
      var owner : Person?
    }
    
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Address.self))
      // ^^ this needs to trigger the use-temporary-entity logic!
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // 1 generated
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
      XCTAssertFalse(toOne.isMandatory)
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
    // do not included generated, but does include relationships
    // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testSchemaWithInlineArrayToMany() {
    // Note: This works w/ Swift 4.0.3 (i.e. Xcode 9.2 on Travis), but loops
    //       w/ Swift 4.0.0 (i.e. Xcode 9 on Travis)
    class Person : CodableObjectType {
      var addresses : [ Address ]
    }
    class Address : CodableObjectType {
      var name1     : String?
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person.self))
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()

    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 1) // 1 generated
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(personEntity .relationships.count, 1)
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // original, in-code relationship
    XCTAssertNotNil(personEntity[relationship: "addresses"])
    if let toMany = personEntity[relationship: "addresses"] {
      XCTAssertTrue(toMany.isToMany)
      XCTAssertEqual(toMany.joins.count, 1)
      if let join = toMany.joins.first {
        XCTAssertEqual(join.sourceName,      "id")
        XCTAssertEqual(join.destinationName, "personId")
      }
      XCTAssertEqual(toMany.entity.name,             "Person")
      XCTAssertEqual(toMany.destinationEntity?.name, "Address")
    }
    
    // generated, reverse relationship
    XCTAssertNotNil(addressEntity[relationship: "person"])
    if let toOne = personEntity[relationship: "person"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "personId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 1)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
    }
    XCTAssertEqual(personEntity.classPropertyNames?.count ?? -1, 1)
    // do not included generated, but does include relationships
    // ... unless those are generated too ;-)
    if let names = personEntity.classPropertyNames {
      XCTAssertTrue(names.contains("addresses"))
    }
  }
  
  
  // MARK: - Cycles
  
  func testSchemaWithToCycle() {
    class Person : CodableObjectType {
      var firstname : String
      var addresses : ToMany<Address>
    }
    class Address : CodableObjectType {
      var name1     : String?
      var owner     : ToOne<Person>
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person .self))
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // +1, generated pkey
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated pkey+fkey
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    XCTAssertEqual(personEntity .relationships.count, 1)

    
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
    }
    
    XCTAssertNotNil(personEntity[relationship: "addresses"])
    if let toMany = personEntity[relationship: "addresses"] {
      XCTAssertTrue(toMany.isToMany)
      XCTAssertEqual(toMany.joins.count, 1)
      if let join = toMany.joins.first {
        XCTAssertEqual(join.sourceName,      "id")
        XCTAssertEqual(join.destinationName, "ownerId")
      }
      XCTAssertEqual(toMany.entity.name,             "Person")
      XCTAssertEqual(toMany.destinationEntity?.name, "Address")
    }

    // validate class properties
    
    XCTAssertEqual(personEntity.classPropertyNames?.count ?? -1, 2)
    if let names = personEntity.classPropertyNames {
      XCTAssertTrue(names.contains("firstname"))
      XCTAssertTrue(names.contains("addresses"))
    }
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testSchemaWithToOneInlineCycle() {
    // This needs to throw - w/o optional this can't create
    
    class Person : CodableObjectType {
      var firstname  : String
      var creditCard : CreditCard
    }
    class CreditCard : CodableObjectType {
      var number     : String
      var owner      : Person
    }
    
    let reflector = CodableModelDecoder()
    #if false
      XCTAssertThrowsError() { error in
        XCTAssertEqual(error as? CodableModelDecoder.Error,
                       CodableModelDecoder.Error.reflectionDepthExceeded)
      }
    #else
      do {
        try reflector.add(Person.self)
        XCTFail("did not throw error")
      }
      catch let error as CodableModelDecoder.Error {
        if case .reflectionDepthExceeded = error {
          // good
          return
        }
        else {
          XCTFail("unexpected error: \(error)")
        }
      }
      catch {
        XCTFail("unexpected error")
      }
    #endif

    // we should never get here
    let model = reflector.buildModel()
    model.dump() // crashes on unowned reference in -description
    XCTFail("Reached unexpected point")
  }
  
  func testSchemaWithOptionalToOneInlineCycle() {
    
    class Person : CodableObjectType {
      var firstname  : String
      var creditCard : CreditCard?
    }
    class CreditCard : CodableObjectType {
      var number     : String
      var owner      : Person
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person .self))
    XCTAssertNoThrow(try reflector.add(CreditCard.self))
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let ccEntity = model[entity: "CreditCard"] else {
      XCTFail("model has no CreditCard entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity.attributes.count, 3) // +2 generated
    XCTAssertEqual(ccEntity    .attributes.count, 3) // +2, generated!
    
    let pkeys = ccEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(ccEntity.relationships.count, 1)
    
    // relationship
    
    XCTAssertNotNil(ccEntity[relationship: "owner"])
    if let toOne = ccEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "CreditCard")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
      XCTAssertTrue(toOne.isMandatory) // FIXME: fails, why?
    }
    
    XCTAssertNotNil(personEntity[relationship: "creditCard"])
    if let toOne = personEntity[relationship: "creditCard"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "creditCardId") // TBD
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Person")
      XCTAssertEqual(toOne.destinationEntity?.name, "CreditCard")
      XCTAssertFalse(toOne.isMandatory)
    }

    // validate class properties
    
    XCTAssertEqual(ccEntity.classPropertyNames?.count ?? -1, 2)
    // do not included generated, but does include relationships
    // ... unless those are generated too ;-)
    if let names = ccEntity.classPropertyNames {
      XCTAssertTrue(names.contains("number"))
      XCTAssertTrue(names.contains("owner"))
    }
    
    XCTAssertEqual(personEntity.classPropertyNames?.count ?? -1, 2)
    // do not included generated, but does include relationships
    // ... unless those are generated too ;-)
    if let names = personEntity.classPropertyNames {
      XCTAssertTrue(names.contains("firstname"))
      XCTAssertTrue(names.contains("creditCard"))
    }
  }
  
  func testSchemaWithToManyInlineCycle() {
    // FIXME: This actually works. The second decoding step (address
    // decoding Person again due to `owner`), need to already know that we are
    // decoding the relationship and return nil)
    
    class Person : CodableObjectType {
      var firstname : String
      var addresses : [ Address ]
    }
    class Address : CodableObjectType {
      var name1     : String?
      var owner     : Person
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Person .self))
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()
    
    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssertEqual(personEntity .attributes.count, 2) // +1, generated pkey
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated pkey+fkey
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    XCTAssertEqual(personEntity .relationships.count, 1)

    
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
    }
    
    XCTAssertNotNil(personEntity[relationship: "addresses"])
    if let toMany = personEntity[relationship: "addresses"] {
      XCTAssertTrue(toMany.isToMany)
      XCTAssertEqual(toMany.joins.count, 1)
      if let join = toMany.joins.first {
        XCTAssertEqual(join.sourceName,      "id")
        XCTAssertEqual(join.destinationName, "ownerId")
      }
      XCTAssertEqual(toMany.entity.name,             "Person")
      XCTAssertEqual(toMany.destinationEntity?.name, "Address")
    }

    // validate class properties
    
    XCTAssertEqual(personEntity.classPropertyNames?.count ?? -1, 2)
    if let names = personEntity.classPropertyNames {
      XCTAssertTrue(names.contains("firstname"))
      XCTAssertTrue(names.contains("addresses"))
    }
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testImplicitEntityByReference() {
    // we also want to get an entity for 'Person', even though we do not add
    // it to the decoder below
    class Person : CodableObjectType {
      var name  : String
    }
    class Address : CodableObjectType {
      var name1 : String?
      var owner : Person
    }
    
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()

    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }

    // We'd like to have that as a `CodableObjectEntity<Person>`, but it looks
    // like that is not yet possible in Swift
    //   https://gist.github.com/helje5/a3c26a63092a57dd61f5a1dcb7c8580e
    XCTAssert(personEntity  is DecodableEntity<Person>,
              "person entity is not a DecodableEntity<T>")
    XCTAssert(addressEntity is CodableObjectEntity<Address>,
              "address entity is not a CodableEntity<T>")

    XCTAssertEqual(personEntity .attributes.count, 2) // 1 generated
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
      XCTAssertTrue(toOne.isMandatory)
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testImplicitEntityExplicitToOne() {
    // we also want to get a *typed* entity for 'Person', even though we do not
    // add it to the decoder below
    class Person : CodableObjectType {
      var name  : String
    }
    class Address : CodableObjectType {
      var name1 : String?
      var owner : ToOne<Person>
    }
    
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Address.self))
      // this is NOT automagic with full typing info, because the keyed
      // container is type erased!
    let model = reflector.buildModel()

    model.dump()
    
    guard let addressEntity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    guard let personEntity = model[entity: "Person"] else {
      XCTFail("model has no Person entity: \(model)")
      return
    }
    
    XCTAssert(personEntity  is CodableObjectEntity<Person>,
              "person entity is not a CodableEntity<T>")
    XCTAssert(addressEntity is CodableObjectEntity<Address>,
              "address entity is not a CodableEntity<T>")

    XCTAssertEqual(personEntity .attributes.count, 2) // 1 generated
    XCTAssertEqual(addressEntity.attributes.count, 3) // +2, generated!
    
    let pkeys = addressEntity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
    
    XCTAssertEqual(addressEntity.relationships.count, 1)
    
    // relationship
    XCTAssertNotNil(addressEntity[relationship: "owner"])
    if let toOne = personEntity[relationship: "owner"] {
      XCTAssertFalse(toOne.isToMany)
      XCTAssertEqual(toOne.joins.count, 1)
      if let join = toOne.joins.first {
        XCTAssertEqual(join.sourceName,      "ownerId")
        XCTAssertEqual(join.destinationName, "id")
      }
      XCTAssertEqual(toOne.entity.name,             "Address")
      XCTAssertEqual(toOne.destinationEntity?.name, "Person")
      XCTAssertTrue(toOne.isMandatory)
    }
    
    // validate class properties
    
    XCTAssertEqual(addressEntity.classPropertyNames?.count ?? -1, 2)
      // do not included generated, but does include relationships
      // ... unless those are generated too ;-)
    if let names = addressEntity.classPropertyNames {
      XCTAssertTrue(names.contains("name1"))
      XCTAssertTrue(names.contains("owner"))
    }
  }
  
  func testBasicPlainCodableSchema() {
    
    class Address : Codable {
      var objectVersion : Int = 0
      var id            : Int
      var dbStatus      : String
      var companyId     : Int
      var type          : String
      
      var name1         : String?
      var name2         : String?
      var name3         : String?
      var street        : String?
      var zip           : String?
      var zipcity       : String?
      var country       : String?
      var state         : String?
      var district      : String?
    }
    
    let reflector = CodableModelDecoder()
    XCTAssertNoThrow(try reflector.add(Address.self))
    let model = reflector.buildModel()
    model.dump()
    
    guard let entity = model[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    
    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 14,
                   "attribute counts do not match: \(attrs)")
    
    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")

    let filledModel = ModelSQLizer().sqlizeModel(model)
    // filledModel.dump()
    guard let filledEntity = filledModel[entity: "Address"] else {
      XCTFail("model has no Address entity: \(model)")
      return
    }
    XCTAssertEqual(filledEntity.externalName, "address")
  }
  
  func testPlainCodableContactsDBModel() {
    let model = PlainCodableContactsDBModel.model
    model.dump()
    
    guard let address = model[entity: "Address"] else {
      XCTAssertNotNil(model[entity: "Address"], "Model has no Address?")
      return
    }
    guard let person = model[entity: "Person"] else {
      XCTAssertNotNil(model[entity: "Person"],  "Model has no Person?")
      return
    }
    
    XCTAssertEqual(address.classPropertyNames?.count ?? 0, 6,
                   "unexpected class properties: \(address.classPropertyNames ?? [])")
    XCTAssertEqual(person.classPropertyNames?.count  ?? 0, 4,
                   "unexpected class properties: \(person.classPropertyNames ?? [])")

    XCTAssertEqual(address.relationships.count, 1)
    XCTAssertEqual(person .relationships.count, 1)
  }
  
  func testPlainCodableContactsDBModelSQLize() {
    let model    = PlainCodableContactsDBModel.model
    let sqlModel = PlainCodableContactsDBModel.sqlModel
    
    print("Codable Model:")
    model.dump()
    print("SQL Model:")
    sqlModel.dump()
    print("---")

    guard let address = model[entity: "Address"] else {
      XCTAssertNotNil(model[entity: "Address"], "Model has no Address?")
      return
    }
    guard let person = model[entity: "Person"] else {
      XCTAssertNotNil(model[entity: "Person"],  "Model has no Person?")
      return
    }
    guard let sqlAddress = sqlModel[entity: "Address"] else {
      XCTAssertNotNil(model[entity: "Address"], "Model has no Address?")
      return
    }
    guard let sqlPerson = sqlModel[entity: "Person"] else {
      XCTAssertNotNil(model[entity: "Person"],  "Model has no Person?")
      return
    }
    
    // This is right, we are doing PlainCodableContactsDBModel,
    // where the classes are NOT `CodableObjectType`!!!
    typealias M = PlainCodableContactsDBModel
    XCTAssert(address    is DecodableEntity<M.Address>)
    XCTAssert(person     is DecodableEntity<M.Person>)
    XCTAssert(sqlAddress is DecodableEntity<M.Address>)
    XCTAssert(sqlPerson  is DecodableEntity<M.Person>)

    XCTAssertEqual(address.classPropertyNames?.count ?? 0, 6,
                   "unexpected class properties: " +
                   "\(address.classPropertyNames ?? [])")
    XCTAssertEqual(person.classPropertyNames?.count  ?? 0, 4,
                   "unexpected class properties: " +
                   "\(person.classPropertyNames ?? [])")
    XCTAssertEqual(address.relationships.count, 1)
    XCTAssertEqual(person .relationships.count, 1)

    XCTAssertEqual(address   .classPropertyNames?.count ?? 0,
                   sqlAddress.classPropertyNames?.count ?? 0,
                   "unexpected class properties:" +
                   " \(address.classPropertyNames ?? [])" +
                   " vs \(sqlAddress.classPropertyNames ?? [])")
    XCTAssertEqual(person   .classPropertyNames?.count  ?? 0,
                   sqlPerson.classPropertyNames?.count  ?? 0,
                   "unexpected class properties:" +
                   " \(person.classPropertyNames ?? [])" +
                   " vs \(sqlPerson.classPropertyNames ?? [])")

    XCTAssertEqual(address.relationships.count, sqlAddress.relationships.count)
    XCTAssertEqual(person .relationships.count, sqlPerson .relationships.count)
    XCTAssertEqual(address.attributes   .count, sqlAddress.attributes   .count)
    XCTAssertEqual(person .attributes   .count, sqlPerson .attributes   .count)
  }
  
  
  // MARK: - Non-ObjC Swift Support

  static var allTests = [
    ( "testBasicSchema",                  testBasicSchema                  ),
    ( "testSchemaWithKeyMappings",        testSchemaWithKeyMappings        ),
    ( "testSchemaWithOptionalAttribute",  testSchemaWithOptionalAttribute  ),
    ( "testSchemaWithoutPrimaryKey",      testSchemaWithoutPrimaryKey      ),
    ( "testSchemaWithRelationshipsAndForeignKey",
       testSchemaWithRelationshipsAndForeignKey ),
    ( "testSchemaWithToManyWithoutForeignKey",
       testSchemaWithToManyWithoutForeignKey ),
    ( "testSchemaWithOptionalToOne",      testSchemaWithOptionalToOne      ),
    ( "testSchemaWithToOne",              testSchemaWithToOne              ),
    ( "testSchemaWithInlineToOneInOrder", testSchemaWithInlineToOneInOrder ),
    ( "testSchemaWithInlineToOneSourceBeforeTarget",
       testSchemaWithInlineToOneSourceBeforeTarget ),
    ( "testSchemaWithInlineToOneSourceNoExplicitTarget",
       testSchemaWithInlineToOneSourceNoExplicitTarget ),
    ( "testSchemaWithOptionalInlineToOneSourceNoExplicitTarget",
       testSchemaWithOptionalInlineToOneSourceNoExplicitTarget ),
    ( "testSchemaWithInlineArrayToMany",  testSchemaWithInlineArrayToMany  ),
    ( "testSchemaWithToCycle",            testSchemaWithToCycle            ),
    ( "testSchemaWithToOneInlineCycle",   testSchemaWithToOneInlineCycle   ),
    ( "testSchemaWithOptionalToOneInlineCycle",
       testSchemaWithOptionalToOneInlineCycle ),
    ( "testSchemaWithToManyInlineCycle",  testSchemaWithToManyInlineCycle  ),
    ( "testImplicitEntityByReference",    testImplicitEntityByReference    ),
    ( "testImplicitEntityExplicitToOne",  testImplicitEntityExplicitToOne  ),
    ( "testBasicPlainCodableSchema",      testBasicPlainCodableSchema      ),
    ( "testPlainCodableContactsDBModel",  testPlainCodableContactsDBModel  ),
    ( "testPlainCodableContactsDBModelSQLize",
      testPlainCodableContactsDBModelSQLize )
  ]
}

internal extension Model {
  
  func dump(prefix: String = "") {
    print("\(prefix)got model:", self)
    for entity in entities {
      entity.dump(prefix: prefix + "  ")
    }
  }
  
}

internal extension Entity {
  
  func dump(prefix: String = "  ") {
    print("\(prefix)entity: \(self)")
    if let props = classPropertyNames {
      print("\(prefix)  props: \(props.joined(separator: ","))")
    }
    for attr in attributes {
      print("\(prefix)  attr: \(attr)")
    }
    for rs in relationships {
      print("\(prefix)  rs:   \(rs)")
    }
  }
}
