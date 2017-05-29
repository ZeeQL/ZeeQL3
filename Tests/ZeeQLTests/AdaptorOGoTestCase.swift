//
//  AdaptorOGoTestCase.swift
//  ZeeQL
//
//  Created by Helge Hess on 02/03/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class AdaptorOGoTestCase: XCTestCase {
  // Is there a better way to share test cases?
  
  var adaptor : Adaptor! {
    XCTAssertNotNil(nil, "override in subclass")
    return nil
  }
  
  let printResults = true
  
  let entity : Entity = {
    let e = ModelEntity(name: "Person", table: "person")
    e.attributes = [
      ModelAttribute(name: "id",    column: "company_id",
                     externalType: "INTEGER"),
      ModelAttribute(name: "login", externalType: "VARCHAR(255)"),
      ModelAttribute(name: "name",  externalType: "VARCHAR(255)")
    ]
    e.primaryKeyAttributeNames = [ "id" ]
    return e
  }()
  
  struct Qualifiers {
    static let templateUser =
      qualifierWith(format: "login = %@ AND id = %i", "template",9999)
  }
  
  
  // MARK: - tests
  
  func testRawAdaptorChannelQuery() throws {
    var resultCount = 0
    let sql = "SELECT company_id AS id, login, name FROM person LIMIT 5"

    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    try channel.querySQL(sql) { result in
      resultCount += 1
      if printResults {
        print("  Result \(resultCount):")
        dump(row: result)
      }
    }
    
    XCTAssert(resultCount >= 2, "there should be at least template&root")
  }
  
  func testEvaluateQueryExpression() throws {
    let fs = ModelFetchSpecification(entity: entity,
                                     qualifier: Qualifiers.templateUser)
    
    let expr = adaptor.expressionFactory.selectExpressionForAttributes(
      entity.attributes, lock: true, fs, entity
    )
    
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    var results = [ AdaptorRecord ]()
    try channel.evaluateQueryExpression(expr, entity.attributes) { record in
      results.append(record)
    }
    if printResults {
      print("Query results: #\(results.count): \(expr.statement)")
      for result in results {
        print("  Result:")
        dump(row: result)
      }
    }
    
    if results.count != 1 {
      print("UNEXPECTED COUNT: \(results)")
      
    }
    XCTAssertEqual(results.count, 1, "there should be only one 'template'")
  }
  
  func testRawTypeSafeQuery() throws {
    try adaptor.select("SELECT company_id, name FROM person LIMIT 3") {
      ( id: Int, name: String ) in
      if printResults {
        print("person, \(id)[\(type(of: id))] \(name)[\(type(of: name))]")
      }
    }
  }
  
  func testSimpleTX() throws {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    try channel.begin()
    // hm, doesn't work: defer { try channel.rollback() }
    
    try channel.querySQL("SELECT COUNT(*) AS count FROM person") { record in
      if let count = record["count"] {
        let i = Int("\(count)") // TODO: improve, APR should reflect
        XCTAssertNotNil(i, "could not convert count into int")
        XCTAssert(i! >= 2, "should be at least two ...")
      }
      else {
        XCTAssertNotNil(record["count"])
      }
    }
    
    try channel.rollback()
  }
  
  func testAdaptorDataSourceFindByID() throws {
    let ds = AdaptorDataSource(adaptor: adaptor, entity: entity)
    
    let templateUser = try ds.findBy(id: 9999)
    XCTAssertNotNil(templateUser)
    XCTAssertNotNil(templateUser!["id"])
    XCTAssertNotNil(templateUser!["login"])
    
    if printResults {
      if let result = templateUser {
        print("  Result:")
        dump(row: result)
      }
    }
  }
  
  func testBasicReflection() throws {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    let dbs = try channel.describeDatabaseNames()
    if printResults { print("Databases: \(dbs)") }
    XCTAssertFalse(dbs.isEmpty, "got no databases")
    
    let tables = try channel.describeTableNames()
    if printResults { print("Tables: \(tables)") }
    XCTAssertFalse(tables.isEmpty, "got no tables")
    XCTAssertTrue(tables.contains("company"), "missing OGo 'company' table")
    XCTAssertTrue(tables.contains("address"), "missing OGo 'address' table")
    XCTAssertTrue(tables.contains("object_acl"),
                  "missing OGo 'object_acl' table")
    
    let seqs = try channel.describeSequenceNames()
    if printResults { print("Sequences: \(seqs)") }
    #if false // SQLite has no sequences
    XCTAssertFalse(seqs.isEmpty, "got no sequences")
    XCTAssertTrue(seqs.contains("key_generator"), "missing OGo key seq")
    #endif
  }
  
  func testTableReflection() throws {
    let channel = try adaptor.openChannel()
    defer { adaptor.releaseChannel(channel) }
    
    let companyEntity = try channel.describeEntityWithTableName("company")
    XCTAssertNotNil(companyEntity)
    if printResults {
      print("Company: \(companyEntity as Optional)")
      print("  pkeys: \(companyEntity!.primaryKeyAttributeNames as Optional)")
    }
    XCTAssertEqual(companyEntity!.name,         "company")
    XCTAssertEqual(companyEntity!.externalName, "company")
    XCTAssertNotNil(companyEntity!.primaryKeyAttributeNames)
    XCTAssertEqual(companyEntity!.primaryKeyAttributeNames!, [ "company_id" ])
    
    let nameAttr = companyEntity![attribute: "name"]
    XCTAssertNotNil(nameAttr)
    XCTAssertNotNil(nameAttr?.externalType)
    if printResults {
      print("  name: \(nameAttr as Optional) \(nameAttr?.externalType as Optional)")
    }
    XCTAssert(nameAttr!.externalType!.hasPrefix("VARCHAR"))

    let idAttr = companyEntity![attribute: "company_id"]
    XCTAssertNotNil(idAttr)
    XCTAssertNotNil(idAttr?.externalType)
    if printResults {
      print("  id:   \(idAttr as Optional) \(idAttr?.externalType as Optional)")
    }
    XCTAssert(idAttr!.externalType!.hasPrefix("INT"))
  }
  
  #if false // the inner class cannot refer to 'db'
  func testRecordAttachedSchema() throws {
    let db = Database(adaptor: adaptor)
    
    class Person : ActiveRecord {
      override class var database : Database { return db }
      
      let id        : Int     = -1
      let login     : String  = ""
      let name      : String  = ""
      let firstname : String? = ""
    }
    
    let p = Person(database: nil, entity: nil)
    print("Entity: \(p.entity)")
    
    let ds = ActiveDataSource<Person>(database: db, entity: p.entity)
    
    // fails:
    let person1 = try ds.findBy(id: 10000)
    if printResults { print("got person: \(person1)") }
    
    let person = Person.findBy(id: 10000)
    if printResults { print("got person: \(person)") }
  }
  #endif
  
  func testCodeSchema() throws {
    let db = Database(adaptor: adaptor)
    
    class OGoObject : ActiveRecord {
      // TODO: actuall add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
      let dbStatus      = Info.String(column: "db_status", width: 50)
    }
    
    
    class Address : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        
        let id            = Info.Int(column: "address_id")
        let companyId     = Info.Int(column: "company_id")
        let type          = Info.String(width: 50) // TODO: an enum?
        let name1         : String? = nil
        let name2         : String? = nil
        let name3         : String? = nil
        let street        : String? = nil
        let zip           = Info.OptString(width: 50)
        let zipcity       : String? = nil
        let country       : String? = nil
        let state         : String? = nil
        let district      : String? = nil
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    class Person : OGoObject {
      class Entity : OGoCodeEntity<Person> {
        
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    let ds = ActiveDataSource<Address>(database: db)
    if printResults { print("ds: \(ds)") }

    var fs = ModelFetchSpecification(entity: ds.entity!)
    fs.fetchLimit = 12
    fs.setQualifier("SQL[name1 IS NOT NULL AND LENGTH(name1) > 0]")
    ds.fetchSpecification = fs
    
    let objects = try ds.fetchObjects()
    
    if printResults {
      print("got: #\(objects.count)")
      
      for address in objects {
        print("  Address: \(address)")
      }
    }
  }
  
  
  func testCodeSchemaWithJoinQualifier() throws {
    let db = Database(adaptor: adaptor)

    class OGoObject : ActiveRecord {
      // TODO: actuall add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
    }
    
    
    class Address : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Address> {
        let table         = "address"
        let id            = Info.Int(column: "address_id")
        
        let dbStatus      = Info.String(column: "db_status", width: 50)
        
        let companyId     = Info.Int(column: "company_id")
        
        let type          = Info.String(width: 50) // TODO: an enum?
        
        let name1         : String? = nil
        let name2         : String? = nil
        let name3         : String? = nil
        let street        : String? = nil
        let zip           = Info.OptString(width: 50)
        let zipcity       : String? = nil
        let country       : String? = nil
        let state         : String? = nil
        let district      : String? = nil
        
        let person        = ToOne<Person>()
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    class Person : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let isPerson      = Info.Int(column: "is_person")
        
        let login         = Info.OptString(width: 50)
        let isLocked      = Info.Int(column: "is_locked")
        let number        = Info.String(width: 100)
        
        let lastname      = Info.OptString(column: "name")
        let firstname     : String? = nil
        let middlename    : String? = nil
        
        let addresses     = ToMany<Address>(on: "companyId")
      }
      static let entity : ZeeQL.Entity = Entity()
    }

    // relship qualifier fetch (fetch addresses of a specific person)
    let ds = ActiveDataSource<Address>(database: db)
    ds.fetchSpecification =
      ModelFetchSpecification(entity: Address.entity, "person.login != nil",
                              limit: 4)
          
    let objects = try ds.fetchObjects()
    if printResults {
      print("got: #\(objects.count)")
    
      for address in objects {
        print("  Address: \(address)")
      }
    }
    
    XCTAssert(objects.count > 0) // an empty DB fails on this
  }

  func testCodeSchemaWithRelshipPrefetch() throws {
    let db = Database(adaptor: adaptor)

    class OGoObject : ActiveRecord {
      // TODO: actually add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
    }
    
    
    class Address : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        let id            = Info.Int(column: "address_id")

        let dbStatus      = Info.String(column: "db_status", width: 50)
        
        let companyId     = Info.Int(column: "company_id")
        
        let type          = Info.String(width: 50) // TODO: an enum?
        
        let name1         : String? = nil
        let name2         : String? = nil
        let name3         : String? = nil
        let street        : String? = nil
        let zip           = Info.OptString(width: 50)
        let zipcity       : String? = nil
        let country       : String? = nil
        let state         : String? = nil
        let district      : String? = nil
        
        let person        = ToOne<Person>() // auto: key: "company_id")
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    class Person : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let isPerson      = Info.Int(column: "is_person")
        
        let login         = Info.OptString(width: 50)
        let isLocked      = Info.Int(column: "is_locked")
        let number        = Info.String(width: 100)
        
        let lastname      = Info.OptString(column: "name")
        let firstname     : String? = nil
        let middlename    : String? = nil
        
        let addresses     = ToMany<Address>()
      }
      static let entity : ZeeQL.Entity = Entity()
      
      var addresses : [ Address ] { // TBD: Careful, does it conflict with KVC?
        return storedValue(forKey: "addresses") as? [ Address ] ?? []
      }
    }

    let persons = ActiveDataSource<Person>(database: db)
    
    persons.fetchSpecification =
      ModelFetchSpecification(entity: persons.entity!, "login LIKE '*he*'",
                              limit: 4, prefetch: [ "addresses" ])
      // Note: this makes no sense:
      //   "login LIKE '*he*' AND addresses.zipcity != ''"
      // it does NOT affect the prefetch but only the lookup of the base
      // objects.
    
    let objects = try persons.fetchObjects()
    if printResults {
      print("got person recs: #\(objects.count)")
    
      for object in objects {
        print("  Person:")
        object.dumpRecordInColumns(indent: "    ")
        
        for address in object.addresses {
          print("    Address:")
          address.dumpRecordInColumns(indent: "      ")
        }
      }
    }
  }

  func testCodeSchemaWithTypedFetchSpec() throws {
    let db = Database(adaptor: adaptor)

    class OGoObject : ActiveRecord {
      // TODO: actually add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
    }
    
    
    class Address : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Address> {
        // this, or a property list [ "id": { column: "address_id", ... } ]?
        // an advantage of this is that we can refer to the columns from within
        // Swift, like Address.entity.id. E.g. for type-safe raw selects.
        let table         = "address"
        let id            = Info.Int(column: "address_id")

        let dbStatus      = Info.String(column: "db_status", width: 50)
        
        let companyId     = Info.Int(column: "company_id")
        
        let type          = Info.String(width: 50) // TODO: an enum?
        
        let name1         : String? = nil
        let name2         : String? = nil
        let name3         : String? = nil
        let street        : String? = nil
        let zip           = Info.OptString(width: 50)
        let zipcity       : String? = nil
        let country       : String? = nil
        let state         : String? = nil
        let district      : String? = nil
        
        let person        = ToOne<Person>() // auto: key: "company_id")
      }
      static let fields = Entity()
      static let entity : ZeeQL.Entity = fields
    }
    
    class Person : OGoObject, EntityType {
      class Entity : OGoCodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let isPerson      = Info.Int(column: "is_person")
        
        let login         = Info.OptString(width: 50)
        let isLocked      = Info.Int(column: "is_locked")
        let number        = Info.String(width: 100)
        
        let lastname      = Info.OptString(column: "name")
        let firstname     : String? = nil
        let middlename    : String? = nil
        
        let addresses     = ToMany<Address>()
      }
      static let fields = Entity()
      static let entity : ZeeQL.Entity = fields
      
      var addresses : [ Address ] { // TBD: Careful, does it conflict with KVC?
        return storedValue(forKey: "addresses") as? [ Address ] ?? []
      }
    }

    let persons = ActiveDataSource<Person>(database: db)
    
    // Note: what we really want is put fetch-specs into the CodeEntity!
    persons.fetchSpecification = Person
      .where(Person.fields.login.like("*he*"))
      .limit(4)
      .prefetch("addresses")
      .order(by: Person.fields.login)
    
    let objects = try persons.fetchObjects()
    if printResults {
      print("got person recs: #\(objects.count)")
    
      for object in objects {
        print("  Person:")
        object.dumpRecordInColumns(indent: "    ")
        
        for address in object.addresses {
          print("    Address:")
          address.dumpRecordInColumns(indent: "      ")
        }
      }
    }
  }
}


// MARK: - Helpers

fileprivate func dump(row: AdaptorRecord, prefix: String = "    ") {
  for ( key, value ) in row {
    print("\(prefix)\(key): \(value as Optional) [\(type(of: value))]")
  }
}

extension ActiveRecord {
  
  func dumpRecordInColumns(indent: String = "") {
    // TODO: align width
    let attrNames = self.entity.attributes.map({ $0.name })
    let maxLength = attrNames.reduce(0) {
      $1.characters.count > $0 ? $1.characters.count : $0
    }
    
    for key in attrNames {
      let vs  = "\(self[key] ?? "")"
      guard !vs.isEmpty else { continue }
      
      let pad = String(repeating: " ", count: maxLength - key.characters.count)
      print("\(indent)\(key): \(pad)\(vs)")
    }
  }
  
}
