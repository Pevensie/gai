# Agent, Tool Loop & Runtime - Design Proposal v2

> Updated based on Isaac's feedback: tools should carry their own executor, use coerce/identity for existential pattern.

## Overview

This document proposes the design for the three missing pieces in `gai`:
1. **Agent** - Bundles provider, system prompt, and tools
2. **Tool Loop** - Orchestrates LLM calls with automatic tool execution  
3. **Runtime** - Abstracts HTTP transport for Erlang vs JavaScript

---

## 1. Existential Tools Pattern

Instead of separating tool definitions from executors (requiring pattern matching on tool names), tools carry their own execution function. Type safety is preserved at definition time, then erased for storage using coerce.

### The Coerce Pattern

```gleam
// src/gai/internal/coerce.gleam

/// Coerce a value to a different type. This is safe because:
/// - Erlang/BEAM doesn't have runtime type checking
/// - JavaScript doesn't have runtime type checking  
/// The Gleam compiler sees a type change, but at runtime it's a no-op.
@external(erlang, "gleam@function", "identity")
@external(javascript, "../gleam_stdlib/gleam/function", "identity")
pub fn unsafe_coerce(value: a) -> b
```


### Tool Type with Embedded Executor

```gleam
// src/gai/tool.gleam

import gleam/dynamic.{type Dynamic}
import gleam/json.{type Json}
import gai/internal/coerce

/// Error from tool execution
pub type Error {
  ParseError(message: String)
  ExecutionError(message: String)
}

/// Result of tool execution
pub type ToolResult {
  ToolResult(tool_use_id: String, content: Result(String, String))
}

/// A tool call from the LLM response
pub type Call {
  Call(id: String, name: String, arguments_json: String)
}

/// A tool with embedded executor. The `args` type parameter represents
/// the parsed arguments type, but is erased to Dynamic for storage.
pub opaque type Tool(ctx, args) {
  Tool(
    name: String,
    description: String,
    schema_json: Json,
    /// Parses JSON args internally and executes
    run: fn(ctx, args) -> Result(String, ToolError),
  )
}

pub ToolArgs

/// Create a new tool with typed schema and executor.
/// The type parameter is captured in the closure, then erased for storage.
pub fn new(
  name name: String,
  description description: String,
  schema schema: sextant.JsonSchema(args),
  execute execute: fn(ctx, args) -> Result(String, ToolError),
) -> Tool(ctx, ToolArgs) {
  Tool(
    name:,
    description:,
    schema_json: sextant.to_json(schema),
    run: fn(ctx, args_json) {
      case json.parse(args_json, sextant.decoder(schema)) {
        Ok(args) -> execute(ctx, args)
        Error(e) -> Error(ParseError(json.decode_error_to_string(e)))
      }
    },
  )
  |> coerce.unsafe_coerce
}

/// Get the tool name
pub fn name(tool: Tool(ctx, args)) -> String {
  tool.name
}

/// Get the tool description  
pub fn description(tool: Tool(ctx, args)) -> String {
  tool.description
}

/// Get the JSON schema for sending to the LLM API
pub fn schema_json(tool: Tool(ctx, args)) -> Json {
  tool.schema_json
}

/// Execute the tool with the given context and JSON arguments
pub fn run(
  tool: Tool(ctx, args),
  ctx: ctx,
  arguments_json: String,
) -> Result(String, ToolError) {
  tool.run(ctx, arguments_json)
}

/// Execute a tool call, returning a ToolResult
pub fn execute_call(
  tool: Tool(ctx, args),
  ctx: ctx,
  call: ToolCall,
) -> ToolResult {
  case tool.run(ctx, call.arguments_json) {
    Ok(content) -> ToolResult(call.id, Ok(content))
    Error(e) -> ToolResult(call.id, Error(tool_error_to_string(e)))
  }
}

fn describe_error(error: ToolError) -> String {
  case error {
    ParseError(msg) -> "Parse error: " <> msg
    ExecutionError(msg) -> "Execution error: " <> msg
  }
}
```

---

## 2. Agent Type

