# gai - Gleam AI SDK

A unified, purely functional library for making LLM requests through a standard interface.

## Overview

`gai` is a Gleam library for interacting with LLM APIs (OpenAI, Anthropic, Google Gemini, etc.). It constructs `gleam/http.Request` values and parses `gleam/http.Response` values - the actual HTTP transport is left to the caller. This makes it purely functional, testable, and compatible with both Erlang and JavaScript targets.

## Design Decisions & Justifications

### 1. Build from First Principles (No LLM Package Dependencies)

**Decision:** Do not depend on any existing LLM packages in the Gleam or BEAM ecosystem (e.g., `gllm`, `llmgleam`, `anthropic_gleam`).

**Justification:**
- Full control over request/response format - easy to adapt when APIs change
- No hidden behaviour - understand exactly what's being sent
- More scalable and easier to change in the future
- Existing packages are incomplete, Erlang-only, or tightly coupled to specific HTTP clients

**Only dependencies:**
- `gleam_stdlib` - Core language utilities
- `gleam_http` - Standard HTTP Request/Response types
- `gleam_json` - JSON encoding/decoding
- `sextant` - JSON Schema library (local, at `../sextant`)

### 2. Module Structure is Public API

**Decision:** Flat module structure with types defined in their primary module.

**Justification:** In Gleam:
- Every module in `src/` is public - there's no way to hide internal modules
- Types cannot be re-exported from other modules
- Users must import types from their defining module

Therefore, module structure directly determines the user-facing API. We use a flat structure:
```
gai.gleam           → Core types (Message, Content, Role, etc.)
gai/request.gleam   → CompletionRequest type + builders
gai/response.gleam  → CompletionResponse type + helpers
gai/openai.gleam    → OpenAI provider
```

Users import what they need:
```gleam
import gai.{Message, User, Text}
import gai/request
import gai/openai
```

### 3. Provider Config as Opaque Type

**Decision:** Each provider has an opaque `Config` type with builder functions.

**Justification:**
- Providers need multiple config options: API key, base URL, org ID, custom headers
- Opaque type allows internal changes without breaking API
- Pipeable construction is idiomatic Gleam:
  ```gleam
  let config = openai.new(api_key)
    |> openai.with_base_url(proxy_url)
    |> openai.with_organization(org_id)
  ```

### 4. Provider Type for Framework Use

**Decision:** Include a `Provider` type that bundles `build_request`, `parse_response`, and `parse_stream_chunk` functions.

**Justification:** The user plans to build an agent framework on top of `gai` that:
- Handles tool call loops
- Has pluggable runtimes for JS vs Erlang concurrency
- Needs to work with any provider polymorphically

Without a `Provider` type, the framework would need to know which provider module to call. With it:
```gleam
// Framework can be provider-agnostic
pub fn run_agent(provider: Provider, runtime: Runtime, ...) {
  let http_req = provider.build_request(req)
  let http_resp = runtime.send(http_req)
  provider.parse_response(http_resp)
  // ... tool loop logic
}
```

### 5. Both Direct Functions and Provider Constructor

**Decision:** Each provider module exports both direct functions AND a `provider()` constructor.

**Justification:** Supports two use cases:
- **Simple use:** Call provider functions directly
  ```gleam
  let http_req = openai.build_request(config, req)
  let result = openai.parse_response(http_resp)
  ```
- **Framework use:** Get a bundled Provider
  ```gleam
  let provider = openai.provider(config)
  agent.run(provider, runtime, req)
  ```

### 6. Sextant for Tool Schemas and Structured Output

**Decision:** Use Sextant (`../sextant`) for JSON Schema generation and validation.

**Justification:**
- Sextant provides type-safe JSON Schema generation
- Same schema can generate JSON Schema for the API AND validate/decode responses
- Already built for this exact use case (see Sextant README examples)
- Maintains type safety through the tool call flow

### 7. Transport Agnostic

**Decision:** Only construct Request values and parse Response values. No HTTP calls.

