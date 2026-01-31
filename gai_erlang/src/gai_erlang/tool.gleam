/// Tool definitions with embedded executors.
import gai
import gai/tool as gai_tool
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import sextant.{type JsonSchema}

/// An executable tool with embedded executor.
///
/// The `ctx` type parameter is the context passed to the executor.
pub opaque type Tool(ctx) {
  Tool(
    schema: gai_tool.ToolSchema,
    /// Parses JSON args internally and executes with context
    run: fn(ctx, String) -> Result(String, gai_tool.ExecutionError),
  )
}

/// Create a new executable tool with typed schema and executor.
pub fn new(
  name name: String,
  description description: String,
  schema schema: JsonSchema(args),
  execute execute: fn(ctx, args) -> Result(String, gai_tool.ExecutionError),
) -> Tool(ctx) {
  Tool(
    schema: gai_tool.ToolSchema(
      name:,
      description:,
      schema_json: sextant.to_json(schema),
    ),
    run: fn(ctx, args_json) {
      use dynamic <- result.try(
        json.parse(args_json, decode.dynamic)
        |> result.map_error(describe_json_decoding_error)
        |> result.map_error(gai_tool.ParseError),
      )
      use args <- result.try(
        sextant.run(dynamic, schema)
        |> result.map_error(describe_validation_errors)
        |> result.map_error(gai_tool.ParseError),
      )
      execute(ctx, args)
    },
  )
}

/// Get the tool schema.
pub fn schema(tool: Tool(ctx)) -> gai_tool.ToolSchema {
  tool.schema
}

/// Get the tool name.
pub fn name(tool: Tool(ctx)) -> String {
  tool.schema.name
}

/// Execute a tool call and return a ToolResult content block.
pub fn execute(
  tool: Tool(ctx),
  ctx: ctx,
  id: String,
  arguments_json: String,
) -> gai.Content {
  case tool.run(ctx, arguments_json) {
    Ok(output) -> gai.ToolResult(id, output, False)
    Error(err) -> gai.ToolResult(id, gai_tool.describe_error(err), True)
  }
}

fn describe_json_decoding_error(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "Unexpected end of input"
    json.UnexpectedByte(_) -> "Unexpected byte"
    json.UnexpectedSequence(_) -> "Unexpected sequence"
    json.UnableToDecode(errors) ->
      "Unable to decode JSON: "
      <> list.map(errors, describe_decode_error)
      |> string.join("; ")
  }
  |> string.append("JSON Decoding Failed: ", _)
}

fn describe_decode_error(error: decode.DecodeError) {
  case error {
    decode.DecodeError(expected:, found:, path:) ->
      string.join(path, ".") <> " expected " <> expected <> ", got " <> found
  }
}

fn describe_validation_errors(errors: List(sextant.ValidationError)) -> String {
  errors
  |> list.map(fn(e) {
    case e {
      sextant.TypeError(path:, expected:, found:) ->
        string.join(path, ".") <> " expected " <> expected <> ", got " <> found
      sextant.MissingField(path:, field:) ->
        string.join(path, ".") <> " missing field '" <> field <> "'"
      sextant.ConstraintError(path:, violation: _) ->
        string.join(path, ".") <> " constraint violation"
      sextant.UnknownVariant(path:, value:, expected:) ->
        string.join(path, ".")
        <> " unknown variant '"
        <> value
        <> "', expected one of "
        <> string.join(expected, ", ")
      sextant.ConstMismatch(path:, expected:, actual:) ->
        string.join(path, ".")
        <> " expected const '"
        <> expected
        <> "', got '"
        <> actual
        <> "'"
    }
  })
  |> string.join("; ")
  |> string.append("Validation failed:", _)
}
