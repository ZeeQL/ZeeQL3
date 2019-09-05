//
//  OActiveRecord.swift
//  ZeeQL3
//
//  Created by Helge Heß on 05.09.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

#if canImport(Combine)

import protocol Combine.ObservableObject
import class    Combine.PassthroughSubject

/**
 * Like an `ActiveRecord`, but is a Combine `ObservableObject`. I.e. one can
 * subscribe to `objectWillChange` events.
 */
@available(iOS 13, tvOS 13, watchOS 6, macOS 13, *)
open class OActiveRecord : ActiveRecord, ObservableObject {
  // Looks like we can't add this to the `ActiveRecord` using @availability
  // features.
  // Defining the `objectWillChange` property in an extension, will link in
  // Combine, which fails on older platforms :-/

  public let objectWillChange = PassthroughSubject<Void, Never>()

  override open func willChange() {
    objectWillChange.send()
    super.willChange()
  }
}

#endif