**Justification:**
- Works with any HTTP client (`gleam_httpc` on Erlang, `gleam_fetch` on JS, or custom)
- Purely functional - easy to test with mock requests/responses
- No FFI required
- User has full control over timeouts, retries, connection pooling, etc.

---

## Module Structure

```
src/
├── gai.gleam                 # Core types: Message, Content, Role, Usage, StopReason, etc.
├── gai/
│   ├── request.gleam         # CompletionRequest type + builders
│   ├── response.gleam        # CompletionResponse type + helpers
│   ├── tool.gleam            # Tool, ToolCall types + Sextant integration
│   ├── provider.gleam        # Provider type (for framework use)
│   ├── streaming.gleam       # StreamDelta type + SSE parsing
│   ├── error.gleam           # Error types
│   ├── openai.gleam          # OpenAI provider (+ OpenRouter, xAI, Mistral, etc.)
│   ├── anthropic.gleam       # Anthropic provider
│   └── google.gleam          # Google Gemini provider
```

---

## Core Types

### gai.gleam - Message Types

```gleam
/// Message role
pub type Role {
  System
  User
  Assistant
}

/// Content block within a message
pub type Content {
  Text(text: String)
  Image(source: ImageSource)
  Document(source: DocumentSource, media_type: String)
  ToolUse(id: String, name: String, arguments: Dynamic)
  ToolResult(tool_use_id: String, content: List(Content))
}

pub type ImageSource {
  ImageBase64(data: String, media_type: String)
  ImageUrl(url: String)
}

pub type DocumentSource {
  DocumentBase64(data: String)
  DocumentUrl(url: String)
}

/// A message in a conversation
pub type Message {
  Message(role: Role, content: List(Content))
}

/// Why the model stopped generating
pub type StopReason {
  EndTurn
  MaxTokens
  StopSequence
  ToolUse
}

/// Token usage information
pub type Usage {
  Usage(input_tokens: Int, output_tokens: Int)
}

// Convenience constructors
pub fn system(text: String) -> Message
pub fn user(content: List(Content)) -> Message
pub fn user_text(text: String) -> Message
pub fn assistant(content: List(Content)) -> Message
pub fn text(t: String) -> Content
pub fn image_url(url: String) -> Content
pub fn image_base64(data: String, media_type: String) -> Content
```

### gai/request.gleam - Completion Request

```gleam
import gai.{type Message}
import gai/tool.{type Tool, type ToolChoice}

/// Response format options
pub type ResponseFormat {
  TextFormat
  JsonFormat
  JsonSchemaFormat(schema: json.Json, name: String, strict: Bool)
}

/// Completion request configuration
pub type CompletionRequest {
  CompletionRequest(
    model: String,
    messages: List(Message),
    max_tokens: Option(Int),
    temperature: Option(Float),
    top_p: Option(Float),
    stop: Option(List(String)),
    tools: Option(List(Tool)),
    tool_choice: Option(ToolChoice),
    response_format: Option(ResponseFormat),
  )
}

// Builder functions
pub fn new(model: String, messages: List(Message)) -> CompletionRequest
pub fn with_max_tokens(req: CompletionRequest, n: Int) -> CompletionRequest
pub fn with_temperature(req: CompletionRequest, t: Float) -> CompletionRequest
pub fn with_tools(req: CompletionRequest, tools: List(Tool)) -> CompletionRequest
pub fn with_tool_choice(req: CompletionRequest, choice: ToolChoice) -> CompletionRequest
pub fn with_response_format(req: CompletionRequest, format: ResponseFormat) -> CompletionRequest
```

### gai/response.gleam - Completion Response

```gleam
import gai.{type Content, type StopReason, type Usage}

/// Completion response from the model
pub type CompletionResponse {
  CompletionResponse(
    id: String,
    model: String,
    content: List(Content),
    stop_reason: StopReason,
    usage: Usage,
  )
}

// Helper functions
pub fn text_content(resp: CompletionResponse) -> String
pub fn tool_calls(resp: CompletionResponse) -> List(ToolUse)
pub fn has_tool_calls(resp: CompletionResponse) -> Bool
```

