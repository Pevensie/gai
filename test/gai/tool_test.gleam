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
    tool.new(
      "get_weather",
      "Get current weather for a location",
      weather_schema(),
    )

  let assert "get_weather" = tool.name(t)
  let assert "Get current weather for a location" = tool.description(t)
  Nil
}

pub fn to_json_schema_test() -> Nil {
  let weather_tool = tool.new("get_weather", "Get weather", weather_schema())

  let json_schema = tool.to_json_schema(weather_tool)
  let json_str = json.to_string(json_schema)

  // Should contain the field definitions
  assert string.contains(json_str, "location")
  assert string.contains(json_str, "City name")
  assert string.contains(json_str, "unit")
  assert string.contains(json_str, "celsius")
  assert string.contains(json_str, "fahrenheit")
  Nil
}

pub fn parse_arguments_success_test() -> Nil {
  let weather_tool = tool.new("get_weather", "Get weather", weather_schema())

  let args_json = "{\"location\":\"London\",\"unit\":\"celsius\"}"

  let assert Ok(WeatherParams(location: "London", unit: Some(Celsius))) =
    tool.parse_arguments(weather_tool, args_json)
  Nil
}

pub fn parse_arguments_optional_missing_test() -> Nil {
  let weather_tool = tool.new("get_weather", "Get weather", weather_schema())

  let args_json = "{\"location\":\"Paris\"}"

  let assert Ok(WeatherParams(location: "Paris", unit: None)) =
    tool.parse_arguments(weather_tool, args_json)
  Nil
}

pub fn parse_arguments_invalid_test() -> Nil {
  let weather_tool = tool.new("get_weather", "Get weather", weather_schema())

  // Missing required field
  let args_json = "{}"

  let assert Error(_errors) = tool.parse_arguments(weather_tool, args_json)
  Nil
}

// UntypedTool tests

pub fn to_untyped_test() -> Nil {
  let weather_tool = tool.new("get_weather", "Get weather", weather_schema())

  let untyped = tool.to_untyped(weather_tool)

  let assert "get_weather" = tool.untyped_name(untyped)
  let assert "Get weather" = tool.untyped_description(untyped)

  // JSON schema should still be valid
  let schema_json = tool.untyped_schema(untyped)
  let json_str = json.to_string(schema_json)
  assert string.contains(json_str, "location")
  Nil
}
