/// Tool definitions with Sextant schema integration.
///
/// This module provides typed tool definitions that can generate JSON Schema
/// for the LLM API and parse tool call arguments back into typed Gleam values.
import gleam/dynamic/decode
import gleam/json.{type Json}
import sextant.{type JsonSchema}

/// Tool definition with Sextant schema.
/// The phantom type `a` represents the decoded arguments type.
pub opaque type Tool(a) {
  Tool(name: String, description: String, schema: JsonSchema(a))
}

/// Create a tool definition
pub fn new(
  name: String,
  description: String,
  parameters: JsonSchema(a),
) -> Tool(a) {
  Tool(name:, description:, schema: parameters)
}

/// Get the tool name
pub fn name(tool: Tool(a)) -> String {
  tool.name
}

/// Get the tool description
pub fn description(tool: Tool(a)) -> String {
  tool.description
}

/// Get the JSON Schema for a tool (for sending to API)
pub fn to_json_schema(tool: Tool(a)) -> Json {
  sextant.to_json(tool.schema)
}

/// Parse tool call arguments from a JSON string using the tool's schema
pub fn parse_arguments(
  tool: Tool(a),
  arguments_json: String,
) -> Result(a, List(sextant.ValidationError)) {
  case json.parse(arguments_json, decode.dynamic) {
    Ok(dynamic) -> sextant.run(dynamic, tool.schema)
    Error(_) ->
      Error([
        sextant.TypeError(
          path: [],
          expected: "valid JSON",
          found: "invalid JSON",
        ),
      ])
  }
}

/// An untyped tool for storage in lists (type erased)
pub opaque type UntypedTool {
  UntypedTool(name: String, description: String, schema_json: Json)
}

/// Erase the type parameter for storage in lists
pub fn to_untyped(tool: Tool(a)) -> UntypedTool {
  UntypedTool(
    name: tool.name,
    description: tool.description,
    schema_json: sextant.to_json(tool.schema),
  )
}

/// Get the name of an untyped tool
pub fn untyped_name(tool: UntypedTool) -> String {
  tool.name
}

/// Get the description of an untyped tool
pub fn untyped_description(tool: UntypedTool) -> String {
  tool.description
}

/// Get the JSON schema of an untyped tool
pub fn untyped_schema(tool: UntypedTool) -> Json {
  tool.schema_json
}
