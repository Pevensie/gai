/// Structured output schemas with Sextant integration.
///
/// This module provides typed schema definitions for structured output generation.
/// Schemas use Sextant to generate JSON Schema for the API and parse responses
/// back into typed Gleam values.
///
/// ## Example
///
/// ```gleam
/// import gai/schema
/// import sextant
///
/// type Greeting {
///   Greeting(message: String)
/// }
///
/// // Define the schema
/// let greeting_schema = schema.new("greeting", {
///   use message <- sextant.field("message", sextant.string())
///   sextant.success(Greeting(message))
/// })
///
/// // Use in request
/// let req = request.new("gpt-4o", messages)
///   |> request.with_schema(greeting_schema)
///
/// // Parse the response
/// let assert Ok(greeting) = schema.parse(greeting_schema, response_text)
/// ```
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import sextant.{type JsonSchema, type ValidationError}

/// Schema definition with Sextant schema.
/// The phantom type `a` represents the decoded output type.
pub opaque type Schema(a) {
  Schema(name: String, schema: JsonSchema(a), strict: Bool)
}

/// Create a schema definition.
pub fn new(name: String, schema: JsonSchema(a)) -> Schema(a) {
  Schema(name:, schema:, strict: True)
}

/// Set whether strict mode is enabled (default: True).
/// When strict, the model must exactly follow the schema.
pub fn with_strict(schema: Schema(a), strict: Bool) -> Schema(a) {
  Schema(..schema, strict:)
}

/// Get the schema name
pub fn name(schema: Schema(a)) -> String {
  schema.name
}

/// Get whether strict mode is enabled
pub fn strict(schema: Schema(a)) -> Bool {
  schema.strict
}

/// Get the JSON Schema (for sending to API)
pub fn to_json_schema(schema: Schema(a)) -> Json {
  sextant.to_json(schema.schema)
}

/// Parse a JSON string response using the schema.
/// Use this to parse the text content from a completion response.
pub fn parse(
  schema: Schema(a),
  json_string: String,
) -> Result(a, List(ValidationError)) {
  case json.parse(json_string, decode.dynamic) {
    Ok(dynamic) -> parse_dynamic(schema, dynamic)
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

/// Parse a Dynamic value using the schema.
/// Useful when you already have parsed JSON.
pub fn parse_dynamic(
  schema: Schema(a),
  value: Dynamic,
) -> Result(a, List(ValidationError)) {
  sextant.run(value, schema.schema)
}
