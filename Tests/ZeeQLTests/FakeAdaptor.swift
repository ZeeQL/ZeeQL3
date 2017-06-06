//
//  FakeAdaptor.swift
//  ZeeQL3
//
//  Created by Helge Hess on 06/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import ZeeQL

class FakeAdaptor : Adaptor {

  var expressionFactory = SQLExpressionFactory()
  var model             : Model?
  var fakeFetchModel    : Model?
  
  var sqlCalls = [ String ]()
  
  public init(model: Model? = nil) {
    self.model = model
  }
  
  public func openChannel() throws -> AdaptorChannel {
    return FakeAdaptorChannel(adaptor: self)
  }

  public func fetchModel() throws -> Model {
    return fakeFetchModel ?? model ?? Model(entities: [])
  }
  
  func fetchModelTag() throws -> ModelTag {
    return FakeModelTag()
  }
  
  struct FakeModelTag : ModelTag {
    public func isEqual(to object: Any?) -> Bool {
      return object is FakeModelTag
    }
  }
  
  class FakeAdaptorChannel : AdaptorChannel {
    
    let expressionFactory : SQLExpressionFactory
    let model : Model
    weak var adaptor : FakeAdaptor?
  
    init(adaptor: Adaptor) {
      self.adaptor           = adaptor as? FakeAdaptor
      self.expressionFactory = adaptor.expressionFactory
      
      self.model = (adaptor as? FakeAdaptor)?.fakeFetchModel
                ?? adaptor.model ?? Model(entities:[])
    }
    
    public func querySQL(_ sql: String, _ optAttrs: [Attribute]?,
                         cb: (AdaptorRecord) throws -> Void) throws
    {
      adaptor?.sqlCalls.append(sql)
    }
    func performSQL(_ sql: String) throws -> Int {
      adaptor?.sqlCalls.append(sql)
      return 0
    }
    
    func evaluateQueryExpression(_ sqlexpr  : SQLExpression,
                                 _ optAttrs : [ Attribute ]?,
                                 result: ( AdaptorRecord ) throws -> Void) throws
    {
      adaptor?.sqlCalls.append(sqlexpr.statement)
    }
    
    func evaluateUpdateExpression(_ sqlexpr  : SQLExpression) throws -> Int {
      adaptor?.sqlCalls.append(sqlexpr.statement)
      return 0
    }
    
    func describeTableNames() throws -> [ String ] {
      return model.entities.map { $0.externalName ?? $0.name }
    }
    
    func describeSequenceNames() throws -> [ String ] { return [] }
    func describeDatabaseNames() throws -> [ String ] { return [ "fake" ] }
    
    func describeEntityWithTableName(_ table: String) throws -> Entity? {
      return model[entityGroup: table].first
    }
  }
}
