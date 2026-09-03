//
//  Dictionary+Extensions.swift
//  ZeeQL3
//
//  Created by Helge Heß on 24.11.24.
//

enum DictionaryArgumentError: Error, Equatable {

  case oddArgumentCount(Int)
}

extension Dictionary where Key == String, Value == Any {
  
  /**
   * This method creates a new `Dictionary` from a set of given array containing
   * key/value arguments.
   */
  static func createArgs(_ values: [ Any ]) throws -> Self {
    guard !values.isEmpty else { return [:] }
    guard values.count.isMultiple(of: 2) else {
      throw DictionaryArgumentError.oddArgumentCount(values.count)
    }
    var me = Self()
    me.reserveCapacity(values.count / 2 + 1)
    
    for idx in stride(from: 0, to: values.count, by: 2) {
      let anyKey = values[idx]
      let value  = values[idx + 1]
      me[anyKey as? String ?? String(describing: anyKey)] = value
    }
    return me
  }
}