### gai/tool.gleam - Tool Definitions

```gleam
import sextant

/// Tool choice options
pub type ToolChoice {
  Auto
  None
  Required
  Specific(name: String)
}

/// A tool call from the model (parsed from response)
pub type ToolUse {
  ToolUse(id: String, name: String, arguments: Dynamic)
}

/// Tool definition with Sextant schema
/// The phantom type `a` represents the decoded arguments type
pub opaque type Tool(a) {
  Tool(
    name: String,
    description: String,
    schema: sextant.JsonSchema(a),
  )
}

/// Create a tool definition
pub fn new(
  name: String,
  description: String,
  parameters: sextant.JsonSchema(a),
) -> Tool(a)

/// Get the JSON Schema for a tool (for sending to API)
pub fn to_json_schema(tool: Tool(a)) -> json.Json

/// Parse tool call arguments using the tool's schema
pub fn parse_arguments(tool: Tool(a), arguments: Dynamic) -> Result(a, List(sextant.ValidationError))

/// Erase the type parameter for storage in lists
pub fn to_untyped(tool: Tool(a)) -> UntypedTool

pub opaque type UntypedTool {
  UntypedTool(name: String, description: String, schema_json: json.Json)
}
```

### gai/provider.gleam - Provider Abstraction

```gleam
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gai/request.{type CompletionRequest}
import gai/response.{type CompletionResponse}
import gai/streaming.{type StreamDelta}
import gai/error.{type Error}

/// A provider bundles request building and response parsing.
/// Use this for building frameworks/abstractions over multiple providers.
pub type Provider {
  Provider(
    /// Provider name (e.g., "openai", "anthropic")
    name: String,
    /// Build an HTTP request from a completion request
    build_request: fn(CompletionRequest) -> Request(String),
    /// Parse an HTTP response into a completion response
    parse_response: fn(Response(String)) -> Result(CompletionResponse, Error),
    /// Parse a streaming chunk (SSE data line)
    parse_stream_chunk: fn(String) -> Result(StreamDelta, Error),
  )
}

/// Get the provider name
pub fn name(provider: Provider) -> String

/// Build an HTTP request using the provider
pub fn build_request(provider: Provider, req: CompletionRequest) -> Request(String)

/// Parse an HTTP response using the provider
pub fn parse_response(provider: Provider, resp: Response(String)) -> Result(CompletionResponse, Error)

/// Parse a streaming chunk using the provider
pub fn parse_stream_chunk(provider: Provider, chunk: String) -> Result(StreamDelta, Error)
```

### gai/streaming.gleam - Streaming Support

```gleam
import gai.{type Content, type StopReason, type Usage}

/// A delta from a streaming response
pub type StreamDelta {
  /// Incremental content
  ContentDelta(content: Content)
  /// Stream finished
  Done(stop_reason: StopReason, usage: Option(Usage))
  /// Keep-alive / empty event
  Ping
}

/// Parse raw SSE text into individual event strings
pub fn parse_sse(raw: String) -> List(String)

/// Accumulate deltas into a final response
pub type Accumulator

pub fn new_accumulator() -> Accumulator
pub fn accumulate(acc: Accumulator, delta: StreamDelta) -> Accumulator
pub fn finish(acc: Accumulator) -> Result(CompletionResponse, Error)
```

### gai/error.gleam - Error Types

```gleam
/// Errors that can occur when working with LLM APIs
pub type Error {
  /// HTTP-level error (connection failed, timeout, etc.)
  HttpError(status: Int, body: String)
  /// JSON parsing error
  JsonError(message: String)
  /// API returned an error response
  ApiError(code: String, message: String)
  /// Response didn't match expected format
  ParseError(message: String)
  /// Rate limited
  RateLimited(retry_after: Option(Int))
  /// Authentication failed
  AuthError(message: String)
}

pub fn to_string(error: Error) -> String
```

