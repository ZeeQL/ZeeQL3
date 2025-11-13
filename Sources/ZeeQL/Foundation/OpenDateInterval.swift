//
//  OpenDateInterval.swift
//  ZeeQL
//
//  Created by Helge Hess on 21/02/17.
//  Copyright © 2017-2025 ZeeZide GmbH. All rights reserved.
//

import Foundation

/**
 * A date range that can have an optional start and/or end date.
 *
 * This is similar to the Foundation `DateInterval` or a `Range<Date>`, but
 * allows for open ("nil") ends.
 *
 * This ``OpenDateInterval`` is supported in ``SQLExpression`` queries.
 */
@frozen
public struct OpenDateInterval: Hashable, Sendable, Codable {
  // (The `DateInterval` in Foundation seems superfluous and its functionality
  //  should just be an extension on `Range where Bound == Date`?)

  public var start : Date?
  public var end   : Date?

  /**
   * Create a new ``OpenDateInterval``.
   *
   * - Parameters:
   *   - start: The start of the date interval, or nil if the lower bound is
   *            open.
   *   - end:   The end of the date interval, or nil if the lower bound is
   *            open.
   */
  @inlinable
  public init(start: Date? = nil, end: Date? = nil) {
    self.start = start
    self.end   = end
    
    if let start, let end {
      assert(start <= end,
             "date range endDate before startDate! \(start) \(end) ")
      if end < start {
        self.start = end
        self.end   = start
      }
    }
  }
}

public extension OpenDateInterval {
  
  @inlinable
  var isEmpty : Bool {
    if let from = start, let to = end { return from == to }
    else { return false } // open, not empty!
  }
  
  @inlinable
  var duration : TimeInterval? {
    guard !isEmpty else { return 0 }
    guard let from = start, let to = end else { return nil } // open
    return to.timeIntervalSince(from)
  }
  
  @inlinable
  var isOpen : Bool {
    return start == nil || end == nil
  }
  
  /**
   * Be careful with using this. For higher-level units (years, months, weeks),
   * you probably want to use the Calendar!
   *
   * But its fine for hours and such, which do not leap.
   */
  @inlinable
  var nextTimeRange : Self? {
    guard let duration = duration else { return nil }
    return OpenDateInterval(start: end, end: end?.addingTimeInterval(duration))
  }
  
  /**
   * Be careful with using this. For higher-level units (years, months, weeks),
   * you probably want to use the Calendar!
   *
   * But its fine for hours and such, which do not leap.
   */
  @inlinable
  var previousTimeRange : Self? {
    guard let duration = duration else { return nil }
    return OpenDateInterval(start: start?.addingTimeInterval(-duration),
                            end: start)
  }
  
  
  // MARK: - Containment
  
  // TODO: add tests
  
  @inlinable
  func contains(_ date: Date) -> Bool {
    if let from = start, let to = end {
      if from.compare(date) == .orderedDescending { return false }
      if date.compare(to)   != .orderedAscending  { return false }
      return true
    }
    else if let from = start {
      return from.compare(date) != .orderedDescending
    }
    else if let to = end {
      return date.compare(to) == .orderedAscending
    }
    else {
      return true // fully open
    }
  }
  
  @inlinable
  func isBefore(_ date: Date) -> Bool {
    switch ( start, end ) {
      case ( .none, .none ): return false // open is never "before"
      case ( .some(let startDate), .none ): return startDate < date
      case ( .none, .some(let endDate) ): return endDate < date
      case ( .some(let startDate), .some(let endDate) ):
        assert(startDate <= endDate)
        return startDate < date && endDate < date
    }
  }
  
  /**
   * Returns true if this timerange and the other one cover a common section.
   *
   * The end is treated as EXCLUSIVE.
   *
   * - Parameters:
   *   - range: the other timerange
   * - Returns: `true` on overlap, false if the two are distinct.
   */
  @inlinable
  func overlaps(with range: Range<Date>) -> Bool {
    // Note: range can be empty, but will still match open ranges?
    // Note: OGoCore/J has different behaviour here! It considers open ranges
    //       as non-overlapping!
    self.range.overlaps(range)
  }
  
  /**
   * Returns true if this timerange and the other one cover a common section.
   *
   * - Parameters:
   *   - range: the other timerange
   * - Returns: `true` on overlap, false if the two are distinct.
   */
  @inlinable
  func overlaps(with range: OpenDateInterval) -> Bool {
    return overlaps(with: range.range)
  }
}

#if false // TBD!
public extension OpenDateInterval: Comparable {
  
}
#endif
#if false // TBD!
public extension OpenDateInterval: SetAlgebra {
  
}
#endif

// MARK: - Foundation/Swift type support

public extension OpenDateInterval {
  
  /**
   * Create a new ``OpenDateInterval``, replacing distantPast and distantFuture
   * with open boundaries.
   *
   * - Parameters:
   *   - start: The start of the date interval, .distantPast if the lower bound
   *            is open.
   *   - end:   The end of the date interval, .distantFuture if the upper bound
   *            is open.
   */
  @inlinable
  init(start: Date, end: Date) {
    self.init(start : start == .distantPast   ? nil : start,
              end   : end   == .distantFuture ? nil : end)
  }
  
  @inlinable
  init(_ range: Range<Date>) {
    self.init(start: range.lowerBound, end: range.upperBound)
  }
  
  @inlinable
  init(_ interval: DateInterval) {
    self.init(start: interval.start, end: interval.end)
  }
  
  /**
   * Returns a Foundation `DateInterval` for the date range, replacing nil
   * values w/ distancePast and distantFuture.
   */
  @inlinable
  var interval : DateInterval {
    set {
      start = newValue.start == .distantPast   ? nil : newValue.start
      end   = newValue.end   == .distantFuture ? nil : newValue.end
    }
    get {
      DateInterval(start: (start ?? .distantPast),
                   end: (end ?? .distantFuture))
    }
  }
  
  /**
   * Returns a `Range<Date>` for the date range, replacing nil
   * values w/ distancePast and distantFuture.
   */
  @inlinable
  var range : Range<Date> {
    set {
      start = newValue.lowerBound == .distantPast   ? nil : newValue.lowerBound
      end   = newValue.upperBound == .distantFuture ? nil : newValue.upperBound
    }
    get { (start ?? .distantPast)..<(end ?? .distantFuture) }
  }
}
