/// Anthropic provider implementation.
///
/// For Claude models via the Anthropic Messages API.
import gai
import gai/internal/decode as json_decode
import gai/provider
import gai/request as gai_request
import gai/response as gai_response
import gai/streaming
import gai/tool
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request as http_request
import gleam/http/response as http_response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri

// ============================================================================
// Config
// ============================================================================

/// Anthropic configuration (opaque type)
pub opaque type Config {
  Config(
    api_key: String,
    base_url: String,
    anthropic_version: String,
    thinking_budget: Int,
  )
}

/// Create a new Anthropic config
pub fn new(api_key: String) -> Config {
  Config(
    api_key:,
    base_url: "https://api.anthropic.com/v1",
    anthropic_version: "2023-06-01",
    thinking_budget: 0,
  )
}

/// Use a custom base URL (for proxies, etc.)
pub fn with_base_url(config: Config, url: String) -> Config {
  Config(..config, base_url: url)
}

/// Set API version
pub fn with_version(config: Config, version: String) -> Config {
  Config(..config, anthropic_version: version)
}

/// Enable extended thinking with a token budget.
/// When enabled, Claude will use interleaved thinking before responding.
/// Set budget_tokens to 0 to disable thinking (default).
pub fn with_thinking(config: Config, budget_tokens: Int) -> Config {
  Config(..config, thinking_budget: budget_tokens)
}

// ============================================================================
// Build Request
// ============================================================================

/// Build an HTTP request from a completion request
pub fn build_request(
  config: Config,
  req: gai_request.CompletionRequest,
) -> http_request.Request(String) {
  let assert Ok(base_uri) = uri.parse(config.base_url)
  let host = option.unwrap(base_uri.host, "api.anthropic.com")
  let base_path = case base_uri.path {
    "" -> "/v1"
    p -> p
  }
  let path = base_path <> "/messages"
  let scheme = case base_uri.scheme {
    Some("http") -> http.Http
    _ -> http.Https
  }

  let body = encode_request(req, config.thinking_budget)

  let request =
    http_request.new()
    |> http_request.set_method(http.Post)
    |> http_request.set_scheme(scheme)
    |> http_request.set_host(host)
    |> http_request.set_path(path)
    |> http_request.set_body(json.to_string(body))
    |> http_request.set_header("content-type", "application/json")
    |> http_request.set_header("x-api-key", config.api_key)
    |> http_request.set_header("anthropic-version", config.anthropic_version)

  let request = case base_uri.port {
    Some(port) -> http_request.set_port(request, port)
    None -> request
  }

  // Collect beta features that need headers
  let beta_features = []

  let beta_features = case req.response_format {
    Some(gai_request.JsonSchemaFormat(..)) -> [
      "structured-outputs-2025-11-13",
      ..beta_features
    ]
    _ -> beta_features
  }

  let beta_features = case config.thinking_budget > 0 {
    True -> ["interleaved-thinking-2025-05-14", ..beta_features]
    False -> beta_features
  }

  // Add beta header if any features enabled
  case beta_features {
    [] -> request
    features ->
      http_request.set_header(
        request,
        "anthropic-beta",
        string.join(features, ","),
      )
  }
}