---

## Provider Modules

Each provider module exports both direct functions and a `Provider` constructor.

### gai/openai.gleam

```gleam
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gai/provider.{type Provider}
import gai/request.{type CompletionRequest}
import gai/response.{type CompletionResponse}
import gai/error.{type Error}

/// OpenAI configuration
pub opaque type Config {
  Config(
    api_key: String,
    base_url: String,
    organization: Option(String),
  )
}

/// Create a new OpenAI config
pub fn new(api_key: String) -> Config

/// Use a custom base URL (for proxies, Azure, etc.)
pub fn with_base_url(config: Config, url: String) -> Config

/// Set organization ID
pub fn with_organization(config: Config, org: String) -> Config

// Direct functions (simple use)
pub fn build_request(config: Config, req: CompletionRequest) -> Request(String)
pub fn parse_response(resp: Response(String)) -> Result(CompletionResponse, Error)
pub fn parse_stream_chunk(chunk: String) -> Result(StreamDelta, Error)

// Provider constructor (framework use)
pub fn provider(config: Config) -> Provider

// Convenience constructors for OpenAI-compatible providers
pub fn openrouter(api_key: String) -> Config  // base_url = "https://openrouter.ai/api/v1"
pub fn xai(api_key: String) -> Config         // base_url = "https://api.x.ai/v1"
pub fn mistral(api_key: String) -> Config     // base_url = "https://api.mistral.ai/v1"
pub fn groq(api_key: String) -> Config        // base_url = "https://api.groq.com/openai/v1"
pub fn together(api_key: String) -> Config    // base_url = "https://api.together.xyz/v1"
```

### gai/anthropic.gleam

```gleam
pub opaque type Config {
  Config(
    api_key: String,
    base_url: String,
    anthropic_version: String,
  )
}

pub fn new(api_key: String) -> Config
pub fn with_base_url(config: Config, url: String) -> Config
pub fn with_version(config: Config, version: String) -> Config

pub fn build_request(config: Config, req: CompletionRequest) -> Request(String)
pub fn parse_response(resp: Response(String)) -> Result(CompletionResponse, Error)
pub fn parse_stream_chunk(chunk: String) -> Result(StreamDelta, Error)
pub fn provider(config: Config) -> Provider
```

### gai/google.gleam

```gleam
pub opaque type Config {
  Config(
    api_key: String,
    base_url: String,
  )
}

pub fn new(api_key: String) -> Config
pub fn with_base_url(config: Config, url: String) -> Config

pub fn build_request(config: Config, req: CompletionRequest) -> Request(String)
pub fn parse_response(resp: Response(String)) -> Result(CompletionResponse, Error)
pub fn parse_stream_chunk(chunk: String) -> Result(StreamDelta, Error)
pub fn provider(config: Config) -> Provider
```

---

## Usage Examples

### Simple Use (Direct Functions)

```gleam
import gai
import gai/request
import gai/openai
import gleam/httpc  // or gleam/fetch on JS

pub fn main() {
  let config = openai.new("sk-...")

  let req = request.new("gpt-4o", [
    gai.system("You are a helpful assistant."),
    gai.user_text("What is 2 + 2?"),
  ])
  |> request.with_max_tokens(100)

  let http_req = openai.build_request(config, req)

  // Send with your HTTP client
  let assert Ok(http_resp) = httpc.send(http_req)

  // Parse response
  let assert Ok(completion) = openai.parse_response(http_resp)

  io.println(response.text_content(completion))
}
```

### Framework Use (Provider Type)

```gleam
import gai/provider.{type Provider}
import gai/request.{type CompletionRequest}
import gai/response.{type CompletionResponse}
import gai/openai
import gai/anthropic

/// Generic function that works with any provider
pub fn call_llm(
  provider: Provider,
  req: CompletionRequest,
  send: fn(Request(String)) -> Result(Response(String), HttpError),
) -> Result(CompletionResponse, Error) {
  let http_req = provider.build_request(req)
  use http_resp <- result.try(send(http_req) |> result.map_error(to_gai_error))
  provider.parse_response(http_resp)
}

// Use with different providers
let openai_provider = openai.new("sk-...") |> openai.provider
let anthropic_provider = anthropic.new("sk-...") |> anthropic.provider

call_llm(openai_provider, req, httpc.send)
call_llm(anthropic_provider, req, httpc.send)
```

