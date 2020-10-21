//
//  SQLite3CodableTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 12.02.18.
//  Copyright © 2018-2020 ZeeZide GmbH. All rights reserved.
//

import XCTest
import Foundation
@testable import ZeeQL

class SQLite3CodableTests: XCTestCase {

  var adaptor : Adaptor! { return _adaptor }
  var _adaptor : Adaptor = {
    var pathToTestDB : String = {
    #if ZEE_BUNDLE_RESOURCES
      let bundle = Bundle(for: type(of: self) as! AnyClass)
      let url    = bundle.url(forResource: "contacts", withExtension: "sqlite3")
      guard let path = url?.path else { return "contacts.sqlite3" }
      return path
    #else
      return "\(lookupTestDataPath())/contacts.sqlite3"
    #endif
    }()
    return SQLite3Adaptor(pathToTestDB)
  }()
  

  func testRawAdaptorQuery() throws {
    guard let entity = PlainCodableContactsDBModel.sqlModel[entity: "Person"]
     else
    {
      XCTAssertNotNil(PlainCodableContactsDBModel.sqlModel[entity: "Person"],
                      "got no Person entity?")
      return
    }
    
    print("Entity:", entity)
    
    let factory = adaptor.expressionFactory
    
    do {
      let channel = try adaptor.openChannel()
      defer { adaptor.releaseChannel(channel) }
      
      let expr =
        factory.selectExpressionForAttributes(entity.attributes, nil, entity)
      
      var records = [ AdaptorRecord ]()
      try channel.evaluateQueryExpression(expr, entity.attributes) { record in
        records.append(record)
      }
      
      print("records:", records)
      
      XCTAssertEqual(records.count, 3)      
    }
    catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
  
  func testBasicCodableFetch() {
    typealias Model = PlainCodableContactsDBModel
    
    do {
      let objects = try adaptor.query(Model.Person.self)
      
      XCTAssertEqual(objects.count, 3)
      
      if let entity = Model.model[entity: "Person"] {
        for object in objects {
          print("object: \(entity.descriptionForObject(object))")
        }
      }
      else {
        print("objects:", objects)
      }
    }
    catch {
      XCTFail("Unexpected error: \(error)")
    }
  }


  // MARK: - Non-ObjC Swift Support
  
  static var allTests = [
    ( "testRawAdaptorQuery", testRawAdaptorQuery )
  ]
}

extension Entity {
  
  func descriptionForObject(_ object: Any) -> String {
    var ms = "<\(type(of: object))[\(name)]:"
    for prop in classPropertyNames ?? attributes.map({ $0.name }) {
      let v = KeyValueCoding.value(forKey: prop, inObject: object)
      if let v = v {
        ms += " \(prop)="
        if let s = v as? String {
          ms += "\"\(s)\"" // TODO: escape
        }
        else {
          ms += "\(v)"
        }
      }
    }
    ms += ">"
    return ms
  }
}

// TDD ;-)

extension Adaptor {
  // extension AdaptorQueryType {
  
  func query<T: Decodable>(_ type: T.Type) throws -> [ T ] {
    let adaptor = self
    
    // create model for type
    
    let options = CodableModelDecoder.Options(sqlize: true)
    let model   = try Model.createFromTypes(type, options: options)
      // TODO: we should cache the sqlized model (but per adaptor-type?!)
    
    guard let entity = model.entityForType(type) else {
      // TODO: throw
      fatalError("did not find entity for decoded type")
    }
    
    // generate SQL
    
    let factory = adaptor.expressionFactory
    let expr =
      factory.selectExpressionForAttributes(entity.attributes, nil, entity)
    
    // open channel

    let channel = try openChannelFromPool()
    defer { releaseChannel(channel) }
    
    // fetch and decode
    
    let decoder = AdaptorRecordDecoder<T>()
    var objects = [ T ]()
    
    try channel.evaluateQueryExpression(expr, entity.attributes) { record in
      print("record:", record)
      let object = try decoder.decode(record: record)
      print("object:", record)
      objects.append(object)
    }
    
    return objects
  }
  
}

// FIXME: We cannot just move this into its own file due to
//        the Xcode build bug.
// TODO(2019-08-07): still an issue?
  
/**
 * Decode plain Decodable objects from adaptor records.
 *
 * Adaptor queries can use relationships to query specific information
 * (i.e. use pathes in fetch specs), but they cannot themselves
 * follow relationships.
 * A database channel / object tracking context can be used for that.
 */
public class AdaptorRecordDecoder<T: Decodable> : Decoder {
  
