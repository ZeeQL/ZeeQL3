//
//  AccessDataSourcePublisher.swift
//  ZeeQL
//
//  Created by Helge Heß on 22.08.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

#if canImport(Combine)
import Combine
import class Dispatch.DispatchQueue
import class Foundation.NSLock

@available(iOS 13, tvOS 13, OSX 10.15, watchOS 6, *)
internal
struct AccessDataSourcePublisher<DataSource,Object>: Publisher
                where Object: SwiftObject,
                      DataSource: AccessDataSource<Object>
{
  typealias Output  = Object
  typealias Failure = Swift.Error
  
  private let queue              : DispatchQueue
  private let dataSource         : DataSource
  private let fetchSpecification : FetchSpecification

  init(dataSource         : DataSource,
       fetchSpecification : FetchSpecification,
       queue              : DispatchQueue)
  {
    self.queue      = queue
    self.dataSource = dataSource
    self.fetchSpecification = fetchSpecification
  }

  func receive<S>(subscriber: S)
         where S: Subscriber, Failure == S.Failure, Output == S.Input
  {
    let subscription = AccessDataSourceSubscription(
      dataSource: dataSource,
      fetchSpecification: fetchSpecification,
      subscriber: subscriber,
      queue: queue
    )
    subscriber.receive(subscription: subscription)
  }
}

@available(iOS 13, tvOS 13, OSX 10.15, watchOS 6, *)
internal
final class AccessDataSourceSubscription<DataSource,SubscriberType>
            : Subscription
              where DataSource: AccessDataSource<SubscriberType.Input>,
                    SubscriberType: Subscriber,
                    SubscriberType.Failure == Swift.Error
{
  // Note: Careful w/ that. It assumes that ZeeQL is thread safe, which is
  //       not necessarily true :-) Be diligent with the queue.
  
  private let queue              : DispatchQueue
  private let dataSource         : DataSource
  private let fetchSpecification : FetchSpecification
  private let lock               = Foundation.NSLock()
  private var didResume          = false
  private var subscriber         : SubscriberType?
  
  init(dataSource         : DataSource,
       fetchSpecification : FetchSpecification,
       subscriber         : SubscriberType,
       queue              : DispatchQueue)
  {
    self.queue      = queue
    self.subscriber = subscriber
    self.dataSource = dataSource
    self.fetchSpecification = fetchSpecification
  }

  func request(_ demand: Subscribers.Demand) {
    // We ignore the demand, but wait for the first: unlimited, none, max(Int)
    lock.lock()
    let doResume = !didResume
    didResume = true
    lock.unlock()
    
    if doResume { resume() }
  }
  
  func cancel() {
    lock.lock()
    subscriber = nil
    lock.unlock()
  }
  
  private func getSubscriber() -> SubscriberType? {
    lock.lock(); defer { lock.unlock() }
    return subscriber
  }
  
  private func resume() {
    queue.async {
      // TBD: this can feed before the function returns. Is this an issue?
      // Yes, I think so. We should only send values once we got a subscription!
      // And even then we can decide whether each subscription should re-query?
      do {
        try self.dataSource.fetchObjects(self.fetchSpecification) { object in
          // we can detect cancellable via `subscriber` == nil, but
          // ZeeQL right now has no cancel API in this place :-)
          _ = self.getSubscriber()?.receive(object)
            // returns subsequent demand, which we ignore!
        }
        self.getSubscriber()?.receive(completion: .finished)
      }
      catch {
        self.getSubscriber()?.receive(completion: .failure(error))
      }
    }
  }
}
#endif // canImport(Combine)
