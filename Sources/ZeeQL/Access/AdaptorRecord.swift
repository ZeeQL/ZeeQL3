//
//  AdaptorRecord.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017-2020 ZeeZide GmbH. All rights reserved.
//

/**
 * A specialized Dictionary<String, Any?> to be used for raw records returned
 * from the database.
 * One feature is that it shares all keys between the records.
 *
 * Note: Do not confuse w/ `AdaptorRow`, which is a straight
 *         `[ String : Any? ]`
 *       dictionary with an optional value to represent NULL columns.
 */
open class AdaptorRecord : SwiftObject, SmartDescription {
  // Note: used to be a struct, but for DataSource we need an object, and well.
  
  public let schema  : AdaptorRecordSchema
  public var values  : [ Any? ] // TBD: is it Any or some DB column base class?
  
  public var isEmpty : Bool { return values.isEmpty }
  
  @inlinable
  public subscript(name: String) -> Any? {
    set {
      guard let idx = _indexForName(name) else {
        globalZeeQLLogger
          .error("Attempt to set unsupported field", name, "in", self)
        assertionFailure("record has no '\(name)' field to apply value!")
        return
      }
      while idx >= values.count {
        values.append(nil)
      }
      values[idx] = newValue
    }
    get {
      guard let idx = _indexForName(name) else { return nil }
      guard idx < values.count            else { return nil }
      return values[idx]
    }
  }
  
  @inlinable
  public subscript(index: Int) -> Any? {
    return index < values.count ? values[index] : nil
  }
  
  @inlinable
  public func _indexForName(_ name: String) -> Int? {
    #if swift(>=5)
      let idx = schema.attributeNames.firstIndex(of: name)
    #else
      let idx = schema.attributeNames.index(of: name)
    #endif
    #if DEBUG
      if let checkIdx = idx {
        assert(checkIdx >= 0 && checkIdx < values.count)
      }
    #endif
    return idx
  }
  
  
  // MARK: - Initializer

  @inlinable
  public init(schema: AdaptorRecordSchema, values: [ Any? ]) {
    self.schema = schema
    self.values = values
  }
  
  
  // MARK: - Dictionary Representations
  
  /**
   * Returns the record as a `[ String : Any ]` dictionary. If a value is NULL,
   * it is excluded from the dictionary.
   *
   * If NULL values are needed, use `asAdaptorRow` instead (yields an `Any?`).
   */
  @inlinable
  public var asDictionary : [ String : Any ] {
    var dict = [ String : Any ]()
    dict.reserveCapacity(schema.count)
    for key in schema.attributeNames {
      guard let v = self[key] else { continue }
      dict[key] = v
    }
    return dict
  }
  
  /**
   * An `AdaptorRow` is just a `[ String : Any? ]` dictionary.
   *
   * This includes a key, even when the value is NULL. To get the
   * "compact" version, use `asDictionary`.
   */
  @inlinable
  public var asAdaptorRow : AdaptorRow {
    var dict = AdaptorRow()
    dict.reserveCapacity(schema.count)
    for key in schema.attributeNames {
      guard let v = self[key] else { continue }
      dict[key] = v
    }
    return dict
  }
  
  
  // MARK: - Description

  @inlinable
  public func appendToDescription(_ ms: inout String) {
    ms += " "
    ms += asDictionary.description
  }
}

extension AdaptorRecord : Sequence {
  
  /**
   * This iterates over the attributes in the record. Like a dictionary
   * the value yielded is a tuple, the attribute name (`String`) and
   * the value (`Any?`).
   */
  public struct AdaptorRecordIterator : IteratorProtocol {
    @usableFromInline
    let record : AdaptorRecord
    @usableFromInline
    var pos    = 0
    
    @inlinable
    init(record: AdaptorRecord) {
      self.record = record
    }
    
    @inlinable
    public mutating func next() -> ( String, Any? )? {
      guard pos < record.schema.count else { return nil }
      
      let value = ( record.schema.attributeNames[pos], record[pos] )
      pos += 1
      
      return value
    }
  }
  
  /**
   * This iterates over the attributes in the record. Like a dictionary
   * the value yielded is a tuple, the attribute name (`String`) and
   * the value (`Any?`).
   */
  @inlinable
  public func makeIterator() -> AdaptorRecordIterator {
    return AdaptorRecordIterator(record: self)
  }
}
