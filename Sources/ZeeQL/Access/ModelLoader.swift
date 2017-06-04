//
//  ModelLoader.swift
//  ZeeQL3
//
//  Created by Helge Hess on 04/06/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//

import Foundation

open class ModelLoader {
  
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
  
  // MARK: - XML Parsing
  
  open func loadDataModelContents(from xml: XMLDocument) throws -> Model {
    guard let root = xml.rootElement(), root.name == "model" else {
      throw Error.InvalidFileFormat
    }
    
    var entities = [ Entity ]()
    
    // scan for entities
    for element in root.childElementsWithName("entity") {
      if let entity = loadEntity(from: element) {
        entities.append(entity)
      }
    }
    
    for _ in root.childElementsWithName("fetchRequest") {
      // TODO: process fetch specs (attached to entities)
    }
    
    for _ in root.childElementsWithName("configurations") {
      // TODO: process configurations (@name + <memberEntity name="entity"/>)
    }
    
    let model = Model(entities: entities)
    return model
  }
  
  func loadEntity(from xml: XMLElement) -> Entity? {
    assert(xml.name == "entity")
    
    let attrs = xml.attributesAsDict
    guard let name = attrs["name"] ?? attrs["representedClassName"]
     else { return nil }
    
    let entity = ModelEntity(name: name)
    
    if let v = attrs["representedClassName"] { entity.className          = v }
    if let v = attrs["codeGenerationType"]   { entity.codeGenerationType = v }
    
    if let s = attrs["syncable"], s == "NO" || s == "false" || s == "0" {
      entity.isSyncable = false
    }
    else {
      entity.isSyncable = true
    }
    
    // support 'externalName' in userdata
    var ud = loadUserInfo(from: xml.firstChildElementWithName("userInfo"))
    if let extName = ud.removeValue(forKey: "externalName"), !extName.isEmpty {
      entity.externalName = extName
    }
    
    for attribute in xml.childElementsWithName("attribute") {
      guard let attr = loadAttribute(from: attribute) else { continue }
      entity.attributes.append(attr)
    }
    
    for _ in xml.childElementsWithName("relationship") {
      // TODO: load relships
    }
    
    return entity
  }
  
  func loadAttribute(from xml: XMLElement) -> Attribute? {
    //     <attribute name="city"   optional="YES" attributeType="String" syncable="YES"/>
    
    return nil
  }
  
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
