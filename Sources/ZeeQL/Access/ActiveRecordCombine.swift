//
//  ActiveRecordCombine.swift
//  ZeeQL3
//
//  Created by Helge Heß on 05.09.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

#if canImport(Combine)
import Combine

@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public extension ActiveRecord {
  var objectWillChange : PassthroughSubject<Void, Never> {
    if let subject =
      _objectWillChangeHolder as? PassthroughSubject<Void, Never> {
      return subject
    }
    let subject = PassthroughSubject<Void, Never>()
    _objectWillChangeHolder = subject
    return subject
  }
}
#endif
