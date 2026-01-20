import gai/agent
import gai/anthropic
import gai/tool
import gleam/option
import sextant

// Test argument types
type WeatherArgs {
  WeatherArgs(location: String, unit: option.Option(Unit))
}

type Unit {
  Celsius
  Fahrenheit
}

type SearchArgs {
  SearchArgs(query: String)
}

// Test context type
type TestContext

fn weather_schema() {
  use location <- sextant.field("location", sextant.string())
  use unit <- sextant.optional_field(
    "unit",
    sextant.enum(#("celsius", Celsius), [#("fahrenheit", Fahrenheit)]),
  )
  sextant.success(WeatherArgs(location:, unit:))
}

fn search_schema() {
  use query <- sextant.field("query", sextant.string())
  sextant.success(SearchArgs(query:))
}

pub fn agent_creation_test() {
  let config = anthropic.new("test-key")
  let provider = anthropic.provider(config)

  let my_agent =
    agent.new(provider)
    |> agent.with_system_prompt("You are helpful")
    |> agent.with_max_iterations(5)

  let assert option.Some("You are helpful") = agent.system_prompt(my_agent)
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
  let assert option.Some(tool) = agent.find_tool(my_agent, "get_weather")
  assert "get_weather" == tool.name(tool)
  assert "Get weather" == tool.description(tool)

  assert option.None == agent.find_tool(my_agent, "nonexistent")
}
