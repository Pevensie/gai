# Agent & Tool Loop Design

High-level API for agentic LLM workflows with automatic tool execution.

## Architecture Overview

```
gai/src/                          # Shared, target-agnostic
├── gai.gleam                     # Core types: Message, Content, Error, etc.
└── gai/
    ├── provider.gleam            # Provider abstraction
    ├── anthropic.gleam           # Anthropic provider
    ├── openai.gleam              # OpenAI provider
    ├── google.gleam              # Google provider
    ├── request.gleam             # CompletionRequest builder
    ├── response.gleam            # CompletionResponse helpers
    ├── streaming.gleam           # SSE parsing, Accumulator
    ├── tool.gleam                # ToolSchema, ExecutionError
    └── agent.gleam               # StopCondition (shared)

gai_erlang/src/                   # Erlang runtime
├── gai_erlang.gleam
└── gai_erlang/
    ├── tool.gleam                # Tool(ctx) with sync executor
    ├── agent.gleam               # Agent(ctx) with send function
    └── loop.gleam                # Sync recursive loop

gai_javascript/src/               # JavaScript runtime
├── gai_javascript.gleam
└── gai_javascript/
    ├── tool.gleam                # Tool(ctx) with async executor
    ├── agent.gleam               # Agent(ctx) with fetch function
    └── loop.gleam                # Promise-based loop
```

### Why Separate Runtime Packages?

Tool execution differs fundamentally:

- **Erlang**: Sync functions, OTP tasks for parallelism
- **JavaScript**: Promises, `Promise.all` for parallelism

The loop also differs: tail-recursion (Erlang) vs promise chains (JavaScript).

Rather than abstract with complex effect types, we duplicate ~300 lines per runtime package. Shared code is ~2000+ lines.

---

## Shared Types (`gai/`)

### Core Types (`gai.gleam`)

```gleam
pub type Message {
  Message(role: Role, content: List(Content), cache_control: Option(CacheControl))
}

pub type Role { System  User  Assistant }

pub type Content {
  Text(text: String)
  Image(source: ImageSource)
  Document(source: DocumentSource, media_type: String)
  ToolCall(id: String, name: String, arguments_json: String)
  ToolResult(tool_use_id: String, output: String, is_error: Bool)
  Thinking(text: String)
}

pub type StopReason { EndTurn  MaxTokens  StopSequence  ToolUsed  ContentFilter }

pub type Error {
  HttpError(status: Int, body: String)
  JsonError(message: String)
  ApiError(code: String, message: String)
  ParseError(message: String)
  RateLimited(retry_after: Option(Int))
  AuthError(message: String)
}
```

### Tool Schema (`gai/tool.gleam`)

```gleam
pub type ToolSchema {
  ToolSchema(name: String, description: String, schema_json: Json)
}

pub type ExecutionError {
  ParseError(message: String)
  ToolError(message: String)
}
```

### Stop Condition (`gai/agent.gleam`)

```gleam
pub type StopCondition {
  MaxIterations(Int)
  HasToolCall(ToolSchema)
}
```

`HasToolCall` stops the loop when the specified tool is called. The tool is still executed before stopping. This supports "final answer" patterns where the agent signals completion via a specific tool.

---

## Runtime Packages

Both runtimes follow the same pattern. Key differences noted below.

### Tool

Tools have a typed executor that parses JSON arguments internally.

```gleam
pub opaque type Tool(ctx) {
  Tool(
    schema: ToolSchema,
    run: fn(ctx, String) -> Result(String, ExecutionError),  // Erlang
    // run: fn(ctx, String) -> Promise(Result(String, ExecutionError)),  // JavaScript
  )
}

pub fn new(
  name name: String,
  description description: String,
  schema schema: JsonSchema(a),
  execute execute: fn(ctx, a) -> Result(String, ExecutionError),
) -> Tool(ctx)

pub fn schema(tool: Tool(ctx)) -> ToolSchema
pub fn name(tool: Tool(ctx)) -> String

pub fn execute(tool: Tool(ctx), ctx: ctx, id: String, arguments_json: String) -> Content
```

