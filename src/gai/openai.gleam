/// OpenAI provider implementation.
///
/// Supports OpenAI and OpenAI-compatible APIs (OpenRouter, xAI, Mistral, etc.)
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
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

// ============================================================================
// Config
// ============================================================================

/// OpenAI configuration (opaque type)
pub opaque type Config {
  Config(api_key: String, base_url: String, organization: Option(String))
}

/// Create a new OpenAI config
pub fn new(api_key: String) -> Config {
  Config(api_key:, base_url: "https://api.openai.com/v1", organization: None)
}

/// Use a custom base URL (for proxies, Azure, etc.)
pub fn with_base_url(config: Config, url: String) -> Config {
  Config(..config, base_url: url)
}

/// Set organization ID
pub fn with_organization(config: Config, org: String) -> Config {
  Config(..config, organization: Some(org))
}

// ============================================================================
// Convenience constructors for OpenAI-compatible providers
// ============================================================================

/// Create config for OpenRouter
pub fn openrouter(api_key: String) -> Config {
  Config(api_key:, base_url: "https://openrouter.ai/api/v1", organization: None)
}

/// Create config for xAI (Grok)
pub fn xai(api_key: String) -> Config {
  Config(api_key:, base_url: "https://api.x.ai/v1", organization: None)
}

/// Create config for Mistral
pub fn mistral(api_key: String) -> Config {
  Config(api_key:, base_url: "https://api.mistral.ai/v1", organization: None)
}

/// Create config for Groq
pub fn groq(api_key: String) -> Config {
  Config(
    api_key:,
    base_url: "https://api.groq.com/openai/v1",
    organization: None,
  )
}

/// Create config for Together AI
pub fn together(api_key: String) -> Config {
  Config(api_key:, base_url: "https://api.together.xyz/v1", organization: None)
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
  let host = option.unwrap(base_uri.host, "api.openai.com")
  let base_path = case base_uri.path {
    "" -> "/v1"
    p -> p
  }
  let path = base_path <> "/chat/completions"
  let scheme = case base_uri.scheme {
    Some("http") -> http.Http
    _ -> http.Https
  }

  let body = encode_request(req)

  let http_req =
    http_request.new()
    |> http_request.set_method(http.Post)
    |> http_request.set_scheme(scheme)
    |> http_request.set_host(host)
    |> http_request.set_path(path)
    |> http_request.set_body(json.to_string(body))
    |> http_request.set_header("content-type", "application/json")
    |> http_request.set_header("authorization", "Bearer " <> config.api_key)

  let http_req = case base_uri.port {
    Some(port) -> http_request.set_port(http_req, port)
    None -> http_req
  }

  case config.organization {
    Some(org) -> http_request.set_header(http_req, "openai-organization", org)
    None -> http_req
  }
}

