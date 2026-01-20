import gai/agent
import gai/anthropic
import gai/tool
import gleam/option
import sextant

// Test argument types
type WeatherArgs {
  WeatherArgs(location: String, unit: option.Option(String))
}

type SearchArgs {
  SearchArgs(query: String)
}

// Test context type
type TestContext {
  TestContext(api_key: String)
}

fn weather_schema() {
  use location <- sextant.field("location", sextant.string())
  use unit <- sextant.optional_field("unit", sextant.string())
  sextant.success(WeatherArgs(location:, unit:))
}

fn search_schema() {
  use query <- sextant.field("query", sextant.string())
  sextant.success(SearchArgs(query:))
}

pub fn tool_creation_test() {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather for a location",
      schema: weather_schema(),
      execute: fn(_ctx: TestContext, args: WeatherArgs) {
        Ok("Weather in " <> args.location <> ": sunny")
      },
    )

  let assert "get_weather" = tool.tool_name(weather_tool)
  let assert "Get weather for a location" = tool.tool_description(weather_tool)
  Nil
}

pub fn tool_execution_test() {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather for a location",
      schema: weather_schema(),
      execute: fn(_ctx: TestContext, args: WeatherArgs) {
        let unit = option.unwrap(args.unit, "celsius")
        Ok("Weather in " <> args.location <> ": 20" <> unit)
      },
    )

  let ctx = TestContext(api_key: "test-key")

  // Test with valid JSON
  let assert Ok("Weather in Madrid: 20celsius") =
    tool.execute(weather_tool, ctx, "{\"location\": \"Madrid\"}")

  // Test with unit specified
  let assert Ok("Weather in London: 20fahrenheit") =
    tool.execute(
      weather_tool,
      ctx,
      "{\"location\": \"London\", \"unit\": \"fahrenheit\"}",
    )
  Nil
}

pub fn tool_parse_error_test() {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather for a location",
      schema: weather_schema(),
      execute: fn(_ctx: TestContext, _args: WeatherArgs) { Ok("ok") },
    )

  let ctx = TestContext(api_key: "test-key")

  // Test with invalid JSON
  let assert Error(_) = tool.execute(weather_tool, ctx, "not json")

  // Test with missing required field
  let assert Error(_) = tool.execute(weather_tool, ctx, "{}")
  Nil
}

pub fn agent_creation_test() {
  let config = anthropic.new("test-key")
  let provider = anthropic.provider(config)

  let my_agent =
    agent.new(provider)
    |> agent.with_system_prompt("You are helpful")
    |> agent.with_max_tokens(1000)
    |> agent.with_temperature(0.7)
    |> agent.with_max_iterations(5)

  let assert option.Some("You are helpful") = agent.system_prompt(my_agent)
  let assert option.Some(1000) = agent.max_tokens(my_agent)
  let assert 5 = agent.max_iterations(my_agent)
  let assert False = agent.has_tools(my_agent)
  Nil
}

pub fn agent_with_tools_test() {
  let config = anthropic.new("test-key")
  let provider = anthropic.provider(config)

  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather",
      schema: weather_schema(),
      execute: fn(_ctx: TestContext, args: WeatherArgs) {
        Ok("Weather in " <> args.location)
      },
    )

  let search_tool =
    tool.tool(
      name: "search",
      description: "Search web",
      schema: search_schema(),
      execute: fn(_ctx: TestContext, args: SearchArgs) {
        Ok("Results for: " <> args.query)
      },
    )

  let my_agent =
    agent.new(provider)
    |> agent.with_tool(weather_tool)
    |> agent.with_tool(search_tool)

  let assert True = agent.has_tools(my_agent)
  let assert 2 = agent.tool_count(my_agent)

  // Find tool by name
  let assert option.Some(_) = agent.find_tool(my_agent, "get_weather")
  let assert option.None = agent.find_tool(my_agent, "nonexistent")
  Nil
}

pub fn tool_call_result_test() {
  let call = tool.Call(id: "call_123", name: "test", arguments_json: "{}")

  let ok_result = tool.call_ok(call, "success!")
  let assert "call_123" = ok_result.tool_use_id
  let assert Ok("success!") = ok_result.content

  let err_result = tool.call_error(call, "failed!")
  let assert Error("failed!") = err_result.content
  Nil
}

pub fn tool_to_schema_test() {
  let weather_tool =
    tool.tool(
      name: "get_weather",
      description: "Get weather for a location",
      schema: weather_schema(),
      execute: fn(_ctx: TestContext, _args: WeatherArgs) { Ok("ok") },
    )

  let schema = tool.to_schema(weather_tool)

  let assert "get_weather" = schema.name
  let assert "Get weather for a location" = schema.description
  Nil
}
