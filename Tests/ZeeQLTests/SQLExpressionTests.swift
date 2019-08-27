//
//  SQLExpressionTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 21/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class SQLExpressionTests: XCTestCase {
  
  let factory = SQLExpressionFactory()
  
  let entity  : Entity = {
    let e = ModelEntity(name: "company")
    e.attributes = [
      ModelAttribute(name: "id",   externalType: "INTEGER"),
      ModelAttribute(name: "age",  externalType: "INTEGER"),
      ModelAttribute(name: "name", externalType: "VARCHAR(255)")
    ]
    return e
  }()
  
  
  func testRawDeleteSQLExpr() {
    let q = qualifierWith(format: "id = 5")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let expr = factory.deleteStatementWithQualifier(q!, entity)
    XCTAssertEqual(expr.statement,
                   "DELETE FROM \"company\" WHERE \"id\" = 5",
                   "unexpected SQL result")
  }
  
  func testUpdateSQLExpr() {
    let q = qualifierWith(format: "id = 5")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let row : [ String : Any? ] = [ "age": 42, "name": "Zealandia" ]
    
    let expr = factory.updateStatementForRow(row, q!, entity)

    // can be reordered, hashtable has no ordering!
    XCTAssert((
      ( expr.statement ==
        "UPDATE \"company\" SET \"age\" = 42, \"name\" = ? WHERE \"id\" = 5" )
      ||
      ( expr.statement ==
        "UPDATE \"company\" SET \"name\" = ?, \"age\" = 42 WHERE \"id\" = 5" )
      ), "unexpected SQL result")
    
    let bindings = expr.bindVariables
    XCTAssertEqual(bindings.count, 1, "unexpected binding count")
    XCTAssertEqual(bindings[0].value as? String, "Zealandia")
  }

  func testInsertSQLExpr() {
    let row : [ String : Any? ] = [ "id": 5, "age": 42, "name": "Zealandia" ]
    
    let expr = factory.insertStatementForRow(row, entity)
    
    // can be reordered, hashtable has no ordering!
    XCTAssert((
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"id\", \"age\", \"name\" ) " +
         "VALUES ( 5, 42, ? )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"name\", \"id\", \"age\" ) " +
          "VALUES ( ?, 5, 42 )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"age\", \"name\", \"id\" ) " +
          "VALUES ( 42, ?, 5 )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"age\", \"id\", \"name\" ) " +
          "VALUES ( 42, 5, ? )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"id\", \"name\", \"age\" ) " +
          "VALUES ( 5, ?, 42 )" ) )
      ||
      ( expr.statement ==
        ("INSERT INTO \"company\" ( \"name\", \"age\", \"id\" ) " +
          "VALUES ( ?, 42, 5 )" ) )
      ), "unexpected SQL result `\(expr.statement)`")
    
    let bindings = expr.bindVariables
    XCTAssertEqual(bindings.count, 1, "unexpected binding count")
    XCTAssertEqual(bindings[0].value as? String, "Zealandia")
  }
  
  func testSimpleSelectExpr() {
    let q = qualifierWith(format: "age > 13")
    XCTAssertNotNil(q, "could not parse qualifier")
    
    let fs = ModelFetchSpecification(entity: entity, qualifier: q)
    let expr = factory.selectExpressionForAttributes(
      entity.attributes, lock: true, fs, entity
    )
    XCTAssertEqual(expr.statement,
      "SELECT BASE.\"id\", BASE.\"age\", BASE.\"name\" " +
        "FROM \"company\" AS BASE " +
       "WHERE BASE.\"age\" > 13 FOR UPDATE",
      "unexpected SQL result")
  }

  func testJoinExpr() {
    class Address : ActiveRecord, EntityType {
      class Entity : CodeEntity<Address> {
        let table         = "address"
        let id            = Info.Int(column: "address_id")
        let companyId     = Info.Int(column: "company_id")
        let name1         : String? = nil
        let street        : String? = nil
        let person        = ToOne<Person>(from: "companyId")
          // auto: key: "company_id")
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    class Person : ActiveRecord, EntityType {
      class Entity : CodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let login         : String? = nil
        let lastname      = Info.OptString(column: "name")
        let addresses     = ToMany<Address>(on: "companyId")
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    let fs = ModelFetchSpecification(entity: Address.entity,
                                     "person.login != nil")
    let expr = factory.selectExpressionForAttributes(
      Address.entity.attributes, fs, Address.entity
    )
    
    XCTAssert(expr.statement.contains("JOIN"), "missing join")
    
    print("\(expr.statement)")
    XCTAssertEqual(expr.statement,
      "SELECT BASE.\"address_id\", BASE.\"company_id\", BASE.\"name1\", " +
             "BASE.\"street\" " +
       "FROM \"address\" AS BASE " +
       "LEFT JOIN \"person\" AS P " +
              "ON ( BASE.\"company_id\" = P.\"company_id\" ) " +
      "WHERE P.\"login\" IS NOT NULL")
  }
  
  func testCountExpr() {
    class OGoObject : ActiveRecord {
      // TODO: actually add KVC to store the key in this var
      var id : Int { return value(forKey: "id") as! Int }
    }
    class OGoCodeEntity<T: OGoObject> : CodeEntity<T> {
      // add common attributes, and support them in reflection
      let objectVersion = Info.Int(column: "object_version")
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
      }
      static let fields = Entity()
      static let entity : ZeeQL.Entity = fields
    }
    
    let fs = Person.where(Person.fields.login.like("*"))
                   .limit(4)
                   .order(by: Person.fields.login)
    let cfs = fs.fetchSpecificationForCount
    
    let expr = factory.selectExpressionForAttributes([], cfs, Person.entity)
    XCTAssertEqual(expr.statement,
                   "SELECT COUNT(*) FROM \"person\" AS BASE  " + // yes, two
                   "WHERE COALESCE(BASE.\"login\", '') LIKE ? LIMIT 1")
  }


  func testRelationshipPathExpr() {
    class Address : ActiveRecord, EntityType {
      class Entity : CodeEntity<Address> {
        let table         = "address"
        let id            = Info.Int(column: "address_id")
        let companyId     = Info.Int(column: "company_id")
        let name1         : String? = nil
        let street        : String? = nil
        let zipcity       : String? = nil
        let person        = ToOne<Person>(from: "companyId")
          // auto: key: "company_id")
      }
      static let entity : ZeeQL.Entity = Entity()
    }
    
    class Person : ActiveRecord, EntityType {
      class Entity : CodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let login         : String? = nil
        let lastname      = Info.OptString(column: "name")
        let addresses     = ToMany<Address>(on: "companyId")
      }
      static let typedEntity = Entity()
      static let entity : ZeeQL.Entity = typedEntity
    }
    
    let q  =
      "addresses.street LIKE '*Lo*' AND addresses.zipcity LIKE '*Magdeburg*'"
    let fs = ModelFetchSpecification(entity: Person.entity, q)
    let expr = factory.selectExpressionForAttributes(
      [ Person.typedEntity.id ], fs, Person.entity
    )
    
    XCTAssert(expr.statement.contains("JOIN"), "missing join")
    
    print("\(expr.statement)")
    XCTAssertEqual(expr.statement,
                   "SELECT BASE.\"company_id\" FROM \"person\" AS BASE LEFT JOIN \"address\" AS A ON ( BASE.\"company_id\" = A.\"company_id\" ) WHERE ( COALESCE(A.\"street\", '') LIKE ? ) AND ( COALESCE(A.\"zipcity\", '') LIKE ? )"
                   )
  }

  func DISABLEDtestObjectTargetExpr() { // unsupported yet
    class Address : ActiveRecord, EntityType {
      class Entity : CodeEntity<Address> {
        let table         = "address"
        let id            = Info.Int(column: "address_id")
        let companyId     = Info.Int(column: "company_id")
        let person        = ToOne<Person>(from: "companyId")
          // auto: key: "company_id")
      }
      static let typedEntity = Entity()
      static let entity : ZeeQL.Entity = typedEntity
    }
    class Person : ActiveRecord, EntityType {
      class Entity : CodeEntity<Person> {
        let table         = "person"
        let id            = Info.Int(column: "company_id")
        let login         : String? = nil
        let addresses     = ToMany<Address>(on: "companyId")
      }
      static let typedEntity = Entity()
      static let entity : ZeeQL.Entity = typedEntity
    }
    
    let person = Person()
    person.takeStoredValues([
      "id"    : 42,
      "login" : "donald"
    ])
    
    let q = qualifierWith(format: "person = %@", person)!
    let fs = ModelFetchSpecification(entity: Address.entity, qualifier: q)
    let expr = factory.selectExpressionForAttributes(
      [ Address.typedEntity.id ], fs, Address.entity
    )
    
    XCTAssert(expr.statement.contains("JOIN"), "missing join")
    
    print("\(expr.statement)")
    XCTAssertEqual(expr.statement, "TODO")
  }


  static var allTests = [
    ( "testRawDeleteSQLExpr",     testRawDeleteSQLExpr     ),
    ( "testUpdateSQLExpr",        testUpdateSQLExpr        ),
    ( "testInsertSQLExpr",        testInsertSQLExpr        ),
    ( "testSimpleSelectExpr",     testSimpleSelectExpr     ),
    ( "testJoinExpr",             testJoinExpr             ),
    ( "testCountExpr",            testCountExpr            ),
    ( "testRelationshipPathExpr", testRelationshipPathExpr ),
  ]
}
