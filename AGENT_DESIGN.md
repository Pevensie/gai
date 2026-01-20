# Agent & Tool Loop

High-level API for agentic LLM workflows with automatic tool execution.

## Overview

```
┌─────────────────────────────────────┐
│  Agent                              │
│  - provider                         │
│  - system_prompt                    │
│  - tools (with executors)           │
│  - max_iterations                   │
├─────────────────────────────────────┤
│  Loop                               │
│  - Sends messages to LLM            │
│  - Executes tool calls              │
│  - Repeats until done               │
├─────────────────────────────────────┤
│  Runtime                            │
│  - HTTP transport abstraction       │
│  - Erlang: gleam_httpc              │
│  - JS: gleam_fetch (TBD)            │
└─────────────────────────────────────┘
```

## Tool Design

Tools carry their own executor. Type safety is preserved at definition via closures:

```gleam
let weather_tool = tool.tool(
  name: "get_weather",
  description: "Get weather for a location",
  schema: weather_schema(),
  execute: fn(ctx, args) {
    // args is WeatherArgs - fully typed!
    Ok("Sunny in " <> args.location)
  },
)
```

## Agent

Minimal config for agentic workflows:

```gleam
let my_agent = agent.new(provider)
  |> agent.with_system_prompt("You are helpful.")
  |> agent.with_tool(weather_tool)
  |> agent.with_max_iterations(5)
```

Request-level config (max_tokens, temperature) is passed via `run_with_config`:

```gleam
loop.run_with_config(agent, ctx, messages, runtime, Some(fn(req) {
  req
  |> request.with_max_tokens(1000)
  |> request.with_temperature(0.7)
}))
```

## Runtime

Abstracts HTTP transport:

```gleam
pub type Runtime {
  Runtime(send: fn(Request(String)) -> Result(Response(String), Error))
}
```

## Usage

```gleam
// 1. Create provider
let provider = openai.new("sk-...") |> openai.provider

// 2. Create tools
let search_tool = tool.tool(
  name: "search",
  description: "Search the web",
  schema: search_schema(),
  execute: fn(ctx, args) { do_search(ctx, args.query) },
)

// 3. Create agent
let my_agent = agent.new(provider)
  |> agent.with_system_prompt("You are a helpful assistant.")
  |> agent.with_tool(search_tool)

// 4. Run
let messages = [gai.user_text("Search for Gleam")]
case loop.run(my_agent, ctx, messages, runtime) {
  Ok(result) -> response.text_content(result.response)
  Error(err) -> gai.error_to_string(err)
}
```
