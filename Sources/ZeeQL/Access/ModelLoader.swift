//
//  ModelLoader.swift
//  ZeeQL3
//
//  Created by Helge Hess on 04/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation

open class ModelLoader {

  let log : ZeeQLLogger = globalZeeQLLogger
  
  public enum Error : Swift.Error {
    case CouldNotLoadFile(url: URL, error: Swift.Error?)
    case InvalidPath(String)
    case InvalidFileFormat
    
    case SubclassResponsibility
    
    case TODO(String)
  }
  
  public static func loadModel(from path: String) throws -> Model {
    guard !path.isEmpty     else { throw Error.InvalidPath(path) }
    
    let url = URL(fileURLWithPath: path)
    guard !url.path.isEmpty else { throw Error.InvalidPath(path) }
    
    return try loadModel(from: url)
  }
  
  public static func loadModel(from url: URL) throws -> Model {
    // peek at files/directories to load other model types
    let loader = CoreDataModelLoader()
    return try loader.loadModel(from: url)
  }
  
  
  // MARK: - Main Entrypoint
  
  open func loadModel(from url: URL) throws -> Model {
    throw Error.SubclassResponsibility
  }
  
}

fileprivate extension XMLElement {

  func firstChildElementWithName(_ name: String) -> XMLElement? {
    guard let children = children else { return nil }
    
    for child in children {
      guard let element = child as? XMLElement, let tag = element.name
       else { continue }
      
      if tag == name { return element }
    }
    return nil
  }
  
  func childElementsWithName(_ name: String) -> [ XMLElement ] {
    guard let children = children else { return [] }
    
    var matches = [ XMLElement ]()
    for child in children {
      guard let element = child as? XMLElement, let tag = element.name
        else { continue }
      
      if tag == name {
        matches.append(element)
      }
    }
    return matches
  }
  
  var attributesAsDict : [ String : String ] {
    guard let attributes = attributes else { return [:] }
    
    var map = [ String : String ]()
    for attr in attributes {
      guard let name = attr.localName ?? attr.name else { continue }
      guard let v = attr.stringValue else { continue }
      map[name] = v
    }
    return map
  }
  
}

fileprivate extension Bool { // Linux compat
  var boolValue : Bool { return self }
}

open class CoreDataModelLoader : ModelLoader {
  // An actual implementation for CoreData .xcdatamodeld/.xcdatamodel
  
  // TODO: optimize performance, naive implementation
  
  enum Style {
    /// Use the schema used by CD itself - with those nize Z_ / Z names :-)
    /// Also add the maintenance tables?
    case CoreDataDatabase
    
    /// Create a model which makes sense in ZeeQL setups
    /// - add 'id' primary key, auto-increment
    case ZeeQLDatabase
  }
  
  let style = Style.ZeeQLDatabase
  
  struct ToManyEntry {
    let entity        : Entity
    let relationship  : ModelRelationship
    let inverseName   : String
    let inverseEntity : String
  }
  var toManyRelationshipFixups = [ ToManyEntry ]()
  
  
  // MARK: - XML Parsing
  
  final func boolValue(_ v: Any?, default: Bool = false) -> Bool {
    guard let v = v else { return `default` }
    if let b = v as? Bool { return b }
    if let i = v as? Int  { return i != 0 }
    let s = ((v as? String) ?? String(describing: v)).lowercased()
    return s == "true" || s == "yes" || s == "1"
  }
  
  open func loadDataModelContents(from xml: XMLDocument) throws -> Model {
    guard let root = xml.rootElement(), root.name == "model" else {
      throw Error.InvalidFileFormat
    }

    toManyRelationshipFixups.removeAll()
    var entities = [ Entity ]()
    
    // scan for entities
    for element in root.childElementsWithName("entity") {
      if let entity = loadEntity(from: element) {
        entities.append(entity)
      }
    }
    
    let model = Model(entities: entities)
    
    for entry in toManyRelationshipFixups {
      guard let destEntity = model[entity: entry.inverseEntity]
       else {
        log.warn("did not find inverse entity of relationship:", entry)
        continue
       }
      entry.relationship.destinationEntity = destEntity // hook up, safe work
      
      guard let revRelship = destEntity[relationship: entry.inverseName]
       else {
        log.warn("did not find inverse of relationship:", entry,
                 "in", destEntity)
        continue
       }
      
      let inverseJoins = revRelship.joins.map { $0.inverse }
      entry.relationship.joins = inverseJoins
    }
    
    for node in root.childElementsWithName("fetchRequest") {
      _ = loadFetchSpecification(from: node, into: model)
    }
    
    for _ in root.childElementsWithName("configurations") {
      // TODO: process configurations (@name + <memberEntity name="entity"/>)
    }
    
    return model
  }