```gleam
// src/gai/agent.gleam

import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option, None, Some}
import gai.{type Message}
import gai/provider.{type Provider}
import gai/tool.{type Tool}

/// Agent configuration
pub opaque type Agent(ctx) {
  Agent(
    provider: Provider,
    system_prompt: Option(String),
    tools: List(Tool(ctx, Dynamic)),
    max_tokens: Option(Int),
    temperature: Option(Float),
    max_iterations: Int,
  )
}

/// Create a new agent with a provider
pub fn new(provider: Provider) -> Agent(ctx) {
  Agent(
    provider:,
    system_prompt: None,
    tools: [],
    max_tokens: None,
    temperature: None,
    max_iterations: 10,
  )
}

/// Set the system prompt
pub fn with_system_prompt(agent: Agent(ctx), prompt: String) -> Agent(ctx) {
  Agent(..agent, system_prompt: Some(prompt))
}

/// Add a tool to the agent
pub fn with_tool(agent: Agent(ctx), tool: Tool(ctx, Dynamic)) -> Agent(ctx) {
  Agent(..agent, tools: [tool, ..agent.tools])
}

/// Add multiple tools to the agent
pub fn with_tools(
  agent: Agent(ctx),
  tools: List(Tool(ctx, Dynamic)),
) -> Agent(ctx) {
  Agent(..agent, tools: list.append(tools, agent.tools))
}

/// Set max tokens for completions
pub fn with_max_tokens(agent: Agent(ctx), n: Int) -> Agent(ctx) {
  Agent(..agent, max_tokens: Some(n))
}

/// Set temperature for completions
pub fn with_temperature(agent: Agent(ctx), t: Float) -> Agent(ctx) {
  Agent(..agent, temperature: Some(t))
}

/// Set maximum tool loop iterations (safety limit)
pub fn with_max_iterations(agent: Agent(ctx), n: Int) -> Agent(ctx) {
  Agent(..agent, max_iterations: n)
}

/// Get the provider
pub fn provider(agent: Agent(ctx)) -> Provider {
  agent.provider
}

/// Get tools as a list
pub fn tools(agent: Agent(ctx)) -> List(Tool(ctx, Dynamic)) {
  agent.tools
}

/// Find a tool by name
pub fn find_tool(agent: Agent(ctx), name: String) -> Option(Tool(ctx, Dynamic)) {
  list.find(agent.tools, fn(t) { tool.name(t) == name })
  |> option.from_result
}
```

---

## 3. Runtime Type

```gleam
// src/gai/runtime.gleam

import gai.{type Error}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}

/// Runtime provides HTTP transport abstraction
pub type Runtime {
  Runtime(
    send: fn(Request(String)) -> Result(Response(String), Error),
  )
}

/// Create a runtime from a send function
pub fn new(
  send send: fn(Request(String)) -> Result(Response(String), Error),
) -> Runtime {
  Runtime(send:)
}

/// Send a request using the runtime
pub fn send(
  runtime: Runtime,
  request: Request(String),
) -> Result(Response(String), Error) {
  runtime.send(request)
}
```

### Erlang Runtime (gleam_httpc)

```gleam
// src/gai/runtime/httpc.gleam

import gai
import gai/runtime.{type Runtime}
import gleam/httpc

/// Create a runtime using gleam_httpc (Erlang target)
pub fn new() -> Runtime {
  runtime.new(send: fn(req) {
    httpc.send(req)
    |> result.map_error(fn(_) { 
      gai.HttpError(0, "HTTP request failed") 
    })
  })
}
```

### JavaScript Runtime (gleam_fetch)

```gleam
// src/gai/runtime/fetch.gleam

// Note: gleam_fetch returns Promise, needs different handling
// Option 1: Callback-based API
// Option 2: Return gleam_javascript Promise type
// Option 3: Synchronous wrapper (if possible)

// TBD - needs more design work for async JS
```

---

## 4. Tool Loop