fn encode_request(
  req: gai_request.CompletionRequest,
  thinking_budget: Int,
) -> json.Json {
  // Extract system message from messages list
  let #(system_info, non_system_messages) =
    json_decode.extract_system_message(req.messages)

  let fields = [
    #("model", json.string(req.model)),
    #("messages", json.array(non_system_messages, encode_message)),
  ]

  // Add system message as top-level field if present
  // For Anthropic, system with cache_control uses content blocks format
  let fields = case system_info {
    Some(json_decode.SystemMessage(text:, cache_control: Some(gai.Ephemeral))) -> [
      #(
        "system",
        json.array(
          [
            json.object([
              #("type", json.string("text")),
              #("text", json.string(text)),
              #(
                "cache_control",
                json.object([#("type", json.string("ephemeral"))]),
              ),
            ]),
          ],
          fn(x) { x },
        ),
      ),
      ..fields
    ]
    Some(json_decode.SystemMessage(text:, cache_control: None)) -> [
      #("system", json.string(text)),
      ..fields
    ]
    None -> fields
  }

  // Anthropic requires max_tokens
  let fields = case req.max_tokens {
    Some(n) -> [#("max_tokens", json.int(n)), ..fields]
    None -> [#("max_tokens", json.int(4096)), ..fields]
  }

  let fields = case req.temperature {
    Some(t) -> [#("temperature", json.float(t)), ..fields]
    None -> fields
  }

  let fields = case req.top_p {
    Some(p) -> [#("top_p", json.float(p)), ..fields]
    None -> fields
  }

  let fields = case req.stop {
    Some(sequences) -> [
      #("stop_sequences", json.array(sequences, json.string)),
      ..fields
    ]
    None -> fields
  }

  let fields = case req.tools {
    Some(tools) -> [#("tools", json.array(tools, encode_tool)), ..fields]
    None -> fields
  }

  let fields = case req.tool_choice {
    Some(choice) -> [#("tool_choice", encode_tool_choice(choice)), ..fields]
    None -> fields
  }

  // Structured output format
  let fields = case req.response_format {
    Some(gai_request.JsonSchemaFormat(schema:, ..)) -> [
      #(
        "output_format",
        json.object([
          #("type", json.string("json_schema")),
          #("schema", schema),
        ]),
      ),
      ..fields
    ]
    _ -> fields
  }

  // Extended thinking
  let fields = case thinking_budget > 0 {
    True -> [
      #(
        "thinking",
        json.object([
          #("type", json.string("enabled")),
          #("budget_tokens", json.int(thinking_budget)),
        ]),
      ),
      ..fields
    ]
    False -> fields
  }

  let fields = case req.provider_options {
    Some(options) -> list.append(options, fields)
    None -> fields
  }

  json.object(fields)
}

fn encode_message(msg: gai.Message) -> json.Json {
  let gai.Message(role:, content:, cache_control:) = msg
  let role_str = case role {
    gai.System -> "user"
    // Should not happen after extraction
    gai.User -> "user"
    gai.Assistant -> "assistant"
  }

  // Encode content, adding cache_control to the last content block if present
  let encoded_content = case cache_control {
    Some(gai.Ephemeral) -> encode_content_with_cache(content)
    None -> json.array(content, encode_content)
  }

  json.object([#("role", json.string(role_str)), #("content", encoded_content)])
}

fn encode_content_with_cache(content: List(gai.Content)) -> json.Json {
  // Add cache_control to the last content block
  let reversed = list.reverse(content)
  case reversed {
    [] -> json.array([], encode_content)
    [last, ..rest] -> {
      let last_with_cache = encode_content_cached(last)
      let rest_encoded = list.map(list.reverse(rest), encode_content)
      json.array(list.append(rest_encoded, [last_with_cache]), fn(x) { x })
    }
  }
}

fn encode_content_cached(content: gai.Content) -> json.Json {
  let cache_field = #(
    "cache_control",
    json.object([#("type", json.string("ephemeral"))]),
  )
  case content {
    gai.Text(text) ->
      json.object([
        #("type", json.string("text")),
        #("text", json.string(text)),
        cache_field,
      ])
    gai.Image(gai.ImageUrl(url)) ->
      json.object([
        #("type", json.string("image")),
        #(
          "source",
          json.object([
            #("type", json.string("url")),
            #("url", json.string(url)),
          ]),
        ),
        cache_field,
      ])
    gai.Image(gai.ImageBase64(data, media_type)) ->
      json.object([
        #("type", json.string("image")),
        #(
          "source",
          json.object([
            #("type", json.string("base64")),
            #("media_type", json.string(media_type)),
            #("data", json.string(data)),
          ]),
        ),
        cache_field,
      ])
    gai.Document(gai.DocumentUrl(url), media_type) ->
      json.object([
        #("type", json.string("document")),
        #(
          "source",
          json.object([
            #("type", json.string("url")),
            #("url", json.string(url)),
          ]),
        ),
        #("media_type", json.string(media_type)),
        cache_field,
      ])
    gai.Document(gai.DocumentBase64(data), media_type) ->
      json.object([
        #("type", json.string("document")),
        #(
          "source",
          json.object([
            #("type", json.string("base64")),
            #("data", json.string(data)),
          ]),
        ),
        #("media_type", json.string(media_type)),
        cache_field,
      ])
    // ToolUse, ToolResult, Thinking - cache_control doesn't apply, encode normally
    _ -> encode_content(content)
  }
}

fn encode_content(content: gai.Content) -> json.Json {
  case content {
    gai.Text(text) ->
      json.object([#("type", json.string("text")), #("text", json.string(text))])
    gai.Image(gai.ImageUrl(url)) ->
      json.object([
        #("type", json.string("image")),
        #(
          "source",
          json.object([
            #("type", json.string("url")),
            #("url", json.string(url)),
          ]),
        ),
      ])
    gai.Image(gai.ImageBase64(data, media_type)) ->
      json.object([
        #("type", json.string("image")),
        #(
          "source",
          json.object([
            #("type", json.string("base64")),
            #("media_type", json.string(media_type)),
            #("data", json.string(data)),
          ]),
        ),
      ])
    gai.Document(gai.DocumentUrl(url), media_type) ->
      json.object([
        #("type", json.string("document")),
        #(
          "source",
          json.object([
            #("type", json.string("url")),
            #("url", json.string(url)),
          ]),
        ),
        #("media_type", json.string(media_type)),
      ])
    gai.Document(gai.DocumentBase64(data), media_type) ->
      json.object([
        #("type", json.string("document")),
        #(
          "source",
          json.object([
            #("type", json.string("base64")),
            #("data", json.string(data)),
          ]),
        ),
        #("media_type", json.string(media_type)),
      ])
    gai.ToolUse(id, name, arguments_json) -> {
      // Parse the JSON string back to embed it
      let input = case json.parse(arguments_json, decode.dynamic) {
        Ok(d) -> json_decode.encode_dynamic(d)
        Error(_) -> json.object([])
      }
      json.object([
        #("type", json.string("tool_use")),
        #("id", json.string(id)),
        #("name", json.string(name)),
        #("input", input),
      ])
    }
    gai.ToolResult(tool_use_id, result_content) ->
      json.object([
        #("type", json.string("tool_result")),
        #("tool_use_id", json.string(tool_use_id)),
        #("content", json.array(result_content, encode_content)),
      ])
    gai.Thinking(text) ->
      // Thinking content shouldn't normally be sent back, but handle it gracefully
      json.object([
        #("type", json.string("thinking")),
        #("thinking", json.string(text)),
      ])
  }
}

fn encode_tool(t: tool.ToolSchema) -> json.Json {
  json.object([
    #("name", json.string(t.name)),
    #("description", json.string(t.description)),
    #("input_schema", t.schema),
  ])
}

fn encode_tool_choice(choice: gai_request.ToolChoice) -> json.Json {
  case choice {
    gai_request.Auto -> json.object([#("type", json.string("auto"))])
    gai_request.ToolNone -> json.object([#("type", json.string("none"))])
    gai_request.Required -> json.object([#("type", json.string("any"))])
    gai_request.Specific(name) ->
      json.object([
        #("type", json.string("tool")),
        #("name", json.string(name)),
      ])
  }
}

// ============================================================================
// Parse Response
// ============================================================================

/// Parse an HTTP response into a completion response
pub fn parse_response(
  resp: http_response.Response(String),
) -> Result(gai_response.CompletionResponse, gai.Error) {
  case resp.status {
    200 -> parse_success_response(resp.body)
    429 -> parse_rate_limit_error(resp)
    401 | 403 -> parse_auth_error(resp.body)
    status -> parse_error_response(status, resp.body)
  }
}

fn parse_success_response(
  body: String,
) -> Result(gai_response.CompletionResponse, gai.Error) {
  use data <- result.try(
    json.parse(body, decode.dynamic)
    |> result.map_error(fn(e) { gai.JsonError(string.inspect(e)) }),
  )

  use id <- result.try(
    json_decode.get_string(data, "id")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'id' field") }),
  )

  use model <- result.try(
    json_decode.get_string(data, "model")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'model' field") }),
  )

  use content_list <- result.try(
    json_decode.get_list(data, "content")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'content' field") }),
  )

  use stop_reason_str <- result.try(
    json_decode.get_string(data, "stop_reason")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'stop_reason' field") }),
  )

  use usage_data <- result.try(
    json_decode.get_dynamic(data, "usage")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'usage' field") }),
  )

  let content = list.filter_map(content_list, parse_content_block)
  let stop_reason = parse_stop_reason(stop_reason_str)
  let usage = parse_usage(usage_data)

  Ok(gai_response.CompletionResponse(
    id:,
    model:,
    content:,
    stop_reason:,
    usage:,
  ))
}

fn parse_content_block(block: Dynamic) -> Result(gai.Content, Nil) {
  use content_type <- result.try(json_decode.get_string(block, "type"))
  case content_type {
    "text" -> {
      use text <- result.try(json_decode.get_string(block, "text"))
      Ok(gai.Text(text))
    }
    "thinking" -> {
      use thinking_text <- result.try(json_decode.get_string(block, "thinking"))
      Ok(gai.Thinking(thinking_text))
    }
    "tool_use" -> {
      use id <- result.try(json_decode.get_string(block, "id"))
      use name <- result.try(json_decode.get_string(block, "name"))
      use input <- result.try(json_decode.get_dynamic(block, "input"))
      let arguments_json = json.to_string(json_decode.encode_dynamic(input))
      Ok(gai.ToolUse(id:, name:, arguments_json:))
    }
    _ -> Error(Nil)
  }
}

fn parse_stop_reason(reason: String) -> gai.StopReason {
  case reason {
    "end_turn" -> gai.EndTurn
    "max_tokens" -> gai.MaxTokens
    "stop_sequence" -> gai.StopSequence
    "tool_use" -> gai.ToolUsed
    _ -> gai.EndTurn
  }
}

fn parse_usage(data: Dynamic) -> gai.Usage {
  let input_tokens =
    json_decode.get_int(data, "input_tokens") |> result.unwrap(0)
  let output_tokens =
    json_decode.get_int(data, "output_tokens") |> result.unwrap(0)
  // Anthropic cache usage fields
  let cache_creation_input_tokens =
    json_decode.get_int(data, "cache_creation_input_tokens")
    |> option.from_result
  let cache_read_input_tokens =
    json_decode.get_int(data, "cache_read_input_tokens") |> option.from_result
  gai.Usage(
    input_tokens:,
    output_tokens:,
    cache_creation_input_tokens:,
    cache_read_input_tokens:,
  )
}

fn parse_rate_limit_error(
  resp: http_response.Response(String),
) -> Result(gai_response.CompletionResponse, gai.Error) {
  let retry_after =
    http_response.get_header(resp, "retry-after")
    |> result.try(int.parse)
    |> option.from_result

  Error(gai.RateLimited(retry_after:))
}

fn parse_auth_error(
  body: String,
) -> Result(gai_response.CompletionResponse, gai.Error) {
  let message = json_decode.parse_error_message(body, "Authentication failed")
  Error(gai.AuthError(message:))
}

fn parse_error_response(
  status: Int,
  body: String,
) -> Result(gai_response.CompletionResponse, gai.Error) {
  case json.parse(body, decode.dynamic) {
    Ok(data) -> {
      let error_obj =
        json_decode.get_dynamic(data, "error") |> result.unwrap(data)
      let message =
        json_decode.get_string(error_obj, "message")
        |> result.unwrap("Unknown error")
      let code =
        json_decode.get_string(error_obj, "type")
        |> result.unwrap("unknown_error")
      Error(gai.ApiError(code:, message:))
    }
    Error(_) -> Error(gai.HttpError(status:, body:))
  }
}

// ============================================================================
// Parse Stream Chunk
// ============================================================================

/// Parse a streaming chunk (SSE data line)
pub fn parse_stream_chunk(
  chunk: String,
) -> Result(streaming.StreamDelta, gai.Error) {
  case string.trim(chunk) {
    "" -> Ok(streaming.Ping)
    data -> parse_stream_data(data)
  }
}

fn parse_stream_data(data: String) -> Result(streaming.StreamDelta, gai.Error) {
  use parsed <- result.try(
    json.parse(data, decode.dynamic)
    |> result.map_error(fn(e) { gai.JsonError(string.inspect(e)) }),
  )

  case json_decode.get_string(parsed, "type") {
    Ok("message_stop") ->
      Ok(streaming.Done(stop_reason: gai.EndTurn, usage: None))
    Ok("content_block_delta") -> parse_content_delta(parsed)
    Ok("message_delta") -> parse_message_delta(parsed)
    Ok("error") -> {
      let error_obj =
        json_decode.get_dynamic(parsed, "error") |> result.unwrap(parsed)
      let message =
        json_decode.get_string(error_obj, "message")
        |> result.unwrap("Stream error")
      Error(gai.ApiError(code: "stream_error", message:))
    }
    _ -> Ok(streaming.Ping)
  }
}

fn parse_content_delta(
  data: Dynamic,
) -> Result(streaming.StreamDelta, gai.Error) {
  let text_result = {
    use delta <- result.try(json_decode.get_dynamic(data, "delta"))
    json_decode.get_string(delta, "text")
  }

  case text_result {
    Ok(text) -> Ok(streaming.ContentDelta(gai.Text(text)))
    Error(_) -> Ok(streaming.Ping)
  }
}

fn parse_message_delta(
  data: Dynamic,
) -> Result(streaming.StreamDelta, gai.Error) {
  let reason_result = {
    use delta <- result.try(json_decode.get_dynamic(data, "delta"))
    json_decode.get_string(delta, "stop_reason")
  }

  case reason_result {
    Ok(reason) -> {
      let stop_reason = parse_stop_reason(reason)
      let usage = case json_decode.get_dynamic(data, "usage") {
        Ok(u) -> Some(parse_usage(u))
        Error(_) -> None
      }
      Ok(streaming.Done(stop_reason:, usage:))
    }
    Error(_) -> Ok(streaming.Ping)
  }
}

// ============================================================================
// Provider Constructor
// ============================================================================

/// Create a Provider from config (for framework use)
pub fn provider(config: Config) -> provider.Provider {
  provider.Provider(
    name: "anthropic",
    build_request: fn(req) { build_request(config, req) },
    parse_response: parse_response,
    parse_stream_chunk: parse_stream_chunk,
  )
}
