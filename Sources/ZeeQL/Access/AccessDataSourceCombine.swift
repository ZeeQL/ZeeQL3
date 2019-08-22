//
//  AccessDataSourceCombine.swift
//  ZeeQL
//
//  Created by Helge Heß on 22.08.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

#if canImport(Combine)

import class  Dispatch.DispatchQueue
import struct Combine.AnyPublisher
import class  Combine.Future

@available(iOS 13, tvOS 13, OSX 10.15, watchOS 6, *)
public extension AccessDataSource {
  
  func fetchObjects(_ fs: FetchSpecification,
                    on queue: DispatchQueue = .global())
       -> AnyPublisher<Object, Error>
  {
    AccessDataSourcePublisher(
      dataSource: self, fetchSpecification: fs, queue: queue
    )
    .eraseToAnyPublisher()
  }
  
  func fetchCount(_ fs: FetchSpecification,
                  on queue: DispatchQueue = .global())
       -> AnyPublisher<Int, Error>
  {
    Future { promise in
      queue.async {
        do {
          // TBD: Why isn't this public? I guess because we are supposed to
          //      set the FS on the datasource.
          let count = try self._primaryFetchCount(fs)
          promise(.success(count))
        }
        catch {
          promise(.failure(error))
        }
      }
    }
    .eraseToAnyPublisher()
  }
  
}

#endif // canImport(Combine)

