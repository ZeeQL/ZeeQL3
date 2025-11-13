//
//  OpenDateIntervalTests.swift
//  ZeeQL3
//
//  Created by Helge Heß on 13.11.25.
//

import XCTest
@testable import ZeeQL

class OpenDateIntervalTests: XCTestCase {
  
  // an all-day event, in UTC: 2025-11-07 23:00 - 2025-11-08 22:59
  let eventInterval = OpenDateInterval(
    start: Date(timeIntervalSinceReferenceDate: 784249200.0),
    end:   Date(timeIntervalSinceReferenceDate: 784335540.0)
  )

  func testRangeBeforeOpenInterval() {
    // a day BEFORE, CET, in UTC: 2025-11-06 23:00 - 2025-11-07 23:00
    let dayStart = Date(timeIntervalSinceReferenceDate: 784162800.0)
    let dayEnd   = Date(timeIntervalSinceReferenceDate: 784249200.0)
    let dayRange = dayStart..<dayEnd

    XCTAssertEqual(dayEnd, eventInterval.start)
    XCTAssertFalse(eventInterval.overlaps(with: dayRange),
                   "That should not match the day before")
  }
  
  func testRangeAfterOpenInterval() throws {
    // a range AFTER 2025-11-08 22:59-...
    let start = try XCTUnwrap(eventInterval.end) // start where it ends
    let end   = start.addingTimeInterval(24 * 60 * 60)
    let range = start..<end
       
    XCTAssertFalse(eventInterval.overlaps(with: range),
                   "That should not match the day after")
  }
  
  func testRangeInOpenInterval() throws {
    // a range AFTER 2025-11-08 22:59-...
    let start = try XCTUnwrap(eventInterval.end) // start 4 hours before it ends
      .addingTimeInterval(-(4 * 60 * 60)) // negative, substract 4h from end
    let end   = start.addingTimeInterval(24 * 60 * 60)
    let range = start..<end
       
    XCTAssertTrue(eventInterval.overlaps(with: range),
                  "That should match the range")
  }
}
