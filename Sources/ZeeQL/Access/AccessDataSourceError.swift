//
//  AccessDataSourceError.swift
//  ZeeQL
//
//  Created by Helge Heß on 22.08.19.
//  Copyright © 2019 ZeeZide GmbH. All rights reserved.
//

public enum AccessDataSourceError : Swift.Error { // cannot nest in generic
  case CannotConstructFetchSpecification
  case CannotConstructCountFetchSpecification
  case CountFetchReturnedNoResults
  case FetchReturnedMoreThanOneResult(fetchSpecification: FetchSpecification,
                                      firstObject: SwiftObject)
}
