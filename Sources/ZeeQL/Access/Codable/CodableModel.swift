//
//  CodableModel.swift
//  ZeeQL3
//
//  Created by Helge Hess on 12.02.18.
//  Copyright © 2018 ZeeZide GmbH. All rights reserved.
//

#if swift(>=4.0)
public extension Model {
  // This has all those dupes, because we want to capture the full static type.
  // It is a little stupid, but hey, type safety!
  
  public typealias CodableOptions = CodableModelDecoder.Options
  
  // MARK: - Decodable
  
  static func createFromTypes<T1: CodableObjectType>
                (_ t1: T1.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType,
                              T4: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType,
                              T4: CodableObjectType,
                              T5: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType,
                              T4: CodableObjectType,
                              T5: CodableObjectType,
                              T6: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType,
                              T4: CodableObjectType,
                              T5: CodableObjectType,
                              T6: CodableObjectType,
                              T7: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType,
                              T4: CodableObjectType,
                              T5: CodableObjectType,
                              T6: CodableObjectType,
                              T7: CodableObjectType,
                              T8: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type, _ t8: T8.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    try builder.add(t8)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType,
                              T4: CodableObjectType,
                              T5: CodableObjectType,
                              T6: CodableObjectType,
                              T7: CodableObjectType,
                              T8: CodableObjectType,
                              T9: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type, _ t8: T8.Type,
                 _ t9: T9.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    try builder.add(t8)
    try builder.add(t9)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: CodableObjectType,
                              T2: CodableObjectType,
                              T3: CodableObjectType,
                              T4: CodableObjectType,
                              T5: CodableObjectType,
                              T6: CodableObjectType,
                              T7: CodableObjectType,
                              T8: CodableObjectType,
                              T9: CodableObjectType,
                              TX: CodableObjectType>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type, _ t8: T8.Type,
                 _ t9: T9.Type, _ t10: TX.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    try builder.add(t8)
    try builder.add(t9)
    try builder.add(t10)
    return builder.buildModel()
  }

  
  // MARK: - Plain Decodable

  static func createFromTypes<T1: Decodable>
                (_ t1: T1.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable,
                              T4: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable,
                              T4: Decodable,
                              T5: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable,
                              T4: Decodable,
                              T5: Decodable,
                              T6: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable,
                              T4: Decodable,
                              T5: Decodable,
                              T6: Decodable,
                              T7: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable,
                              T4: Decodable,
                              T5: Decodable,
                              T6: Decodable,
                              T7: Decodable,
                              T8: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type, _ t8: T8.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    try builder.add(t8)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable,
                              T4: Decodable,
                              T5: Decodable,
                              T6: Decodable,
                              T7: Decodable,
                              T8: Decodable,
                              T9: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type, _ t8: T8.Type,
                 _ t9: T9.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    try builder.add(t8)
    try builder.add(t9)
    return builder.buildModel()
  }
  
  static func createFromTypes<T1: Decodable,
                              T2: Decodable,
                              T3: Decodable,
                              T4: Decodable,
                              T5: Decodable,
                              T6: Decodable,
                              T7: Decodable,
                              T8: Decodable,
                              T9: Decodable,
                              TX: Decodable>
                (_ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type, _ t4: T4.Type,
                 _ t5: T5.Type, _ t6: T6.Type, _ t7: T7.Type, _ t8: T8.Type,
                 _ t9: T9.Type, _ t10: TX.Type,
                 options: CodableOptions = CodableOptions()) throws -> Model
  {
    let builder = CodableModelDecoder(options: options)
    try builder.add(t1)
    try builder.add(t2)
    try builder.add(t3)
    try builder.add(t4)
    try builder.add(t5)
    try builder.add(t6)
    try builder.add(t7)
    try builder.add(t8)
    try builder.add(t9)
    try builder.add(t10)
    return builder.buildModel()
  }
}

#endif /* swift(>=4.0) */