```gleam
// src/gai/agent/loop.gleam

import gai.{type Error, type Message}
import gai/agent.{type Agent}
import gai/provider
import gai/request
import gai/response.{type CompletionResponse}
import gai/runtime.{type Runtime}
import gai/tool.{type ToolCall, type ToolResult}
import gleam/list
import gleam/option.{None, Some}
import gleam/result

/// Result of running the agent
pub type RunResult {
  RunResult(
    response: CompletionResponse,
    messages: List(Message),
    iterations: Int,
  )
}

/// Run the agent with automatic tool loop
pub fn run(
  agent: Agent(ctx),
  ctx: ctx,
  messages: List(Message),
  runtime: Runtime,
) -> Result(RunResult, Error) {
  // Prepend system prompt if set
  let messages = case agent.system_prompt {
    None -> messages
    Some(prompt) -> [gai.system(prompt), ..messages]
  }
  
  run_loop(agent, ctx, messages, runtime, 0)
}

fn run_loop(
  agent: Agent(ctx),
  ctx: ctx,
  messages: List(Message),
  runtime: Runtime,
  iteration: Int,
) -> Result(RunResult, Error) {
  // Check iteration limit
  case iteration >= agent.max_iterations {
    True -> Error(gai.ApiError(
      "max_iterations",
      "Tool loop exceeded maximum iterations",
    ))
    False -> {
      // Build request
      let req = build_request(agent, messages)
      
      // Send via runtime
      use http_req <- result.try(Ok(provider.build_request(agent.provider, req)))
      use http_resp <- result.try(runtime.send(runtime, http_req))
      use completion <- result.try(provider.parse_response(agent.provider, http_resp))
      
      // Check for tool calls
      case response.has_tool_calls(completion) {
        False -> {
          // No tools, we're done
          let final_messages = response.append_response(messages, completion)
          Ok(RunResult(
            response: completion,
            messages: final_messages,
            iterations: iteration + 1,
          ))
        }
        True -> {
          // Execute tools
          let tool_calls = extract_tool_calls(completion)
          let results = execute_tools(agent, ctx, tool_calls)
          
          // Append assistant response and tool results to history
          let messages = response.append_response(messages, completion)
          let messages = append_tool_results(messages, results)
          
          // Continue loop
          run_loop(agent, ctx, messages, runtime, iteration + 1)
        }
      }
    }
  }
}

fn build_request(agent: Agent(ctx), messages: List(Message)) -> request.CompletionRequest {
  let tools_json = list.map(agent.tools, tool.schema_json)
  
  request.new(provider.name(agent.provider), messages)
  |> fn(req) {
    case agent.max_tokens {
      None -> req
      Some(n) -> request.with_max_tokens(req, n)
    }
  }
  |> fn(req) {
    case agent.temperature {
      None -> req
      Some(t) -> request.with_temperature(req, t)
    }
  }
  |> fn(req) {
    case agent.tools {
      [] -> req
      _ -> request.with_tools(req, tools_json)
    }
  }
}

fn extract_tool_calls(resp: CompletionResponse) -> List(ToolCall) {
  response.tool_calls(resp)
  |> list.filter_map(fn(content) {
    case content {
      gai.ToolUse(id, name, args_json) -> 
        Ok(tool.ToolCall(id:, name:, arguments_json: args_json))
      _ -> Error(Nil)
    }
  })
}

fn execute_tools(
  agent: Agent(ctx),
  ctx: ctx,
  calls: List(ToolCall),
) -> List(ToolResult) {
  list.map(calls, fn(call) {
    case agent.find_tool(agent, call.name) {
      None -> tool.ToolResult(call.id, Error("Unknown tool: " <> call.name))
      Some(t) -> tool.execute_call(t, ctx, call)
    }
  })
}

fn append_tool_results(
  messages: List(Message),
  results: List(ToolResult),
) -> List(Message) {
  let content = list.map(results, fn(r) {
    case r.content {
      Ok(text) -> gai.tool_result(r.tool_use_id, text)
      Error(err) -> gai.tool_result_error(r.tool_use_id, err)
    }
  })
  list.append(messages, [gai.Message(gai.User, content, None)])
}
```

---

## 5. Complete Usage Example

