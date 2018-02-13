//
//  SQLite3CodableTests.swift
//  ZeeQL3
//
//  Created by Helge Hess on 12.02.18.
//  Copyright © 2018 ZeeZide GmbH. All rights reserved.
//

import XCTest
import Foundation
@testable import ZeeQL

class SQLite3CodableTests: XCTestCase {
  #if swift(>=4.0)

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
      
      print("objects:", objects)
      XCTAssertEqual(objects.count, 3)
    }
    catch {
      XCTFail("Unexpected error: \(error)")
    }
  }


  // MARK: - Non-ObjC Swift Support
  
  static var allTests = [
    ( "testRawAdaptorQuery", testRawAdaptorQuery )
  ]
  
  #else // Not Swift 4
  
  static var allTests = [(String, (SQLite3CodableTests) -> () -> ())]()
  
  #endif // Not Swift 4
}

#if swift(>=4.0)

// TDD ;-)

/**
 * Decode plain Decodable objects from adaptor records.
 *
 * Adaptor queries can use relationships to query specific information
 * (i.e. use pathes in fetch specs), but they cannot themselves
 * follow relationships.
 * A database channel / object tracking context can be used for that.
 */
class AdaptorRecordDecoder<T: Decodable> : Decoder {
  
  enum Error : Swift.Error {
    case notImplemented
    case adaptorCannotDecodeRelationships
    case unsupportedValueType(Any.Type)
  }
  
  var log : ZeeQLLogger { return globalZeeQLLogger }

  var codingPath = [ CodingKey] ()
  var userInfo   = [ CodingUserInfoKey : Any ]()
  
  var record : AdaptorRecord? = nil
  
  func decode(record: AdaptorRecord) throws -> T {
    assert(self.record == nil, "record still assigned?!")
    defer { clear() }
    
    self.record = record
    let object = try T(from: self)
    
    return object
  }
  
  func clear() {
    codingPath.removeAll()
    userInfo.removeAll()
    record = nil
  }
  