### Tool Calling with Sextant

```gleam
import gai
import gai/request
import gai/tool
import sextant

// Define parameter types
type WeatherParams {
  WeatherParams(location: String, unit: Option(Unit))
}

type Unit { Celsius Fahrenheit }

// Create schema with Sextant
fn weather_schema() -> sextant.JsonSchema(WeatherParams) {
  use location <- sextant.field("location",
    sextant.string() |> sextant.describe("City name"))
  use unit <- sextant.optional_field("unit",
    sextant.enum(#("celsius", Celsius), [#("fahrenheit", Fahrenheit)]))
  sextant.success(WeatherParams(location:, unit:))
}

// Create tool
let weather_tool = tool.new(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: weather_schema(),
)

// Use in request
let req = request.new("gpt-4o", messages)
  |> request.with_tools([tool.to_untyped(weather_tool)])
  |> request.with_tool_choice(tool.Auto)

// Later, parse the tool call
case response.tool_calls(completion) {
  [tool_use, ..] -> {
    let assert Ok(params) = tool.parse_arguments(weather_tool, tool_use.arguments)
    // params is now WeatherParams
  }
  [] -> // No tool calls
}
```

### Structured Output

```gleam
import sextant

type Sentiment { Positive Negative Neutral }
type Analysis {
  Analysis(sentiment: Sentiment, confidence: Float, keywords: List(String))
}

fn analysis_schema() -> sextant.JsonSchema(Analysis) {
  use sentiment <- sextant.field("sentiment",
    sextant.enum(#("positive", Positive), [#("negative", Negative), #("neutral", Neutral)]))
  use confidence <- sextant.field("confidence",
    sextant.number() |> sextant.float_min(0.0) |> sextant.float_max(1.0))
  use keywords <- sextant.field("keywords",
    sextant.array(of: sextant.string()) |> sextant.max_items(5))
  sextant.success(Analysis(sentiment:, confidence:, keywords:))
}

let req = request.new("gpt-4o", [
  gai.user_text("Analyse: I love this product!"),
])
|> request.with_response_format(
  request.JsonSchemaFormat(
    schema: sextant.to_json(analysis_schema()),
    name: "sentiment_analysis",
    strict: True,
  )
)
```

---

## Dependencies

```toml
[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
gleam_http = ">= 4.3.0 and < 5.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
sextant = { path = "../sextant" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
gleam_httpc = ">= 5.0.0 and < 6.0.0"
```

---

## Implementation Phases

### Phase 1: Core Types
- [ ] `gai.gleam` - Message, Content, Role, etc.
- [ ] `gai/request.gleam` - CompletionRequest + builders
- [ ] `gai/response.gleam` - CompletionResponse + helpers
- [ ] `gai/error.gleam` - Error types
- [ ] `gai/provider.gleam` - Provider type

### Phase 2: OpenAI Provider
- [ ] `gai/openai.gleam` - Config, build_request, parse_response
- [ ] Request JSON encoding
- [ ] Response JSON decoding
- [ ] Unit tests with mock data

### Phase 3: Tool Calling
- [ ] `gai/tool.gleam` - Tool, ToolChoice, Sextant integration
- [ ] Tool schema generation
- [ ] Tool call parsing
- [ ] Tests

### Phase 4: Anthropic Provider
- [ ] `gai/anthropic.gleam` - Full implementation
- [ ] Handle Anthropic-specific format (system message, content blocks)
- [ ] Tests

### Phase 5: Google Gemini Provider
- [ ] `gai/google.gleam` - Full implementation
- [ ] Handle Gemini-specific format
- [ ] Tests