  @discardableResult
  func loadFetchSpecification(from xml: XMLElement, into model: Model)
       -> FetchSpecification?
  {
    // TODO: 
    // faulting stuff:
    // - returnObjectsAsFaults
    // - fetchBatchSize
    // Hierarchies:
    // - includeSubentities
    // State:
    // - includesPendingChanges
    
    assert(xml.name == "fetchRequest")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"], let entityName = attrs["entity"]
     else {
      log.warn("fetchspec has no name or entity:", xml)
      return nil
     }
    
    guard let entity = model[entity: entityName] as? ModelEntity
     else {
      log.warn("did not find entity of fetchspec:", entityName, xml)
      return nil
     }
    
    let q : Qualifier?
    if let qs = attrs["predicateString"] { q = qualifierWith(format: qs) }
    else                                 { q = nil                       }

    let limit : Int?
    if let l = attrs["fetchLimit"], !l.isEmpty { limit = Int(l) }
    else                                       { limit = nil    }
    
    let sos   : [ SortOrdering ]? = nil
    var fs = ModelFetchSpecification(entity: entity, qualifier: q,
                                     sortOrderings: sos, limit: limit)
    
    fs.usesDistinct = boolValue(attrs["returnDistinctResults"])
    
    if let fs = entity.fetchSpecifications[name] {
      log.warn("duplicate fetchspecs for name:", name, "in entity:", entity, fs)
    }
    
    entity.fetchSpecifications[name] = fs
    return fs
  }
  
  func loadEntity(from xml: XMLElement) -> Entity? {
    assert(xml.name == "entity")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"] ?? attrs["representedClassName"]
     else { return nil }
    
    let entity = ModelEntity(name: name)
    
    if let v = attrs["representedClassName"] { entity.className          = v }
    if let v = attrs["codeGenerationType"]   { entity.codeGenerationType = v }
    entity.isSyncable = boolValue(attrs["syncable"], default: true)
    
    // support 'externalName' in userdata
    var ud = loadUserInfo(from: xml.firstChildElementWithName("userInfo"))
    if let extName = ud.removeValue(forKey: "externalName"), !extName.isEmpty {
      entity.externalName = extName
    }
    
    var idAttribute : Attribute? = nil
    for attribute in xml.childElementsWithName("attribute") {
      guard let attr = loadAttribute(from: attribute) else { continue }
      entity.attributes.append(attr)
      if attr.name == "id" { idAttribute = attr }
    }
    
    var toManyRelships = [ ( ModelRelationship, XMLElement ) ]()
    for rs in xml.childElementsWithName("relationship") {
      guard let ( attr, relship ) = loadRelationship(from: rs, entity: entity)
         else { continue }
      
      if let attr = attr { entity.attributes.append(attr) }
      entity.relationships.append(relship)
      
      // remember for inverse processing
      if relship.isToMany { toManyRelships.append((relship, rs)) }
    }
    
    if style == .ZeeQLDatabase {
      // Add primary key, those are not usually configured in CoreData. Though
      // you can add an 'id' attribute and we consider that the primary
      if idAttribute == nil {
        let pkeyAttr = ModelAttribute(name: "id", allowsNull: false)
        pkeyAttr.isAutoIncrement = true // TBD. CD has a separate sequence
        
        entity.attributes.insert(pkeyAttr, at: 0)
        // TODO: adjust classProperties accordingly (w/o id to mirror CD)
      }
    }
    
    // TODO: scan toMany inverse relationships
    
    for ( toManyRS, node ) in toManyRelships {
      let attrs = node.attributesAsDict
      
      guard let iname = attrs["inverseName"], !iname.isEmpty
       else {
        log.warn("Consistency Error:", toManyRS.name, "relationship does not",
                 "have an inverse, this is an advanced setting")
        continue
       }
      
      let ient = attrs["inverseEntity"]
        ?? toManyRS.destinationEntityName
      let entry = ToManyEntry(entity: entity, relationship: toManyRS,
                              inverseName: iname,
                              inverseEntity: ient ?? "ERROR")
      toManyRelationshipFixups.append(entry)
    }
    
    return entity
  }
  
