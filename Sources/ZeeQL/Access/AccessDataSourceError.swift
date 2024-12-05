//
//  AccessDataSourceError.swift
//  ZeeQL
//
//  Created by Helge Heß on 22.08.19.
//  Copyright © 2019-2024 ZeeZide GmbH. All rights reserved.
//

public enum AccessDataSourceError: Swift.Error {
  // cannot nest in generic
  
  public enum ConstructionErrorReason: Equatable {
    case missingEntity
    case bindingFailed
    case invalidPrimaryKey
  }

  case CannotConstructFetchSpecification(ConstructionErrorReason)
  case CannotConstructCountFetchSpecification
  case MissingEntity
  case CountFetchReturnedNoResults
  case FetchReturnedMoreThanOneResult(fetchSpecification: FetchSpecification,
                                      firstObject: SwiftObject)
  
  case DidNotFindFetchSpecification(name: String, entity: Entity)
  case CouldNotResolveBindings(fetchSpecification: FetchSpecification,
                               bindings: Any)
}
