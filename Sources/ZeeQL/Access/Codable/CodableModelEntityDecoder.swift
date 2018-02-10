//
//  CodableModelEntityDecoder.swift
//  ZeeQL3
//
//  Created by Helge Hess on 10.02.18.
//  Copyright © 2018 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)
  import Foundation

  extension CodableModelDecoder {
    
    class CodableModelEntityDecoder<EntityType: Codable> : Decoder {
      
      let state      : CodableModelDecoder
      var codingPath : [ CodingKey ] { return state.codingPath }
      var userInfo   : [ CodingUserInfoKey : Any ] { return state.userInfo }
      
      init(state: CodableModelDecoder) {
        self.state = state
      }
      
      func container<Key>(keyedBy type: Key.Type) throws
             -> KeyedDecodingContainer<Key> where Key : CodingKey
      {
        return try state.container(keyedBy: type)
      }
      
      func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return try state.unkeyedContainer()
      }
      
      func singleValueContainer() throws -> SingleValueDecodingContainer {
        return try state.singleValueContainer()
      }
      
    }
  }
  
#endif // Swift 4
