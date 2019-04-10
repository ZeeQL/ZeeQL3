//
//  AdaptorRecord.swift
//  ZeeQL
//
//  Created by Helge Hess on 24/02/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * A specialized Dictionary<String, Any?> to be used for raw records returned
 * from the database.
 * One feature is that it shares all keys between the records.
 */
open class AdaptorRecord : SwiftObject, SmartDescription {
  // Note: used to be a struct, but for DataSource we need an object, and well.
  
  public let schema  : AdaptorRecordSchema
  public let values  : [ Any? ] // TBD: is it Any or some DB column base class?
  
  public var isEmpty : Bool { return values.isEmpty }
  
  public subscript(name: String) -> Any? {
    #if swift(>=5)
      guard let idx = schema.attributeNames.firstIndex(of: name) else {
        return nil
      }
    #else
      guard let idx = schema.attributeNames.index(of: name) else { return nil }
    #endif
    guard idx < values.count else { return nil }
    return values[idx]
  }
  
  public subscript(index: Int) -> Any? {
    return index < values.count ? values[index] : nil
  }
  
  
  // MARK: - Initializer

  public init(schema: AdaptorRecordSchema, values: [ Any? ]) {
    self.schema = schema
    self.values = values
  }
  
  
  // MARK: - Dictionary Representations
  
  public var asDictionary : [ String : Any ] {
    var dict = [ String : Any ]()
    for key in schema.attributeNames {
      guard let v = self[key] else { continue }
      dict[key] = v
    }
    return dict
  }
  public var asAdaptorRow : AdaptorRow {
    var dict = AdaptorRow()
    for key in schema.attributeNames {
      guard let v = self[key] else { continue }
      dict[key] = v
    }
    return dict
  }
  
  
  // MARK: - Description

  public func appendToDescription(_ ms: inout String) {
    ms += " "
    ms += asDictionary.description
  }
}

extension AdaptorRecord : Sequence {
  
  public struct AdaptorRecordIterator : IteratorProtocol {
    private let record : AdaptorRecord
    private var pos    = 0
    
    init(record: AdaptorRecord) {
      self.record = record
    }
    
    public mutating func next() -> ( String, Any? )? {
      guard pos < record.schema.count else { return nil }
      
      let value = ( record.schema.attributeNames[pos], record[pos] )
      pos += 1
      
      return value
    }
  }
  
  public func makeIterator() -> AdaptorRecordIterator {
    return AdaptorRecordIterator(record: self)
  }
}