### Phase 6: Streaming
- [ ] `gai/streaming.gleam` - SSE parsing, accumulator
- [ ] Provider-specific stream chunk parsing
- [ ] Tests

### Phase 7: Advanced Features
- [ ] Image/document content types
- [ ] OpenAI-compatible provider variants (OpenRouter, etc.)
- [ ] Integration tests
- [ ] Documentation

---

## Provider API Differences

This table summarises key differences between providers that the implementation must handle:

| Feature | OpenAI | Anthropic | Google Gemini |
|---------|--------|-----------|---------------|
| Base URL | `api.openai.com/v1` | `api.anthropic.com/v1` | `generativelanguage.googleapis.com/v1beta` |
| Auth | `Authorization: Bearer {key}` | `x-api-key: {key}` | `?key={key}` query param |
| Extra headers | `OpenAI-Organization` (optional) | `anthropic-version: 2023-06-01` (required) | None |
| Endpoint | `/chat/completions` | `/messages` | `/models/{model}:generateContent` |
| System message | In messages array with `role: "system"` | Separate top-level `system` field | `systemInstruction` field |
| Content format | `content: string` or `content: [{type, ...}]` | `content: [{type, ...}]` always | `parts: [{...}]` |
| Tool schema key | `parameters` | `input_schema` | `parameters` |
| Tool call in response | `tool_calls: [{id, function: {name, arguments}}]` | `content: [{type: "tool_use", id, name, input}]` | `functionCall: {name, args}` |
| Stop reason field | `finish_reason` | `stop_reason` | `finishReason` |
| Stop reason values | `stop`, `length`, `tool_calls` | `end_turn`, `max_tokens`, `tool_use` | `STOP`, `MAX_TOKENS`, etc. |
| Streaming format | SSE with `data: {...}` | SSE with `event:` + `data:` | Different chunked format |
| Usage in response | `usage: {prompt_tokens, completion_tokens}` | `usage: {input_tokens, output_tokens}` | `usageMetadata: {promptTokenCount, candidatesTokenCount}` |

---

## Sextant Integration Notes

Sextant is a JSON Schema library located at `../sextant`. Key APIs:

```gleam
// Define a schema
fn my_schema() -> sextant.JsonSchema(MyType) {
  use field1 <- sextant.field("field1", sextant.string())
  use field2 <- sextant.optional_field("field2", sextant.integer())
  sextant.success(MyType(field1:, field2:))
}

// Generate JSON Schema (for sending to LLM API)
sextant.to_json(my_schema())  // -> json.Json

// Validate/decode dynamic data (for parsing LLM response)
sextant.run(dynamic_data, my_schema())  // -> Result(MyType, List(ValidationError))
```

For tools:
1. User defines schema with Sextant
2. `tool.new()` stores the schema
3. `tool.to_json_schema()` calls `sextant.to_json()` for the API request
4. `tool.parse_arguments()` calls `sextant.run()` to decode the response

---

## Future: Agent Framework

The `Provider` type enables building an agent framework on top of `gai`:

```gleam
// Hypothetical future agent package
import gai/provider.{type Provider}

pub type Runtime {
  Runtime(
    send: fn(Request(String)) -> Result(Response(String), Error),
    // ... concurrency primitives for JS vs Erlang
  )
}

pub fn run(
  provider: Provider,
  runtime: Runtime,
  messages: List(Message),
  tools: List(Tool),
  tool_executor: fn(ToolUse) -> Content,
) -> Result(CompletionResponse, Error) {
  // Tool loop implementation
}
```

This separation keeps `gai` focused on request/response transformation while enabling higher-level abstractions.

---

## Gleam Resources

- Full Gleam syntax: https://tour.gleam.run/everything
- gleam_http docs: https://hexdocs.pm/gleam_http/
- gleam_json docs: https://hexdocs.pm/gleam_json/
- Sextant: local at `../sextant`, see `../sextant/README.md` and `../sextant/src/sextant.gleam`
