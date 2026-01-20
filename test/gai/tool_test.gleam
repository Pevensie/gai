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

  let assert "get_weather" = tool.name(t)
  let assert "Get current weather for a location" = tool.description(t)
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

  let json_schema = tool.schema(weather_tool)
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

  assert Ok("Weather in London: 20 celsius")
    == tool.execute(weather_tool, TestCtx, args_json)
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

  assert Ok("Weather in Paris: default")
    == tool.execute(weather_tool, TestCtx, args_json)
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

  assert Error(tool.ParseError("Validation failed: missing field 'location'"))
    == tool.execute(weather_tool, TestCtx, args_json)
}

// ToolSchema tests

pub fn execute_with_complex_args_test() -> Nil {
  // This test proves args can be any type, not just String
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, args: WeatherParams) {
        // args.unit is Option(Unit), not String!
        let unit_name = case args.unit {
          Some(Celsius) -> "°C"
          Some(Fahrenheit) -> "°F"
          None -> "°C"
        }
        // args.location is String
        Ok(args.location <> ": 20" <> unit_name)
      },
    )

  // Test with enum value - this would fail if args was String
  assert Ok("Tokyo: 20°F")
    == tool.execute(
      weather_tool,
      TestCtx,
      "{\"location\":\"Tokyo\",\"unit\":\"fahrenheit\"}",
    )
}

pub fn to_schema_test() -> Nil {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestCtx, _args: WeatherParams) { Ok("ok") },
    )

  let assert tool.Schema("get_weather", "Get weather", schema) =
    tool.to_schema(weather_tool)

  // JSON schema should still be valid
  assert "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"required\":[\"location\"],\"type\":\"object\",\"properties\":{\"location\":{\"description\":\"City name\",\"type\":\"string\"},\"unit\":{\"type\":\"string\",\"enum\":[\"celsius\",\"fahrenheit\"]}},\"additionalProperties\":false}"
    == json.to_string(schema)
}