  public enum Error : Swift.Error {
    case notImplemented
    case adaptorCannotDecodeRelationships
    case unsupportedValueType(Any.Type)
    case unsupportedNesting
    case unexpectedRelationshipHolderType
    case missingKey
  }
  
  var log : ZeeQLLogger { return globalZeeQLLogger }

  public var codingPath = [ CodingKey] ()
  public var userInfo   = [ CodingUserInfoKey : Any ]()
  
  var record : AdaptorRecord? = nil
  
  public func decode(record: AdaptorRecord) throws -> T {
    assert(self.record == nil, "record still assigned?!")
    defer { clear() }
    
    self.record = record
    let object = try T(from: self)
    
    return object
  }
  
  public func clear() {
    codingPath.removeAll()
    userInfo.removeAll()
    record = nil
  }
  
  public func container<Key>(keyedBy type: Key.Type) throws
                -> KeyedDecodingContainer<Key> where Key : CodingKey
  {
    log.trace("get-keyed-container<\(type)>")
    return KeyedDecodingContainer(KeyedContainer<T, Key>(decoder: self))
  }
  
  public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    guard let key = codingPath.last else {
      log.error("missing coding key:", codingPath, self)
      throw Error.missingKey
    }
    
    log.trace("get-unkeyed-container",
              "\n  record:   ", record,
              "\n  source-key:", key)
    return UnkeyedContainer<T>(decoder: self, key: key)
  }
  
  public func singleValueContainer() throws -> SingleValueDecodingContainer {
    throw Error.notImplemented
  }

  
  /* Containers */
  
