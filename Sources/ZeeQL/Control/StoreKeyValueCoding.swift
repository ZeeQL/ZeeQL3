//
//  StoreKeyValueCoding.swift
//  ZeeQL
//
//  Created by Helge Hess on 26/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

/**
 * Stored KVC avoids calling extra logic applied when calling regular KVC.
 *
 * Conceptually it just reverses the key lookup path of KVC, that is, instead of
 * 1. check for set/get method
 * 2. check for instance var
 * It does the reverse
 * 1. check for instance var
 * 2. check for set/get method
 *
 * That is the idea. Not sure how to apply it to Swift :-)
 */
public protocol StoreKeyValueCodingType
                  : KeyValueCodingType, MutableKeyValueCodingType
{

  func storedValue(forKey k: String) -> Any?
  func takeStoredValue(_ v: Any?, forKey k: String)

}

public extension StoreKeyValueCodingType {

  func takeStoredValue(_ v: Any?, forKey k: String) {
    fatalError("not implemented: \(#function)")
  }
  
}

public extension StoreKeyValueCodingType {
  
  func storedValue(forKey k: String) -> Any? {
    return StoreKeyValueCoding.defaultStoredValue(forKey: k, inObject: self)
  }
  
  func takeStoredValues(_ values : [ String : Any? ]) {
    for ( key, value ) in values {
      takeStoredValue(value, forKey: key)
    }
  }
  func storedValues(forKeys keys: [ String ]) -> [ String : Any? ] {
    var values = [ String : Any? ]()
    for key in keys {
      values[key] = storedValue(forKey: key)
    }
    return values
  }
}

public struct StoreKeyValueCoding {

  public static func storedValue(forKey k: String, inObject o: Any?) -> Any? {
    if let kvc = o as? StoreKeyValueCodingType {
      return kvc.storedValue(forKey: k)
    }
    return defaultStoredValue(forKey: k, inObject: o)
  }
  
  public static func defaultStoredValue(forKey k: String, inObject o: Any?)
                     -> Any?
  {
    if let kvc = o as? KeyValueCodingType {
      return kvc.value(forKey: k)
    }
    
    return nil
  }
  
}
