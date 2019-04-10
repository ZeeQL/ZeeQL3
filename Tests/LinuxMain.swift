import XCTest

@testable import ZeeQLTests

let tests = [
  testCase(FormatterTests.allTests),
  testCase(QualifierParserTests.allTests),
  testCase(SQLExpressionTests.allTests),
  
  testCase(ModelTests.allTests),
  
  testCase(ModelLoaderTests.allTests),

  testCase(SchemaGenerationTests.allTests),
  testCase(SchemaSyncTests.allTests),
  
  testCase(CodeEntityModelTests.allTests),
  testCase(CodeObjectModelTests.allTests),
  
  testCase(CodableModelTests.allTests),

  testCase(SQLite3ActiveRecordTests.allTests),
  testCase(SQLite3AdaptorTests.allTests),
  testCase(SQLite3ExpressionTests.allTests),
  testCase(SQLite3ModelTests.allTests),
  testCase(SQLite3OGoAdaptorTests.allTests),
  testCase(SQLite3CodableTests.allTests),
]

XCTMain(tests)
