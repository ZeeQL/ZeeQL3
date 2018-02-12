//
//  CodableModelEntityDecoder.swift
//  ZeeQL3
//
//  Created by Helge Hess on 10.02.18.
//  Copyright © 2018 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)
  import Foundation

  /**
   * Just a helper type to check whether a decoder is a
   * `CodableModelEntityDecoder`.
   */
  internal protocol ReflectingDecoderType {}
  
  extension CodableModelDecoder {

    final class CodableModelEntityDecoder<EntityType: Decodable>
                  : Decoder, ReflectingDecoderType
    {
      let state      : CodableModelDecoder
      var log        : ZeeQLLogger
      let entity     : CodableEntityType
      
      var codingPath : [ CodingKey ]
      var userInfo   : [ CodingUserInfoKey : Any ] { return state.userInfo }

      /// helper, remove this
      var codingPathKK : String {
        return codingPath.map { $0.stringValue }.joined(separator: ".")
      }

      init(state: CodableModelDecoder, entity: CodableEntityType) {
        self.state      = state
        self.log        = state.log
        self.entity     = entity
        self.codingPath = state.codingPath
      }
      
      func container<Key>(keyedBy type: Key.Type) throws
             -> KeyedDecodingContainer<Key> where Key : CodingKey
      {
        // Technically the user can have multiple 'Key' types. But that
        // doesn't (really) make sense for us.
        
        // TODO: It would be good to detect additional cycles here. That is, only
        //       create a single container and protect against multiple calls.
        
        log.trace("\("  " * codingPath.count)DC[\(codingPathKK)]:",
                  "get-keyed-container<\(type)>")
        return KeyedDecodingContainer(
          EntityPropertyReflectionContainer<EntityType, Key>(
                                              decoder: self, entity: entity))
      }
      
      func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard let key = codingPath.last else {
          log.error("missing coding key:", codingPath, self)
          throw Error.missingKey
        }
        
        log.trace("\("  " * codingPath.count)DC[\(codingPathKK)]:",
                  "get-unkeyed-container",
                  "\n  source:    ", entity,
                  "\n  source-key:", key)
        return EntityCollectionPropertyReflectionContainer(
                 decoder: self, entity: entity, key: key,
                 codingPath: codingPath)
      }
      
      func singleValueContainer() throws -> SingleValueDecodingContainer {
        log.trace("\("  " * codingPath.count)DC[\(codingPathKK)]:",
                  "get-value-container")
        return SingleContainer(decoder: self)
      }
      
      // MARK: - SingleContainer
      
      private struct SingleContainer<EntityType: Decodable>
                       : SingleValueDecodingContainer
      {
        let log          : ZeeQLLogger
        let decoder      : CodableModelEntityDecoder<EntityType>
        var codingPath   : [ CodingKey ] { return decoder.codingPath }
        
        init(decoder: CodableModelEntityDecoder<EntityType>) {
          self.decoder = decoder
          self.log     = decoder.log
        }
        
        func decodeNil() -> Bool {
          log.log("\("  " * codingPath.count)SC[\(codingPath)]:decodeNil")
          return false
        }
        
        func decode(_ type: Bool.Type)   throws -> Bool   { return true }
        func decode(_ type: Int.Type)    throws -> Int    { return  42 }
        func decode(_ type: Int8.Type)   throws -> Int8   { return  48 }
        func decode(_ type: Int16.Type)  throws -> Int16  { return 416 }
        func decode(_ type: Int32.Type)  throws -> Int32  { return 432 }
        func decode(_ type: Int64.Type)  throws -> Int64  { return 464 }
        func decode(_ type: UInt.Type)   throws -> UInt   { return 142 }
        func decode(_ type: UInt8.Type)  throws -> UInt8  { return 148 }
        func decode(_ type: UInt16.Type) throws -> UInt16 { return 116 }
        func decode(_ type: UInt32.Type) throws -> UInt32 { return 132 }
        func decode(_ type: UInt64.Type) throws -> UInt64 { return 164 }
        
        func decode(_ type: Float.Type)  throws -> Float  { return 42.42 }
        func decode(_ type: Double.Type) throws -> Double { return 4242.42 }
        
        func decode(_ type: String.Type) throws -> String {
          log.log("\("  " * codingPath.count)SC[\(codingPath)]:decodeString")
          return "Dooo"
        }
        
        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
          throw Error.unsupportedSingleValue
        }
        
      }
    }
  }
  
#endif // Swift 4
