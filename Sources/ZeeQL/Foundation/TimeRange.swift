//
//  TimeRange.swift
//  ZeeQL
//
//  Created by Helge Hess on 21/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation

struct TimeRange {
  
  let fromDate : Date?
  let toDate   : Date?
  
  init(from: Date?, to: Date?) {
    fromDate = from
    toDate   = to
  }
  
  var isEmpty : Bool {
    if let from = fromDate, let to = toDate {
      return from == to
    }
    else {
      return false // open, not empty!
    }
  }
  
  var duration : TimeInterval? {
    guard !isEmpty else { return 0 }
    guard let from = fromDate, let to = toDate else { return nil } // open
    return to.timeIntervalSince(from)
  }
  
  var isOpen : Bool {
    return fromDate == nil || toDate == nil
  }
  
  /**
   * Be careful with using this. For higher-level units (years, months, weeks),
   * you probably want to use the Calendar!
   *
   * But its fine for hours and such, which do not leap.
   */
  var nextTimeRange : TimeRange? {
    guard let duration = duration else { return nil }
    return TimeRange(from: toDate, to: toDate?.addingTimeInterval(duration))
  }
  
  /**
   * Be careful with using this. For higher-level units (years, months, weeks),
   * you probably want to use the Calendar!
   *
   * But its fine for hours and such, which do not leap.
   */
  var previousTimeRange : TimeRange? {
    guard let duration = duration else { return nil }
    return TimeRange(from: fromDate?.addingTimeInterval(-duration),
                     to: fromDate)
  }
  
  
  // MARK: - Containment
  
  // TODO: add tests
  
  func contains(_ date: Date) -> Bool {
    if let from = fromDate, let to = toDate {
      if from.compare(date) == .orderedDescending { return false }
      if date.compare(to)   != .orderedAscending  { return false }
      return true
    }
    else if let from = fromDate {
      return from.compare(date) != .orderedDescending
    }
    else if let to = toDate {
      return date.compare(to) == .orderedAscending
    }
    else {
      return true // fully open
    }
  }
}