```gleam
import gai
import gai/agent
import gai/agent/loop
import gai/anthropic
import gai/runtime/httpc
import gai/tool
import gleam/io
import gleam/option.{None, Some}
import sextant

// ----- Define tool argument types -----

type WeatherArgs {
  WeatherArgs(location: String, unit: option.Option(String))
}

type SearchArgs {
  SearchArgs(query: String, limit: option.Option(Int))
}

// ----- Define schemas -----

fn weather_schema() -> sextant.JsonSchema(WeatherArgs) {
  use location <- sextant.field("location", sextant.string())
  use unit <- sextant.optional_field("unit", sextant.string())
  sextant.success(WeatherArgs(location:, unit:))
}

fn search_schema() -> sextant.JsonSchema(SearchArgs) {
  use query <- sextant.field("query", sextant.string())
  use limit <- sextant.optional_field("limit", sextant.int())
  sextant.success(SearchArgs(query:, limit:))
}

// ----- Define context -----

type Context {
  Context(
    weather_api_key: String,
    search_api_key: String,
  )
}

// ----- Create tools with embedded executors -----

fn weather_tool() -> tool.Tool(Context, Dynamic) {
  tool.new(
    name: "get_weather",
    description: "Get current weather for a location",
    schema: weather_schema(),
    execute: fn(ctx, args) {
      // Type-safe! args is WeatherArgs here
      let unit = option.unwrap(args.unit, "celsius")
      
      // Call weather API (simplified)
      let weather = fetch_weather(ctx.weather_api_key, args.location, unit)
      
      Ok("Weather in " <> args.location <> ": " <> weather)
    },
  )
}

fn search_tool() -> tool.Tool(Context, Dynamic) {
  tool.new(
    name: "web_search",
    description: "Search the web for information",
    schema: search_schema(),
    execute: fn(ctx, args) {
      // Type-safe! args is SearchArgs here
      let limit = option.unwrap(args.limit, 5)
      
      // Call search API (simplified)
      let results = do_search(ctx.search_api_key, args.query, limit)
      
      Ok(results)
    },
  )
}

// ----- Main -----

pub fn main() {
  // Setup
  let api_key = "sk-ant-..."
  let config = anthropic.new(api_key)
  let provider = anthropic.provider(config)
  let runtime = httpc.new()
  
  let ctx = Context(
    weather_api_key: "weather-key",
    search_api_key: "search-key",
  )
  
  // Create agent with tools
  let my_agent = agent.new(provider)
    |> agent.with_system_prompt("You are a helpful assistant with access to weather and search tools.")
    |> agent.with_tool(weather_tool())
    |> agent.with_tool(search_tool())
    |> agent.with_max_iterations(5)
  
  // Run conversation
  let messages = [
    gai.user_text("What's the weather like in Madrid? Also search for good tapas restaurants there."),
  ]
  
  case loop.run(my_agent, ctx, messages, runtime) {
    Ok(result) -> {
      io.println("Final response:")
      io.println(response.text_content(result.response))
      io.println("")
      io.println("Iterations: " <> int.to_string(result.iterations))
    }
    Error(err) -> {
      io.println("Error: " <> gai.error_to_string(err))
    }
  }
}
```

---

## 6. Benefits of This Design

| Aspect | Old Design (UntypedTool) | New Design (Coerce) |
|--------|-------------------------|---------------------|
| Type safety at definition | ✅ | ✅ |
| Type safety at execution | ❌ Pattern match | ✅ Closure captures type |
| Tool storage | UntypedTool wrapper | Direct coerce |
| Executor location | Separate function | Embedded in tool |
| Boilerplate | High (match all tools) | Low (just define tool) |
| Adding new tool | Edit executor + add to list | Just add to agent |
| Cross-target | ✅ | ✅ (coerce + identity) |

---

## 7. Implementation Plan

### Phase 1: Core Types
- [ ] `src/gai_ffi.erl` - Erlang coerce function
- [ ] `src/gai/internal/coerce.gleam` - Coerce wrapper
- [ ] Update `src/gai/tool.gleam` - New tool type with embedded executor
- [ ] `src/gai/agent.gleam` - Agent type + builders

### Phase 2: Runtime
- [ ] `src/gai/runtime.gleam` - Runtime type
- [ ] `src/gai/runtime/httpc.gleam` - Erlang runtime

### Phase 3: Tool Loop  
- [ ] `src/gai/agent/loop.gleam` - Tool loop implementation
- [ ] Tests with mock provider/runtime

### Phase 4: JavaScript Support
- [ ] `src/gai/runtime/fetch.gleam` - JS runtime (async design TBD)
- [ ] Integration tests on JS target

### Phase 5: Polish
- [ ] Remove old UntypedTool (or deprecate)
- [ ] Documentation
- [ ] Examples
- [ ] Consider streaming support

---

## 8. Open Questions

1. **Should we keep UntypedTool for backwards compatibility?**
   - Option: Deprecate but keep for a version
   - Option: Remove entirely

2. **JavaScript async handling?**
   - The tool loop is synchronous, but JS fetch is async
   - Need to design async-friendly API or use different pattern

3. **Streaming in tool loop?**
   - Current design is request/response
   - Streaming + tool calls is complex (tool calls come at end)

4. **Context type - generic or fixed?**
   - Current: `Agent(ctx)` is generic
   - Alternative: Use `Dynamic` for ctx too, let user coerce