  internal final class KeyedContainer<T: Decodable, Key: CodingKey>
                         : KeyedDecodingContainerProtocol
  {
    let decoder : AdaptorRecordDecoder<T>
    let log     : ZeeQLLogger

    let codingPath : [ CodingKey ]
    let allKeys    : [ Key ]

    init(decoder: AdaptorRecordDecoder<T>) {
      self.decoder    = decoder
      self.log        = decoder.log
      self.codingPath = decoder.codingPath
      
      if let record = decoder.record {
        self.allKeys = record.schema.attributeNames.compactMap(Key.init)
      }
      else {
        self.allKeys = []
      }
    }
    
    func contains(_ key: Key) -> Bool {
      // called by decodeIfPresent() - which is used for stuff like `age:Int?`
      log.trace("contains:", key.stringValue)
      let name = nameForKey(key)
      return decoder.record?[name] != nil
    }
    
    
    // MARK: - Non-Basetype Objects
    
    /**
     * The main *type erased!* decoding functions for types which are not base
     * types.
     *
     * Remember that Swift won't dispatch dynamically on `T`. Hence the manual
     * checks inline.
     *
     * Arrays: There are two kinds of arrays we want to support:
     *         - base types column arrays, like `[Int]`,
     *         - arrays of CodableObjectType`s aka relationships
     */
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T
           where T : Decodable
    {
      switch type {
        case is RelationshipHolderType.Type:
          return try decodeRelationshipHolder(erasedHolderType: type,
                                              forKey: key)
        
        case is CodableObjectType.Type:
          return try decodeDecodableObject(type, forKey: key)
        
        case is ImplicitToManyRelationshipHolder.Type:
          return try decodeImplicitRelationshipHolder(type, forKey: key)
        
          // TODO: support all combinations :-)
          // TBD: Can we do Array<AttributeValue>?
        //      Maybe via conditional conformance in 4.1?
        case is Array<Int>.Type:
          return try decodeBaseTypeArray(type, Int.self,    forKey: key)
        case is Array<Int8>.Type:
          return try decodeBaseTypeArray(type, Int8.self,   forKey: key)
        case is Array<Int16>.Type:
          return try decodeBaseTypeArray(type, Int16.self,  forKey: key)
        case is Array<Int32>.Type:
          return try decodeBaseTypeArray(type, Int32.self,  forKey: key)
        case is Array<Int64>.Type:
          return try decodeBaseTypeArray(type, Int64.self,  forKey: key)
        case is Array<UInt>.Type:
          return try decodeBaseTypeArray(type, UInt.self,   forKey: key)
        case is Array<UInt8>.Type:
          return try decodeBaseTypeArray(type, UInt8.self,  forKey: key)
        case is Array<UInt16>.Type:
          return try decodeBaseTypeArray(type, UInt16.self, forKey: key)
        case is Array<UInt32>.Type:
          return try decodeBaseTypeArray(type, UInt32.self, forKey: key)
        case is Array<UInt64>.Type:
          return try decodeBaseTypeArray(type, UInt64.self, forKey: key)
        case is Array<Float>.Type:
          return try decodeBaseTypeArray(type, Float.self,  forKey: key)
        case is Array<Double>.Type:
          return try decodeBaseTypeArray(type, Double.self, forKey: key)
        case is Array<Bool>.Type:
          return try decodeBaseTypeArray(type, Bool.self,   forKey: key)
        
        default:
          // Note: This does not fly!:
          //         case let atype as Array<CodableObjectType>.Type
          //       the type is something concrete, like Array<Person>
          
          // OK: Deal with arrays and other objects we don't directly
          //     control.
          return try decodeOtherType(type, forKey: key)
        }
    }
    
    private
    func decodeImplicitRelationshipHolder<T>(_ type: T.Type, forKey key: Key)
      throws -> T
      where T : Decodable
    {
      // Right now this is an Array, eg `var addresses : [ Address ]`.
      // We just want to return an empty array here.
      // TBD: maybe we should create another nested coder?
      
      decoder.codingPath.append(key) // this is the key we are going to use
      let v = try type.init(from: decoder) // init the ('array' expected)
      decoder.codingPath.removeLast()
      
      return v
    }
    
    func decodeOtherType<T>(_ type: T.Type, forKey key: Key) throws -> T
      where T : Decodable
    {
      log.trace("out of band type:", type, "for key:", key)
      
      assert(!(type is ImplicitToManyRelationshipHolder.Type))
      throw Error.unsupportedNesting
    }
    
    /**
     * Decode base type column arrays, like `[ Int ]`
     */
    func decodeBaseTypeArray<T, E>(_ type: T.Type,
                                   _ elementType: E.Type,
                                   forKey key: Key) throws -> T
      where T : Decodable
    {
      log.error("TODO: Array<Int>")
      throw Error.unsupportedValueType(type)
    }
    
    /**
     * This decodes a `ToMany` or `ToOne` wrapper object.
     *
     * `erasedHolderType` and `reflectedHolderType` refer to the same
     * `ToOne` or `ToMany` type.
     * The first is just the typed erased version (generic `Decodable`),
     * while the other was reflected on.
     */
    private
    func decodeRelationshipHolder<T>(erasedHolderType : T.Type,
                                     forKey key       : Key) throws -> T
      where T : Decodable
    {
      guard let reflectedHolderType =
        erasedHolderType as? RelationshipHolderType.Type
        else {
          throw Error.unexpectedRelationshipHolderType
      }
      
      // e.g. ToManyRelationshipHolder<T>
      log.trace("decode `RelationshipHolderType`:",
                key.stringValue, erasedHolderType, reflectedHolderType)
      // TODO: create a ToOne/ToMany instance as requested (with no value)
      throw Error.unsupportedValueType(erasedHolderType)
   }
    
    /**
     * This decodes a `CodableObjectType` when it is used inline (aka is type
     * erased).
     * For example:
     *
     *     class House { var owner : Person }
     *
     * This is not actually supported in the AdaptorDecoder.
     */
    private func decodeDecodableObject<T>(_ type: T.Type,
                                          forKey key: Key) throws -> T
                   where T : Decodable
    {
      log.trace(":decode:", key.stringValue, type)
      throw Error.unsupportedValueType(type) // FIXME: proper error
    }
    
    /**
     * Extract the property (attribute or relationship) name of the key.
     * Ideally this would be the Swift property name, but it looks we can't
     * grab that anymore in 4.1 :-<
     */
    func nameForKey(_ key: Key) -> String {
      // Description gives:
      //
      //   CodingKeys(stringValue: "id", intValue: nil)
      //
      // This is not really what we want, we want to reflect the original
      // key.
      // But maybe this has to do for now (and we should do it on 4.0 too.
      #if true // we want this as the external name
        return key.stringValue
      #else
        return "\(key)" // was stretched and fails on 4.1.snapshot
      #endif
    }
    
    // Note: I think we need to implement each, because we need to return the
    //       value (otherwise we would need to add a protocol w/ a default
    //       ctor)
    
    func valueForKey(_ key: Key) throws -> Any {
      let name = nameForKey(key)
      guard let record = decoder.record else {
        throw Error.notImplemented // FIXME
      }
      guard let anyValue = record[name] else {
        throw Error.notImplemented // FIXME - nil
      }
      log.trace("decoded-value for key:", key, anyValue)
      return anyValue
    }
    func decodeBaseType<T>(forKey key: Key) throws -> T {
      let anyValue = try valueForKey(key)
      guard let v = anyValue as? T else {
        log.error("unexpected base value:", key,
                  "\n  value:", anyValue,
                  "\n  types:",
                  type(of: anyValue), "vs", T.self, "\n")
        throw Error.unsupportedValueType(T.self)
      }
      log.trace("decoded-key:", key, v)
      return v
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
      // FIXME: Hm?!
      let anyValue = try valueForKey(key)
      switch anyValue {
        case let v as Int8:  return Int(v)
        case let v as Int16: return Int(v)
        case let v as Int32: return Int(v)
        case let v as Int64: return Int(v)
        // TODO: refactor and enhance
        default: return try decodeBaseType(forKey: key)
      }
    }
    func decode(_ type: Int8.Type,  forKey key: Key) throws -> Int8 {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
      return try decodeBaseType(forKey: key)
    }
    
    func decode(_ type: UInt.Type,   forKey key: Key) throws -> UInt {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: UInt8.Type,  forKey key: Key) throws -> UInt8 {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
      return try decodeBaseType(forKey: key)
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
      return try decodeBaseType(forKey: key)
    }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
      return try decodeBaseType(forKey: key)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
      let name = nameForKey(key)
      return decoder.record?[name] == nil
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type,
                                    forKey key: Key) throws
           -> KeyedDecodingContainer<NestedKey>
           where NestedKey : CodingKey
    {
      //return try decoder.container(keyedBy: type)
      throw Error.unsupportedNesting
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws
           -> UnkeyedDecodingContainer
    {
      //return try decoder.unkeyedContainer()
      throw Error.unsupportedNesting
    }
    
    func superDecoder() throws -> Decoder {
      return decoder
    }
    func superDecoder(forKey key: Key) throws -> Decoder {
      return decoder
    }
  }