  func loadAttribute(from xml: XMLElement) -> Attribute? {
    // TODO: add support for minValueString/maxValueString
    // TODO: add support for 'indexed'
    assert(xml.name == "attribute")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"] else { return nil }
    
    // Note: we don't care about usesScalarValueType
    let attribute = ModelAttribute(name: name)
    let allowsNull       = boolValue(attrs["optional"])
    attribute.allowsNull = allowsNull
    attribute.isSyncable = boolValue(attrs["syncable"], default: true)
    
    if let attrType = attrs["attributeType"], !attrType.isEmpty {
      let lc = attrType.lowercased()
      
      if lc == "string" {
        attribute.valueType = allowsNull ? Optional<String>.self : String.self
      }
      else if lc.hasPrefix("int") { // funny, ?: doesn't work here
        if attrType.hasSuffix("16") {
          if allowsNull { attribute.valueType = Optional<Int16>.self }
          else          { attribute.valueType = Int16.self           }
        }
        else if attrType.hasSuffix("32") {
          if allowsNull { attribute.valueType = Optional<Int32>.self }
          else          { attribute.valueType = Int32.self           }
        }
        else if attrType.hasSuffix("64") {
          if allowsNull { attribute.valueType = Optional<Int64>.self }
          else          { attribute.valueType = Int64.self           }
        }
        else {
          if allowsNull { attribute.valueType = Optional<Int>.self }
          else          { attribute.valueType = Int.self           }
        }
      }
      else if lc == "date" {
        attribute.valueType = allowsNull ? Optional<Date>.self : Date.self
      }
      else if lc == "binary" || lc ==  "data" {
        attribute.valueType = allowsNull ? Optional<Data>.self : Data.self
      }
      else if lc == "decimal" {
        // TODO: 'usesScalarValueType=YES'
        if allowsNull { attribute.valueType = Optional<Decimal>.self }
        else          { attribute.valueType = Decimal.self           }
      }
      else if lc.hasPrefix("bool") {
        attribute.valueType = allowsNull ? Optional<Bool>.self : Bool.self
      }
      else if lc.hasPrefix("transformable") {
        // valueTransformerName="xx"
        // customClassName="xx"
        log.warn("unsupported attr type in CoreData model: ", attrType)
      }
      else {
        log.warn("unsupported attr type in CoreData model: ", attrType)
      }
    }
    
    return attribute
  }
  
  func loadRelationship(from xml: XMLElement, entity: Entity)
       -> ( Attribute?, ModelRelationship )?
  {
    // TODO: Add support for 'maxCount', 'ordered=YES/NO'
    
    assert(xml.name == "relationship")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"] else { return nil }
    
    let relship = ModelRelationship(name: name, source: entity)
    relship.isSyncable = boolValue(attrs["syncable"], default: true)
    relship.isToMany   = boolValue(attrs["toMany"])
    
    if let de = attrs["destinationEntity"], !de.isEmpty {
      relship.destinationEntityName = de
    }
    
    if let delrule = attrs["deletionRule"], !delrule.isEmpty {
      // nullify
      let lc = delrule.lowercased()
      
      if      lc.hasPrefix("null")    { relship.deleteRule = .nullify      }
      else if lc.hasPrefix("cascade") { relship.deleteRule = .cascade      }
      else if lc.hasPrefix("deny")    { relship.deleteRule = .deny         }
      else if lc.hasPrefix("no")      { relship.deleteRule = .noAction     }
      else if lc.hasSuffix("default") { relship.deleteRule = .applyDefault }
      else { log.warn("unsupported CoreData delete rule:", lc) }
    }
    
    let attributeOpt : Attribute?
    if relship.isToMany {
      attributeOpt = nil // the fkey lives in the reverse, we do that later
    }
    else {
      // 'person' => 'personId'
      let attributeName = name + foreignKeyRelationshipSuffix
      
      let attribute = ModelAttribute(name: attributeName)
      
      let allowsNull       = boolValue(attrs["optional"])
      attribute.allowsNull = allowsNull
      attribute.isSyncable = relship.isSyncable // TBD: only store in one?
      
      relship.joins = [ Join(source      : attributeName,
                             destination : primaryKeyAttributeName) ]
      attributeOpt = attribute
    }
    
    return ( attributeOpt, relship )
  }
  
