//
//  ExpressionEvaluation.swift
//  ZeeQL
//
//  Created by Helge Hess on 16/02/2017.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

public protocol ExpressionEvaluation {
  
  func valueForObject(_ object: Any?) -> Any?
  
}