  /**
   * Right now the sole purpose of this is to decode an array of
   * `CodableObjectType` aka an implicit toMany relationship:
   *
   *     var addresses : [ Address ]
   *
   */
  internal struct UnkeyedContainer<T: Decodable> : UnkeyedDecodingContainer {
    // TBD: is this also for `[ Int ]` and such? (I think we want to capture
    //      those earlier as `[Int]`, `[Float]` etc).
    let log          : ZeeQLLogger
    let decoder      : AdaptorRecordDecoder<T>
    
    let sourceKey    : CodingKey
    
    let codingPath   = [ CodingKey ]()
    var currentIndex : Int = 0
    var isAtEnd      : Bool { return true }
    
    var count : Int? { return 0 } // no need to decode anything!

    init(decoder : AdaptorRecordDecoder<T>, key : CodingKey) {
      self.decoder   = decoder
      self.log       = decoder.log
      self.sourceKey = key
    }
    
    
    // MARK: - Main decoding function
    
    /**
     * Decode the item type of the array, i.e. the `Address` in
     * `[ Address ]`.
     *
     * We create our ToMany relationship in here.
     */
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
      log.trace("decode index:", currentIndex, type, "source-key:", sourceKey)
      throw Error.adaptorCannotDecodeRelationships
    }
    
    // MARK: - Base Decoders, not supported in this specific container
    
    func decodeNil() -> Bool {
      return true // always report nil
    }
    public mutating func decode(_ type: Bool.Type) throws -> Bool {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: String.Type) throws -> String {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: Int.Type) throws -> Int {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: Int8.Type) throws -> Int8 {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: Int16.Type) throws -> Int16 {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: Int32.Type) throws -> Int32 {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: Int64.Type) throws -> Int64 {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: UInt.Type) throws -> UInt {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
      throw Error.unsupportedValueType(type)
    }
    public mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
      throw Error.unsupportedValueType(type)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
           -> KeyedDecodingContainer<NestedKey>
           where NestedKey : CodingKey
    {
      throw Error.unsupportedNesting
    }
    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
      throw Error.unsupportedNesting
    }
    
    func superDecoder() throws -> Decoder {
      return decoder
    }
  }
}
