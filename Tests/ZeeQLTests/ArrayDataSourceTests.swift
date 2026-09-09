//
//  ArrayDataSourceTests.swift
//  ZeeQL
//

import XCTest
@testable import ZeeQL

final class ArrayDataSourceTests: XCTestCase {

  func testFetchWithoutSpecificationReturnsAllObjects() throws {
    let objects = [ makeObject("A", age: 10), makeObject("B", age: 20) ]
    let dataSource = ArrayDataSource(objects)

    XCTAssertEqual(try dataSource.fetchObjects().count, 2)
  }

  func testFetchCountAppliesQualifiersBeforeRange() throws {
    let objects = [
      makeObject("A", age: 10), makeObject("B", age: 20),
      makeObject("C", age: 30), makeObject("D", age: 40)
    ]
    let dataSource = ArrayDataSource(objects)
    dataSource.auxiliaryQualifier = KeyValueQualifier("age", .greaterThan, 10)
    dataSource.fetchSpecification = ModelFetchSpecification(
      qualifier: KeyValueQualifier("age", .lessThan, 40),
      offset: 1, limit: 1)

    XCTAssertEqual(try dataSource.fetchCount(), 2)
  }

  func testUnsortedFilterAndRange() throws {
    let objects = [
      makeObject("A", age: 10), makeObject("B", age: 20),
      makeObject("C", age: 30), makeObject("D", age: 40)
    ]
    let dataSource = ArrayDataSource(objects)
    dataSource.fetchSpecification = ModelFetchSpecification(
      qualifier: KeyValueQualifier("age", .greaterThan, 10),
      offset: 1, limit: 1)

    let fetched = try dataSource.fetchObjects()
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched[0].valueForKey("age") as? Int, 30)
  }

  func testOffsetBeyondResultReturnsEmptyArray() throws {
    let dataSource = ArrayDataSource([ makeObject("A", age: 20) ])
    dataSource.fetchSpecification = ModelFetchSpecification(offset: 10)

    XCTAssertTrue(try dataSource.fetchObjects().isEmpty)
  }

  func testNegativeRangesUseZero() throws {
    let dataSource = ArrayDataSource([ makeObject("A", age: 20) ])
    dataSource.fetchSpecification = ModelFetchSpecification(offset: -1)
    XCTAssertEqual(try dataSource.fetchObjects().count, 1)

    dataSource.fetchSpecification = ModelFetchSpecification(limit: -1)
    XCTAssertTrue(try dataSource.fetchObjects().isEmpty)
  }

  func testVeryLargeLimitDoesNotOverflow() throws {
    let dataSource = ArrayDataSource([ makeObject("A", age: 20) ])
    dataSource.fetchSpecification = ModelFetchSpecification(limit: Int.max)

    XCTAssertEqual(try dataSource.fetchObjects().count, 1)
  }

  func testSortOrderings() throws {
    let objects = [
      makeObject("Beta", age: 20), makeObject("alpha", age: 20),
      makeObject("beta", age: 30)
    ]
    let dataSource = ArrayDataSource(objects)
    dataSource.fetchSpecification = ModelFetchSpecification(
      sortOrderings: [
        SortOrdering(key: "name", selector: .caseInsensitiveAscending),
        SortOrdering(key: "age", selector: .descending)
      ])

    let fetched = try dataSource.fetchObjects()
    let names = fetched.compactMap { $0.valueForKey("name") as? String }
    XCTAssertEqual(names, [ "alpha", "beta", "Beta" ])
    XCTAssertEqual(dataSource.objects[0].valueForKey("name") as? String,
                   "Beta")
  }

  func testCaseInsensitiveSortPreservesNonStringValues() throws {
    let objects = [ makeObject("A", age: 30), makeObject("B", age: 20) ]
    let dataSource = ArrayDataSource(objects)
    dataSource.fetchSpecification = ModelFetchSpecification(
      sortOrderings: [
        SortOrdering(key: "age", selector: .caseInsensitiveAscending)
      ])

    let fetched = try dataSource.fetchObjects()
    XCTAssertEqual(fetched[0].valueForKey("age") as? Int, 20)
    XCTAssertEqual(fetched[1].valueForKey("age") as? Int, 30)
  }

  func testUnsupportedSortSelectorPreservesOrder() throws {
    let objects = [ makeObject("B", age: 20), makeObject("A", age: 30) ]
    let dataSource = ArrayDataSource(objects)
    dataSource.fetchSpecification = ModelFetchSpecification(
      sortOrderings: [ SortOrdering(key: "name", selector: .other("x")) ])

    let fetched = try dataSource.fetchObjects()
    let names = fetched.compactMap { $0.valueForKey("name") as? String }
    XCTAssertEqual(names, [ "B", "A" ])
  }

  private func makeObject(_ name: String, age: Int) -> ActiveRecord {
    let object = ActiveRecord()
    object.takeStoredValue(name, forKey: "name")
    object.takeStoredValue(age, forKey: "age")
    return object
  }
}
