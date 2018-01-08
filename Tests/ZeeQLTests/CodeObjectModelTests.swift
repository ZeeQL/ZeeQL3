//
//  CodeObjectModelTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 13.12.17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

//
//  CodeEntityModelTests.swift
//  ZeeQL
//
//  Created by Helge Hess on 28/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import XCTest
@testable import ZeeQL

class CodeObjectModelTests: XCTestCase {
  
  func testCodeObjectSchema() {
    class OGoObject : ActiveRecord {
      let objectVersion = Value.Int(column: "object_version", 0)
    }
    
    class Address : OGoObject, CodeObjectType {
      // Boxed values, annotated with Attribute information
      let id            = Value.Int   (column: "address_id")
      let dbStatus      = Value.String(column: "db_status", width: 50)
      let companyId     = Value.Int   (column: "company_id")
      let type          = Value.String(width: 50) // TODO: an enum?

      // TODO: We can do this, but we don't get automagic KVC then.
      let name1         : String? = nil
      let name2         : String? = nil
      let name3         : String? = nil
      let street        : String? = nil
      let zip           = Value.OptString(width: 50, nil)
      let zipcity       : String? = nil
      let country       : String? = nil
      let state         : String? = nil
      let district      : String? = nil
      
      // TODO
      // - This could be a 'fault'.
      //let person        = ToOne<Person>() // auto: key: "company_id")
      
      static let entity : ZeeQL.Entity
                        = CodeObjectEntity<Address>(table: "address")
    }

    let entity = Address.entity
    XCTAssertEqual(entity.externalName, "address")
    
    let attrs = entity.attributes
    XCTAssertEqual(attrs.count, 14)
    
    let pkeys = entity.primaryKeyAttributeNames
    XCTAssertNotNil(pkeys)
    XCTAssertEqual(pkeys?.count ?? -1, 1)
    XCTAssertEqual(pkeys?[0] ?? "", "id")
  }
  
}
