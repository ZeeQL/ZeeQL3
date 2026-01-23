//
//  AccessDataSourceError.swift
//  ZeeQL
//
//  Created by Helge Heß on 22.08.19.
//  Copyright © 2019-2026 ZeeZide GmbH. All rights reserved.
//

public enum AccessDataSourceError: Swift.Error {
  // cannot nest in generic
  
  public enum ConstructionErrorReason: Equatable {
    
    case missingEntity
    case bindingFailed
    case invalidPrimaryKey
  }

  case cannotConstructFetchSpecification(ConstructionErrorReason)
  case cannotConstructCountFetchSpecification
  case missingEntity
  case countFetchReturnedNoResults
  case fetchReturnedMoreThanOneResult(fetchSpecification: FetchSpecification,
                                      firstObject: SwiftObject)

  case didNotFindFetchSpecification(name: String, entity: Entity)
  case couldNotResolveBindings(fetchSpecification: FetchSpecification,
                               bindings: Any)
}
