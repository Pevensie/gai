import gai/tool
import gleam/json

pub fn tool_schema_fields_test() {
  let schema = json.object([#("type", json.string("object"))])
  let tool_schema =
    tool.ToolSchema(
      name: "get_weather",
      description: "Get weather",
      schema_json: schema,
    )

  assert tool_schema.name == "get_weather"
  assert tool_schema.description == "Get weather"
}

pub fn describe_error_test() {
  assert tool.describe_error(tool.ParseError("bad")) == "Parse error: bad"
  assert tool.describe_error(tool.ToolError("boom")) == "Execution error: boom"
}