  let primaryKeyAttributeName      = "id"
  let foreignKeyRelationshipSuffix = "Id"
  
  func loadUserInfo(from xml: XMLElement?) -> [ String : String ] {
    guard let xml = xml else { return [:] }
    
    var userInfo = [ String : String ]()
    
    for element in xml.childElementsWithName("entry") {
      let attrs = element.attributesAsDict
      guard let name  = attrs["name"], !name.isEmpty else { continue }
      guard let value = attrs["value"]               else { continue }
      
      // TBD: could be arrays?
      userInfo[name] = value
    }
    
    return userInfo
  }
  
  
  
  // MARK: - File System Lookup

  let fm = FileManager.default
  
  override open func loadModel(from url: URL) throws -> Model {
    /*
     - abc.xcdatamodeld/
       - .xccurrentversion // proplist
       - abc.xcdatamodel/
         - contents
     */
    var isDirectory : ObjCBool = false
    if !fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      throw Error.CouldNotLoadFile(url:url, error: nil) // wrap
    }
    
    // it is a file
    if !isDirectory.boolValue {
      return try loadDataModelContents(from: url)
    }
    
    // it is a directory

    let contentsURL = url.appendingPathComponent("contents", isDirectory: false)
    if fm.fileExists(atPath: contentsURL.path) {
      return try loadDataModel(from: url)
    }
    
    let contents : [ String ]
    do {
      contents = try fm.contentsOfDirectory(atPath: url.path)
    }
    catch {
      throw Error.CouldNotLoadFile(url:url, error: error) // wrap
    }
    
    let hasDataModel = contents.contains { $0.hasSuffix(".xcdatamodel") }
    guard hasDataModel else {
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    
    return try loadDataModelDirectory(from: url)
  }
  
  open func loadDataModelDirectory(from url: URL) throws -> Model {
    // presumably this can have multiple
    let contents : [ String ]
    do {
      contents = try fm.contentsOfDirectory(atPath: url.path)
    }
    catch {
      throw Error.CouldNotLoadFile(url:url, error: error) // wrap
    }
    
    let dataModels = contents.filter { $0.hasSuffix(".xcdatamodel") }
    guard !dataModels.isEmpty else {
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    
    var fullModel : Model? = nil
    for filename in dataModels {
      let dmURL = url.appendingPathComponent(filename)
      let model = try loadDataModel(from: dmURL)
      
      if let container = fullModel {
        container.merge(model)
      }
      else {
        if model.tag != nil {
          fullModel = Model(entities: [])
          fullModel!.merge(model)
        }
        else {
          fullModel = model
        }
      }
    }
    
    guard let result = fullModel else {
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    
    result.connectRelationships()
    return result
  }
  
  open func loadDataModel(from url: URL) throws -> Model {
    var isDirectory : ObjCBool = false
    if !fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      throw Error.CouldNotLoadFile(url:url, error: nil) // wrap
    }

    // it is a file
    if !isDirectory.boolValue {
      return try loadDataModelContents(from: url)
    }
    
    let contentsURL = url.appendingPathComponent("contents", isDirectory: false)
    guard fm.fileExists(atPath: contentsURL.path) else {
      throw Error.CouldNotLoadFile(url:url, error: nil)
    }
    
    return try loadDataModelContents(from: contentsURL)
  }

  open func loadDataModelContents(from url: URL) throws -> Model {
    #if os(Linux) // TBD: is this rather Swift 3.1+?
      let options = XMLNode.Options(rawValue: 0)
    #else // Swift 3.0.2 on 10.11
      let options = 0
    #endif
    
    let xml : XMLDocument
    do {
      xml = try XMLDocument(contentsOf: url, options: options)
    }
    catch {
      throw Error.CouldNotLoadFile(url:url, error: error) // wrap
    }
    
    let model = try loadDataModelContents(from: xml)
    model.connectRelationships()
    return model
  }
}