fn encode_request(req: gai_request.CompletionRequest) -> json.Json {
  let fields = [
    #("model", json.string(req.model)),
    #("messages", json.array(req.messages, encode_message)),
  ]

  let fields = case req.max_tokens {
    Some(n) -> [#("max_completion_tokens", json.int(n)), ..fields]
    None -> fields
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
    Some(sequences) -> [#("stop", json.array(sequences, json.string)), ..fields]
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

  let fields = case req.response_format {
    Some(format) -> [
      #("response_format", encode_response_format(format)),
      ..fields
    ]
    None -> fields
  }

  let fields = case req.provider_options {
    Some(options) -> list.append(options, fields)
    None -> fields
  }

  json.object(fields)
}

fn encode_message(msg: gai.Message) -> json.Json {
  let gai.Message(role:, content:, ..) = msg
  let role_str = case role {
    gai.System -> "system"
    gai.User -> "user"
    gai.Assistant -> "assistant"
  }

  case content {
    [gai.Text(text)] ->
      json.object([
        #("role", json.string(role_str)),
        #("content", json.string(text)),
      ])
    _ ->
      json.object([
        #("role", json.string(role_str)),
        #("content", json.array(content, encode_content)),
      ])
  }
}

fn encode_content(content: gai.Content) -> json.Json {
  case content {
    gai.Text(text) ->
      json.object([#("type", json.string("text")), #("text", json.string(text))])
    gai.Image(gai.ImageUrl(url)) ->
      json.object([
        #("type", json.string("image_url")),
        #("image_url", json.object([#("url", json.string(url))])),
      ])
    gai.Image(gai.ImageBase64(data, media_type)) ->
      json.object([
        #("type", json.string("image_url")),
        #(
          "image_url",
          json.object([
            #("url", json.string("data:" <> media_type <> ";base64," <> data)),
          ]),
        ),
      ])
    gai.Document(gai.DocumentUrl(url), _media_type) ->
      json.object([
        #("type", json.string("text")),
        #("text", json.string("[Document: " <> url <> "]")),
      ])
    gai.Document(gai.DocumentBase64(_data), _media_type) ->
      json.object([
        #("type", json.string("text")),
        #("text", json.string("[Document]")),
      ])
    gai.ToolUse(id, name, arguments_json) -> {
      // Parse the JSON string back to embed it
      let args = case json.parse(arguments_json, decode.dynamic) {
        Ok(d) -> json_decode.encode_dynamic(d)
        Error(_) -> json.object([])
      }
      json.object([
        #("type", json.string("text")),
        #("text", json.string("[Tool call: " <> name <> " (" <> id <> ")]")),
        #(
          "_tool_use",
          json.object([
            #("id", json.string(id)),
            #("name", json.string(name)),
            #("arguments", args),
          ]),
        ),
      ])
    }
    gai.ToolResult(tool_use_id, result_content) ->
      json.object([
        #("type", json.string("tool_result")),
        #("tool_use_id", json.string(tool_use_id)),
        #("content", json.array(result_content, encode_content)),
      ])
    gai.Thinking(_) ->
      // Thinking is Anthropic-specific, ignored for OpenAI
      json.object([#("type", json.string("text")), #("text", json.string(""))])
  }
}

fn encode_tool(t: tool.ToolSchema) -> json.Json {
  json.object([
    #("type", json.string("function")),
    #(
      "function",
      json.object([
        #("name", json.string(t.name)),
        #("description", json.string(t.description)),
        #("parameters", t.schema),
      ]),
    ),
  ])
}

fn encode_tool_choice(choice: gai_request.ToolChoice) -> json.Json {
  case choice {
    gai_request.Auto -> json.string("auto")
    gai_request.ToolNone -> json.string("none")
    gai_request.Required -> json.string("required")
    gai_request.Specific(name) ->
      json.object([
        #("type", json.string("function")),
        #("function", json.object([#("name", json.string(name))])),
      ])
  }
}

fn encode_response_format(format: gai_request.ResponseFormat) -> json.Json {
  case format {
    gai_request.TextFormat -> json.object([#("type", json.string("text"))])
    gai_request.JsonFormat ->
      json.object([#("type", json.string("json_object"))])
    gai_request.JsonSchemaFormat(schema:, name:, strict:) ->
      json.object([
        #("type", json.string("json_schema")),
        #(
          "json_schema",
          json.object([
            #("name", json.string(name)),
            #("strict", json.bool(strict)),
            #("schema", schema),
          ]),
        ),
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

  use choices <- result.try(
    json_decode.get_list(data, "choices")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'choices' field") }),
  )

  use first_choice <- result.try(
    list.first(choices)
    |> result.map_error(fn(_) { gai.ParseError("Empty 'choices' array") }),
  )

  use message <- result.try(
    json_decode.get_dynamic(first_choice, "message")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'message' field") }),
  )

  use finish_reason <- result.try(
    json_decode.get_string(first_choice, "finish_reason")
    |> result.map_error(fn(_) {
      gai.ParseError("Missing 'finish_reason' field")
    }),
  )

  use usage_data <- result.try(
    json_decode.get_dynamic(data, "usage")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'usage' field") }),
  )

  let content = parse_message_content(message)
  let stop_reason = parse_stop_reason(finish_reason)
  let usage = parse_usage(usage_data)

  Ok(gai_response.CompletionResponse(
    id:,
    model:,
    content:,
    stop_reason:,
    usage:,
  ))
}

fn parse_message_content(message: Dynamic) -> List(gai.Content) {
  let text_content = case json_decode.get_string(message, "content") {
    Ok(text) -> [gai.Text(text)]
    Error(_) -> []
  }

  let tool_calls = case json_decode.get_list(message, "tool_calls") {
    Ok(calls) -> list.filter_map(calls, parse_tool_call)
    Error(_) -> []
  }

  list.append(text_content, tool_calls)
}

fn parse_tool_call(call: Dynamic) -> Result(gai.Content, Nil) {
  use id <- result.try(json_decode.get_string(call, "id"))
  use function <- result.try(json_decode.get_dynamic(call, "function"))
  use name <- result.try(json_decode.get_string(function, "name"))
  use arguments_json <- result.try(json_decode.get_string(function, "arguments"))

  Ok(gai.ToolUse(id:, name:, arguments_json:))
}

fn parse_stop_reason(reason: String) -> gai.StopReason {
  case reason {
    "stop" -> gai.EndTurn
    "length" -> gai.MaxTokens
    "tool_calls" -> gai.ToolUsed
    "content_filter" -> gai.ContentFilter
    _ -> gai.EndTurn
  }
}

fn parse_usage(data: Dynamic) -> gai.Usage {
  let prompt_tokens =
    json_decode.get_int(data, "prompt_tokens") |> result.unwrap(0)
  let completion_tokens =
    json_decode.get_int(data, "completion_tokens") |> result.unwrap(0)
  gai.Usage(
    input_tokens: prompt_tokens,
    output_tokens: completion_tokens,
    cache_creation_input_tokens: option.None,
    cache_read_input_tokens: option.None,
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
        json_decode.get_string(error_obj, "code") |> result.unwrap("unknown")
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
    "[DONE]" -> Ok(streaming.Done(stop_reason: gai.EndTurn, usage: None))
    "" -> Ok(streaming.Ping)
    data -> parse_stream_data(data)
  }
}

fn parse_stream_data(data: String) -> Result(streaming.StreamDelta, gai.Error) {
  use parsed <- result.try(
    json.parse(data, decode.dynamic)
    |> result.map_error(fn(e) { gai.JsonError(string.inspect(e)) }),
  )

  case json_decode.get_dynamic(parsed, "error") {
    Ok(err) -> {
      let message =
        json_decode.get_string(err, "message") |> result.unwrap("Stream error")
      Error(gai.ApiError(code: "stream_error", message:))
    }
    Error(_) -> parse_stream_delta(parsed)
  }
}

fn parse_stream_delta(data: Dynamic) -> Result(streaming.StreamDelta, gai.Error) {
  use choices <- result.try(
    json_decode.get_list(data, "choices")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'choices' in stream") }),
  )

  case list.first(choices) {
    Error(_) -> Ok(streaming.Ping)
    Ok(choice) -> {
      // Check for finish reason first
      case json_decode.get_string(choice, "finish_reason") {
        Ok(reason) -> {
          let stop_reason = parse_stop_reason(reason)
          let usage = case json_decode.get_dynamic(data, "usage") {
            Ok(u) -> Some(parse_usage(u))
            Error(_) -> None
          }
          Ok(streaming.Done(stop_reason:, usage:))
        }
        Error(_) -> parse_stream_content_delta(choice)
      }
    }
  }
}

fn parse_stream_content_delta(
  choice: Dynamic,
) -> Result(streaming.StreamDelta, gai.Error) {
  let text_result = {
    use delta <- result.try(json_decode.get_dynamic(choice, "delta"))
    json_decode.get_string(delta, "content")
  }

  case text_result {
    Ok(text) -> Ok(streaming.ContentDelta(gai.Text(text)))
    Error(_) -> Ok(streaming.Ping)
  }
}

// ============================================================================
// Provider Constructor
// ============================================================================

/// Create a Provider from config (for framework use)
pub fn provider(config: Config) -> provider.Provider {
  provider.Provider(
    name: "openai",
    build_request: fn(req) { build_request(config, req) },
    parse_response: parse_response,
    parse_stream_chunk: parse_stream_chunk,
  )
}