JavaScript also provides `new_sync` for tools that don't need async.

### Agent

The Agent holds configuration including the HTTP send function. This enables testing with mocks and using custom HTTP clients.

```gleam
pub opaque type Agent(ctx) {
  Agent(
    provider: Provider,
    tools: List(Tool(ctx)),
    stop_conditions: List(StopCondition),
    max_tokens: Option(Int),
    temperature: Option(Float),
    send: fn(Request(String)) -> Result(Response(String), Error),  // Erlang
    // send: fn(Request(String)) -> Promise(Result(Response(String), Error)),  // JavaScript
  )
}

pub fn new(provider: Provider) -> Agent(ctx)
pub fn with_tool(agent: Agent(ctx), tool: Tool(ctx)) -> Agent(ctx)
pub fn with_tools(agent: Agent(ctx), tools: List(Tool(ctx))) -> Agent(ctx)
pub fn with_stop_condition(agent: Agent(ctx), condition: StopCondition) -> Agent(ctx)
pub fn with_max_iterations(agent: Agent(ctx), max: Int) -> Agent(ctx)
pub fn with_max_tokens(agent: Agent(ctx), max: Int) -> Agent(ctx)
pub fn with_temperature(agent: Agent(ctx), temp: Float) -> Agent(ctx)
pub fn with_send(agent: Agent(ctx), send: fn(...) -> ...) -> Agent(ctx)

/// Convenience helper to create a HasToolCall stop condition
pub fn stop_on_tool(tool: Tool(ctx)) -> StopCondition {
  gai_agent.HasToolCall(tool.schema(tool))
}
```

Default `send` uses `httpc` (Erlang) or `fetch` (JavaScript).

**No system prompt field**: Users pass a system message as the first message in the list.

### Loop

```gleam
pub type RunResult {
  RunResult(
    response: CompletionResponse,
    messages: List(Message),
    iterations: Int,
  )
}

pub type LoopError {
  LoopError(
    error: Error,
    messages: List(Message),
    iterations: Int,
  )
}

pub fn run(
  agent: Agent(ctx),
  ctx: ctx,
  messages: List(Message),
) -> Result(RunResult, LoopError)  // Erlang
// ) -> Promise(Result(RunResult, LoopError))  // JavaScript
```

The loop:
1. Check `MaxIterations` → stop if exceeded
2. Build request with agent's max_tokens/temperature
3. Send to LLM via agent's send function
4. If error → return `LoopError` with partial messages
5. If `stop_reason == ToolUsed` with tool calls:
   - Execute tools in parallel
   - Check `HasToolCall` conditions → if any matched, stop with results
   - Otherwise append results, goto 1
6. Otherwise stop (EndTurn, MaxTokens, ContentFilter, etc.)

**Parallel execution:**
- Erlang: OTP tasks with `task.async`/`task.await_forever`
- JavaScript: `promise.await_list` (wraps `Promise.all`)

---

## Stop Conditions

The loop continues only when **both** are true:
1. `stop_reason == ToolUsed`
2. Response contains tool calls
3. No `HasToolCall` condition matches the called tools

Otherwise it stops. This handles all stop reasons automatically:
- `EndTurn` / `StopSequence` → model is done → stop
- `MaxTokens` → truncated → stop
- `ContentFilter` → filtered → stop
- `ToolUsed` with calls → execute → check `HasToolCall` → continue or stop

`MaxIterations(Int)` prevents infinite loops. Checked before each LLM call. Default: 10.

`HasToolCall(ToolSchema)` stops the loop when the specified tool is called. The tool is executed first, then the loop stops. Useful for "final answer" tools.

---

## Example Usage

### Erlang

