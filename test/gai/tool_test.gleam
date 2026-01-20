import gai/tool
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import sextant

// Test type for tool parameters
type WeatherParams {
  WeatherParams(location: String, unit: option.Option(Unit))
}

type Unit {
  Celsius
  Fahrenheit
}

// Test context
type TestCtx {
  TestCtx
}

fn weather_schema() -> sextant.JsonSchema(WeatherParams) {
  use location <- sextant.field(
    "location",
    sextant.string() |> sextant.describe("City name"),
  )
  use unit <- sextant.optional_field(
    "unit",
    sextant.enum(#("celsius", Celsius), [#("fahrenheit", Fahrenheit)]),
  )
  sextant.success(WeatherParams(location:, unit:))
}

// Tool creation tests

pub fn new_tool_test() -> Nil {
  let t =
    tool.tool(
      name: "get_weather",
      description: "Get current weather for a location",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, _args) { Ok("sunny") },
    )

  let assert "get_weather" = tool.tool_name(t)
  let assert "Get current weather for a location" = tool.tool_description(t)
  Nil
}

pub fn tool_schema_test() -> Nil {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, _args) { Ok("sunny") },
    )

  let json_schema = tool.tool_schema(weather_tool)
  let json_str = json.to_string(json_schema)

  // Should contain the field definitions
  assert string.contains(json_str, "location")
  assert string.contains(json_str, "City name")
  assert string.contains(json_str, "unit")
  assert string.contains(json_str, "celsius")
  assert string.contains(json_str, "fahrenheit")
  Nil
}

pub fn execute_success_test() -> Nil {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, args: WeatherParams) {
        let unit_str = case args.unit {
          Some(Celsius) -> "celsius"
          Some(Fahrenheit) -> "fahrenheit"
          None -> "celsius"
        }
        Ok("Weather in " <> args.location <> ": 20 " <> unit_str)
      },
    )

  let args_json = "{\"location\":\"London\",\"unit\":\"celsius\"}"

  let assert Ok("Weather in London: 20 celsius") =
    tool.execute(weather_tool, TestCtx, args_json)
  Nil
}

pub fn execute_optional_missing_test() -> Nil {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, args: WeatherParams) {
        let unit_str = case args.unit {
          Some(Celsius) -> "celsius"
          Some(Fahrenheit) -> "fahrenheit"
          None -> "default"
        }
        Ok("Weather in " <> args.location <> ": " <> unit_str)
      },
    )

  let args_json = "{\"location\":\"Paris\"}"

  let assert Ok("Weather in Paris: default") =
    tool.execute(weather_tool, TestCtx, args_json)
  Nil
}

pub fn execute_invalid_test() -> Nil {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, _args: WeatherParams) { Ok("ok") },
    )

  // Missing required field
  let args_json = "{}"

  let assert Error(_) = tool.execute(weather_tool, TestCtx, args_json)
  Nil
}

// ToolSchema tests

pub fn to_schema_test() -> Nil {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, _args: WeatherParams) { Ok("ok") },
    )

  let schema = tool.to_schema(weather_tool)

  let assert "get_weather" = schema.name
  let assert "Get weather" = schema.description

  // JSON schema should still be valid
  let json_str = json.to_string(schema.schema)
  assert string.contains(json_str, "location")
  Nil
}