  func container<Key>(keyedBy type: Key.Type) throws
         -> KeyedDecodingContainer<Key> where Key : CodingKey
  {
    log.trace("get-keyed-container<\(type)>")
    #if false // TDD
      return KeyedDecodingContainer(KeyedContainer<T, Key>(decoder: self))
    #else
      throw Error.notImplemented
    #endif
  }
  
  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    throw Error.notImplemented
  }
  
  func singleValueContainer() throws -> SingleValueDecodingContainer {
    throw Error.notImplemented
  }

  #if false // TDD
  
  /* Containers */
  
  final class KeyedContainer<T: Decodable, Key: CodingKey>
                : KeyedDecodingContainerProtocol
  {
    let decoder : AdaptorRecordDecoder<T>
    let log     : ZeeQLLogger
    
    init(decoder: AdaptorRecordDecoder<T>) {
      self.decoder = decoder
      self.log     = decoder.log
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
      /*
       This is tricky. We need to communicate to the decoder, that we are
       decoding a property.
       What do we want? We want to collect relationship types. I.e. this:
       var addresses : [ Address ]
       we want to add to the `entity` of this containers entity, the
       class property `addresses` as a ToMany<Address>.
       So how do we do this?
       We somehow need to track, that we decoded an [ CodingType ]?
       */
      
      decoder.codingPath.append(key) // this is the key we are going to use
      //let v = try decoder.decode(type)
      let v = try type.init(from: decoder) // init the ('array' expected)
      decoder.codingPath.removeLast()
      
      #if false
        if let cota = v as? Array<CodableObjectType> {
          // ^^ we can't dispatch on the static type. But we *can* dispatch on
          //    the dynamic type :-)
          // Maybe we can handle this earlier, but at least in here, we know
          // the proper type.
          // => We should probably handle it earlier.
          print("TODO: it is an array of CodableObjectType!")
        }
      #endif
      
      return v
    }
    
    func decodeOtherType<T>(_ type: T.Type, forKey key: Key) throws -> T
      where T : Decodable
    {
      // effectively this is: `decodeCodableObjectArray<T>`
      log.trace("out of band type:", type, "for key:", key)
      
      assert(!(type is ImplicitToManyRelationshipHolder.Type))
      
      if !decoder.state.options.enforceCodableObjectType {
        // We allow arbitrary Decodable objects!
        // FIXME: this doesn't work right for arrays
        return try decodeDecodableObject(type, forKey: key)
      }
      
      /*
       This is tricky. We need to communicate to the decoder, that we are
       decoding a property.
       What do we want? We want to collect relationship types. I.e. this:
       var addresses : [ Address ]
       we want to add to the `entity` of this containers entity, the
       class property `addresses` as a ToMany<Address>.
       So how do we do this?
       We somehow need to track, that we decoded an [ CodingType ]?
       */
      
      decoder.codingPath.append(key) // this is the key we are going to use
      //let v = try decoder.decode(type)
      let v = try type.init(from: decoder) // init the ('array' expected)
      decoder.codingPath.removeLast()
      
      #if false
        if let cota = v as? Array<CodableObjectType> {
          // ^^ we can't dispatch on the static type. But we *can* dispatch on
          //    the dynamic type :-)
          // Maybe we can handle this earlier, but at least in here, we know
          // the proper type.
          // => We should probably handle it earlier.
          print("TODO: it is an array of CodableObjectType!")
        }
      #endif
      
      return v
    }
    
    /**
     * Decode base type column arrays, like `[Int]`
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
      log.trace("\("  " * codingPath.count)",
        "KC[\(entity.name):\(codingPathKK)]:",
        "decode `RelationshipHolderType`:",
        key.stringValue, erasedHolderType)
      
      // In here because we need the key for the relship name
      let targetEntity =
        try reflectedHolderType.reflectTargetType(on: decoder.state)
      // make sure the target is there (no recursion because we unique,
      // but this may be different if we do free-form)
      
      let name = nameForKey(key)
      //let extName = key.stringValue == name ? nil : key.stringValue
      
      if entity[relationship: name] == nil {
        let rs : Relationship =
          reflectedHolderType.makeRelationship(name: name,
                                               isOptional: nilKeys.contains(key),
                                               source: entity, sourceType: EntityType.self,
                                               destination: targetEntity)
        // TODO: push extName for constraint?
        
        entity.relationships.append(rs)
        // entity.attributes.append(makeAttribute(type, forKey: key))
        entity.addClassPropertyName(nameForKey(key))
      }
      else {
        log.error("already registered relationship:", name, "in", entity)
      }
      
      // The `To-x-RelationshipHolder` objects have special support for our
      // coder, so this is a little easier.
      return try erasedHolderType.init(from: decoder) // we need some init
    }
    
    /**
     * This decodes a `CodableObjectType` when it is used inline (aka is type
     * erased).
     * For example:
     *
     *     class House { var owner : Person }
     *
     * It calls into `decoder.decode()` to do its job.
     */
    private func decodeDecodableObject<T>(_ type: T.Type,
                                          forKey key: Key) throws -> T
      where T : Decodable
    {
      log.trace("\("  " * codingPath.count)KC[\(entity.name):",
        "\(codingPathKK)]:decode:", key.stringValue, type)
      
      let name = nameForKey(key)
      if entity[relationship: name] == nil {
        // TBD: The container is type erased wrt CodableObjectType. Can we
        //      still somehow ask the Type to make the relationship, like
        //      above?
        let destEntity = decoder.state.existingEntityForType(type)
        let rs = DecodableRelationship<T>(name: name, isToMany: false,
                                          isMandatory : !nilKeys.contains(key),
                                          source      : entity,
                                          destination : destEntity)
        // TODO: push extName for constraint?
        log.trace("\("  " * codingPath.count)KC[\(entity.name): created:", rs)
        
        entity.relationships.append(rs)
        // entity.attributes.append(makeAttribute(type, forKey: key))
        entity.addClassPropertyName(name)
      }
      else {
        log.log("already registered relationship:", name, "in", entity)
      }
      
      
      // let the main decoder handle this
      decoder.codingPath.append(key)
      let v = try decoder.state.decode(type) // TODO: replace?
      decoder.codingPath.removeLast()
      
      
      // post process relationship
      
      if let rs = entity[relationship: name],
        let mrs = rs as? ModelRelationship,
        mrs.destinationEntity == nil
      {
        // we didn't have the entity yet
        if let targetEntity = decoder.state.existingEntityForType(type) {
          mrs.destinationEntity = targetEntity
        }
        else {
          // register the relship for patching
          log.trace("did not decode target relationship, register:",
                    name, "in", entity)
          decoder.state.registerForPendingEntity(type, relationship: mrs)
        }
      }
      
      return v
    }
    
    /**
     * Extract the property (attribute or relationship) name of the key.
     * Ideally this would be the Swift property name, but it looks we can't
     * grab that anymore in 4.1 :-<
     */
    func nameForKey(_ key: Key) -> String {
      #if swift(>=4.1)
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
      #else
        return "\(key)" // well, this is a little stretched
      #endif
    }
    
    /// Create a typed attribute for the given key.
    func makeAttribute<T>(_ t: T.Type, forKey key: Key) -> Attribute
      where T: AttributeValue
    {
      // FIXME: This doesn't take Optional into account
      let name    = nameForKey(key)
      let extName = key.stringValue == name ? nil : key.stringValue
      
      let attr : Attribute
      if nilKeys.contains(key) {
        attr = CodeAttribute<Optional<T>>(name, column: extName)
      }
      else {
        attr = CodeAttribute<T>(name, column: extName)
      }
      log.trace("makeAttribute:", t,
                "name:", name, "ext:", extName, "key:", key,
                "\n  attr:", attr)
      return attr
    }
    
    func addAttribute<T>(_ type: T.Type, forKey key: Key) -> Bool
      where T: AttributeValue
    {
      guard entity[attribute: nameForKey(key)] == nil else {
        log.trace("already registered attribute:", key, "in", entity)
        return false
      }
      log.trace("\("  " * codingPath.count)KC[\(entity.name):",
        "\(codingPathKK)]:decode:", key.stringValue, key, type)
      entity.attributes.append(makeAttribute(type, forKey: key))
      entity.addClassPropertyName(nameForKey(key))
      return true
    }
    
    // Note: I think we need to implement each, because we need to return the
    //       value (otherwise we would need to add a protocol w/ a default
    //       ctor)
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? -1337 : -1338
    }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? -13 : -14
    }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? -1337 : -1338
    }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? -11337 : -11338
    }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? -111337 : -111338
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? 1337 : 1338
    }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? 13 : 14
    }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? 1337 : 1338
    }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? 11337 : 11338
    }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> Int {
      return addAttribute(type, forKey: key) ? 111337 : 111338
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
      return addAttribute(type, forKey: key) ? "kasse7" : "kasse8"
    }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
      return addAttribute(type, forKey: key)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
      if nilKeys.contains(key) {
        // return nil if we already know this key!
        // This allows cycles on optional items!
        log.trace("\("  " * codingPath.count)KC[\(entity.name):",
          "\(codingPathKK)]:decodeNil:", key.stringValue,
          "AS-NIL-was-nil")
        return true
      }
      
      // We should check whether the entity already has that class
      // property already. If so, there is no need to decode any
      // further.
      if let cp = entity.classPropertyNames, cp.contains(nameForKey(key)) {
        // return nil if we already know this key!
        // This allows cycles on optional items!
        log.trace("\("  " * codingPath.count)KC[\(entity.name):",
          "\(codingPathKK)]:decodeNil:", key.stringValue,
          "AS-NIL-prop-exists")
        return true
      }
      
      log.trace("\("  " * codingPath.count)KC[\(entity.name):",
        "\(codingPathKK)]:decodeNil:", key.stringValue, "NOT-NIL")
      // Note: so it first calls `contains(:)`, if that returns true,
      //       an Optional still calls decodeNil.
      //       And this returns true for nil values, or false otherwise
      nilKeys.insert(key)
      // we do NOT want nil, we want to fake existence
      return false
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
  #endif // TDD
}

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
#endif // Swift 4+