```gleam
import gai
import gai/anthropic
import gai_erlang/agent
import gai_erlang/loop
import gai_erlang/tool

pub fn main() {
  let provider = anthropic.new("sk-...")
    |> anthropic.with_model("claude-sonnet-4-20250514")
    |> anthropic.provider

  let weather_tool = tool.new(
    name: "get_weather",
    description: "Get weather for a location",
    schema: weather_args_schema(),
    execute: fn(ctx, args) {
      case fetch_weather(ctx.http, args.location) {
        Ok(w) -> Ok(w.temp <> " in " <> args.location)
        Error(e) -> Error(tool.ToolError(e))
      }
    },
  )

  let my_agent = agent.new(provider)
    |> agent.with_tool(weather_tool)
    |> agent.with_max_tokens(1024)

  let messages = [
    gai.system_text("You are a weather assistant."),
    gai.user_text("Weather in Tokyo?"),
  ]

  case loop.run(my_agent, ctx, messages) {
    Ok(result) -> io.println(response.text_content(result.response))
    Error(e) -> io.println(gai.error_to_string(e.error))
  }
}
```

### With HasToolCall Stop Condition

```gleam
let final_answer_tool = tool.new(
  name: "final_answer",
  description: "Provide the final answer to the user's question",
  schema: answer_schema(),
  execute: fn(_ctx, args) { Ok(args.answer) },
)

let my_agent = agent.new(provider)
  |> agent.with_tool(search_tool)
  |> agent.with_tool(final_answer_tool)
  |> agent.with_stop_condition(agent.stop_on_tool(final_answer_tool))
```

### JavaScript

Same API, but tools can be async and loop returns a Promise:

```gleam
let weather_tool = tool.new(
  name: "get_weather",
  description: "Get weather for a location",
  schema: weather_args_schema(),
  execute: fn(ctx, args) {
    fetch_weather_async(ctx, args.location)
    |> promise.map(fn(r) { result.map(r, fn(w) { w.temp }) })
  },
)

loop.run(my_agent, ctx, messages)
|> promise.map(fn(result) { ... })
```

### Testing with Mock Send

```gleam
let mock_send = fn(_req) {
  Ok(Response(200, [], "{...mock response...}"))
}

let test_agent = agent.new(provider)
  |> agent.with_send(mock_send)
```

### Handling Partial Results on Error

```gleam
case loop.run(my_agent, ctx, messages) {
  Ok(result) ->
    io.println("Success after " <> int.to_string(result.iterations) <> " iterations")
  Error(loop_error) -> {
    io.println("Failed after " <> int.to_string(loop_error.iterations) <> " iterations")
    io.println("Partial conversation has " <> int.to_string(list.length(loop_error.messages)) <> " messages")
    // Can inspect loop_error.messages for debugging or recovery
  }
}
```

---

## Context Parameter (`ctx`)

The `ctx` type parameter flows through `Tool(ctx)` and `Agent(ctx)`. It's user-defined and can hold whatever the application needs:

- Database connections
- HTTP clients
- User session data
- Configuration

The loop passes `ctx` to each tool execution unchanged.

---

## Required Refactoring

1. **`gai/tool.gleam`**: Keep only `ToolSchema`, `ExecutionError`. Move `Tool` to runtime packages.

2. **`gai/agent.gleam`**: Add `StopCondition` type with `MaxIterations` and `HasToolCall` variants.

3. **`gai/response.gleam`**: Add `append_response` helper.

4. **Delete**: `gai/agent/loop.gleam` - moves to runtime packages.

5. **`gai_erlang/`**: Implement tool, agent (with send field, stop_on_tool helper), loop (with LoopError).

6. **`gai_javascript/`**: Same, with Promise-based signatures. Add FFI for fetch.

**Dependencies:**

```toml
# gai_erlang/gleam.toml
[dependencies]
gai = { path = "../gai" }
gleam_httpc = ">= 3.0.0"
gleam_otp = ">= 0.16.0"

# gai_javascript/gleam.toml
[dependencies]
gai = { path = "../gai" }
gleam_javascript = ">= 0.14.0"
```

---

## Streaming (Future)

Deferred. Would need:
- Erlang: FFI to streaming HTTP client (hackney/gun), actor-based loop
- JavaScript: `response.body.getReader()`, async generator FFI

Existing `gai/streaming.gleam` (SSE parsing) would be reused.
