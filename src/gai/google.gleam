/// Google Gemini provider implementation.
///
/// For Gemini models via the Google Generative AI API.
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

/// Google Gemini configuration (opaque type)
pub opaque type Config {
  Config(api_key: String, base_url: String)
}

/// Create a new Google Gemini config
pub fn new(api_key: String) -> Config {
  Config(api_key:, base_url: "https://generativelanguage.googleapis.com/v1beta")
}

/// Use a custom base URL (for proxies, etc.)
pub fn with_base_url(config: Config, url: String) -> Config {
  Config(..config, base_url: url)
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
  let host = option.unwrap(base_uri.host, "generativelanguage.googleapis.com")
  let base_path = case base_uri.path {
    "" -> "/v1beta"
    p -> p
  }
  let path = base_path <> "/models/" <> req.model <> ":generateContent"
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
    |> http_request.set_query([#("key", config.api_key)])
    |> http_request.set_body(json.to_string(body))
    |> http_request.set_header("content-type", "application/json")

  case base_uri.port {
    Some(port) -> http_request.set_port(http_req, port)
    None -> http_req
  }
}

fn encode_request(req: gai_request.CompletionRequest) -> json.Json {
  // Extract system message from messages list
  let #(system_info, non_system_messages) =
    json_decode.extract_system_message(req.messages)

  let fields = [#("contents", json.array(non_system_messages, encode_content))]

  // Add system instruction if present (cache_control is Anthropic-specific, ignored here)
  let fields = case system_info {
    Some(json_decode.SystemMessage(text:, ..)) -> [
      #(
        "systemInstruction",
        json.object([
          #("parts", json.array([gai.Text(text)], encode_part)),
        ]),
      ),
      ..fields
    ]
    None -> fields
  }

  // Generation config
  let generation_config = build_generation_config(req)
  let fields = case generation_config {
    [] -> fields
    _ -> [#("generationConfig", json.object(generation_config)), ..fields]
  }

  // Tools
  let fields = case req.tools {
    Some(tools) -> [
      #(
        "tools",
        json.array(
          [
            json.object([
              #("functionDeclarations", json.array(tools, encode_tool)),
            ]),
          ],
          fn(x) { x },
        ),
      ),
      ..fields
    ]
    None -> fields
  }

  // Tool config
  let fields = case req.tool_choice {
    Some(choice) -> [#("toolConfig", encode_tool_config(choice)), ..fields]
    None -> fields
  }

  let fields = case req.provider_options {
    Some(options) -> list.append(options, fields)
    None -> fields
  }

  json.object(fields)
}

fn build_generation_config(
  req: gai_request.CompletionRequest,
) -> List(#(String, json.Json)) {
  let config = []

  let config = case req.max_tokens {
    Some(n) -> [#("maxOutputTokens", json.int(n)), ..config]
    None -> config
  }

  let config = case req.temperature {
    Some(t) -> [#("temperature", json.float(t)), ..config]
    None -> config
  }

  let config = case req.top_p {
    Some(p) -> [#("topP", json.float(p)), ..config]
    None -> config
  }

  let config = case req.stop {
    Some(sequences) -> [
      #("stopSequences", json.array(sequences, json.string)),
      ..config
    ]
    None -> config
  }

  // Response format
  let config = case req.response_format {
    Some(gai_request.JsonFormat) -> [
      #("responseMimeType", json.string("application/json")),
      ..config
    ]
    Some(gai_request.JsonSchemaFormat(schema:, ..)) -> [
      #("responseMimeType", json.string("application/json")),
      // Strip $schema and additionalProperties which Google doesn't support
      #("responseSchema", json_decode.strip_unsupported_schema_fields(schema)),
      ..config
    ]
    _ -> config
  }

  config
}

fn encode_content(msg: gai.Message) -> json.Json {
  let gai.Message(role:, content:, ..) = msg
  let role_str = case role {
    gai.System -> "user"
    // Should not happen after extraction
    gai.User -> "user"
    gai.Assistant -> "model"
  }

  json.object([
    #("role", json.string(role_str)),
    #("parts", json.array(content, encode_part)),
  ])
}

fn infer_image_mime_type(url: String) -> String {
  let lower = string.lowercase(url)
  case
    string.ends_with(lower, ".png"),
    string.ends_with(lower, ".gif"),
    string.ends_with(lower, ".webp"),
    string.ends_with(lower, ".svg"),
    string.ends_with(lower, ".bmp"),
    string.ends_with(lower, ".ico")
  {
    True, _, _, _, _, _ -> "image/png"
    _, True, _, _, _, _ -> "image/gif"
    _, _, True, _, _, _ -> "image/webp"
    _, _, _, True, _, _ -> "image/svg+xml"
    _, _, _, _, True, _ -> "image/bmp"
    _, _, _, _, _, True -> "image/x-icon"
    _, _, _, _, _, _ -> "image/jpeg"
  }
}

fn encode_part(content: gai.Content) -> json.Json {
  case content {
    gai.Text(text) -> json.object([#("text", json.string(text))])
    gai.Image(gai.ImageUrl(url)) ->
      json.object([
        #(
          "fileData",
          json.object([
            #("fileUri", json.string(url)),
            #("mimeType", json.string(infer_image_mime_type(url))),
          ]),
        ),
      ])
    gai.Image(gai.ImageBase64(data, media_type)) ->
      json.object([
        #(
          "inlineData",
          json.object([
            #("mimeType", json.string(media_type)),
            #("data", json.string(data)),
          ]),
        ),
      ])
    gai.Document(gai.DocumentUrl(url), media_type) ->
      json.object([
        #(
          "fileData",
          json.object([
            #("fileUri", json.string(url)),
            #("mimeType", json.string(media_type)),
          ]),
        ),
      ])
    gai.Document(gai.DocumentBase64(data), media_type) ->
      json.object([
        #(
          "inlineData",
          json.object([
            #("mimeType", json.string(media_type)),
            #("data", json.string(data)),
          ]),
        ),
      ])
    gai.ToolUse(_id, name, arguments_json) -> {
      let args = case json.parse(arguments_json, decode.dynamic) {
        Ok(d) -> json_decode.encode_dynamic(d)
        Error(_) -> json.object([])
      }
      json.object([
        #(
          "functionCall",
          json.object([
            #("name", json.string(name)),
            #("args", args),
          ]),
        ),
      ])
    }
    gai.ToolResult(tool_use_id, result_content) ->
      json.object([
        #(
          "functionResponse",
          json.object([
            #("name", json.string(tool_use_id)),
            #(
              "response",
              json.object([
                #("content", json.array(result_content, encode_part)),
              ]),
            ),
          ]),
        ),
      ])
    gai.Thinking(_) ->
      // Thinking is Anthropic-specific, ignored for Google
      json.object([#("text", json.string(""))])
  }
}

fn encode_tool(t: tool.Schema) -> json.Json {
  json.object([
    #("name", json.string(t.name)),
    #("description", json.string(t.description)),
    // Strip $schema and additionalProperties which Google doesn't support
    #("parameters", json_decode.strip_unsupported_schema_fields(t.schema)),
  ])
}

fn encode_tool_config(choice: gai_request.ToolChoice) -> json.Json {
  let mode = case choice {
    gai_request.Auto -> "AUTO"
    gai_request.ToolNone -> "NONE"
    gai_request.Required -> "ANY"
    gai_request.Specific(_) -> "ANY"
  }

  let config = [#("mode", json.string(mode))]

  let config = case choice {
    gai_request.Specific(name) -> [
      #("allowedFunctionNames", json.array([name], json.string)),
      ..config
    ]
    _ -> config
  }

  json.object([#("functionCallingConfig", json.object(config))])
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

  use candidates <- result.try(
    json_decode.get_list(data, "candidates")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'candidates' field") }),
  )

  use first_candidate <- result.try(
    list.first(candidates)
    |> result.map_error(fn(_) { gai.ParseError("Empty 'candidates' array") }),
  )

  use candidate_content <- result.try(
    json_decode.get_dynamic(first_candidate, "content")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'content' field") }),
  )

  use parts <- result.try(
    json_decode.get_list(candidate_content, "parts")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'parts' field") }),
  )

  use finish_reason <- result.try(
    json_decode.get_string(first_candidate, "finishReason")
    |> result.map_error(fn(_) { gai.ParseError("Missing 'finishReason' field") }),
  )

  let content =
    parts
    |> list.index_map(fn(part, idx) { parse_part(part, idx) })
    |> list.filter_map(fn(x) { x })
  let stop_reason = parse_stop_reason(finish_reason)
  let usage = parse_usage_metadata(data)

  // Generate an ID from model name (Gemini doesn't return one)
  let id = "gemini-response"
  let model = "gemini"

  Ok(gai_response.CompletionResponse(
    id:,
    model:,
    content:,
    stop_reason:,
    usage:,
  ))
}

fn parse_part(part: Dynamic, index: Int) -> Result(gai.Content, Nil) {
  case json_decode.get_string(part, "text") {
    Ok(text) -> Ok(gai.Text(text))
    Error(_) -> {
      case json_decode.get_dynamic(part, "functionCall") {
        Ok(fc) -> {
          use name <- result.try(json_decode.get_string(fc, "name"))
          let arguments_json = case json_decode.get_dynamic(fc, "args") {
            Ok(args) -> json.to_string(json_decode.encode_dynamic(args))
            Error(_) -> "{}"
          }
          // Generate a unique ID using index (Gemini doesn't provide one)
          let id = "fc_" <> int.to_string(index) <> "_" <> name
          Ok(gai.ToolUse(id:, name:, arguments_json:))
        }
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn parse_stop_reason(reason: String) -> gai.StopReason {
  case reason {
    "STOP" -> gai.EndTurn
    "MAX_TOKENS" -> gai.MaxTokens
    "SAFETY" -> gai.ContentFilter
    "RECITATION" -> gai.ContentFilter
    "FINISH_REASON_UNSPECIFIED" -> gai.EndTurn
    _ -> gai.EndTurn
  }
}

fn parse_usage_metadata(data: Dynamic) -> gai.Usage {
  case json_decode.get_dynamic(data, "usageMetadata") {
    Ok(usage) -> {
      let input_tokens =
        json_decode.get_int(usage, "promptTokenCount") |> result.unwrap(0)
      let output_tokens =
        json_decode.get_int(usage, "candidatesTokenCount") |> result.unwrap(0)
      gai.Usage(
        input_tokens:,
        output_tokens:,
        cache_creation_input_tokens: option.None,
        cache_read_input_tokens: option.None,
      )
    }
    Error(_) ->
      gai.Usage(
        input_tokens: 0,
        output_tokens: 0,
        cache_creation_input_tokens: option.None,
        cache_read_input_tokens: option.None,
      )
  }
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
        json_decode.get_string(error_obj, "status") |> result.unwrap("UNKNOWN")
      Error(gai.ApiError(code:, message:))
    }
    Error(_) -> Error(gai.HttpError(status:, body:))
  }
}

// ============================================================================
// Parse Stream Chunk
// ============================================================================

/// Parse a streaming chunk
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

  case json_decode.get_dynamic(parsed, "error") {
    Ok(err) -> {
      let message =
        json_decode.get_string(err, "message") |> result.unwrap("Stream error")
      Error(gai.ApiError(code: "stream_error", message:))
    }
    Error(_) -> parse_stream_candidate(parsed)
  }
}

fn parse_stream_candidate(
  data: Dynamic,
) -> Result(streaming.StreamDelta, gai.Error) {
  // Extract candidate, returning Ping for missing data
  let candidate = {
    use candidates <- result.try(json_decode.get_list(data, "candidates"))
    list.first(candidates)
  }

  case candidate {
    Error(_) -> Ok(streaming.Ping)
    Ok(candidate) -> {
      // Check for finish reason first
      case json_decode.get_string(candidate, "finishReason") {
        Ok(reason) -> {
          let stop_reason = parse_stop_reason(reason)
          let usage = Some(parse_usage_metadata(data))
          Ok(streaming.Done(stop_reason:, usage:))
        }
        Error(_) -> parse_stream_content_delta(candidate)
      }
    }
  }
}

fn parse_stream_content_delta(
  candidate: Dynamic,
) -> Result(streaming.StreamDelta, gai.Error) {
  let text_result = {
    use content <- result.try(json_decode.get_dynamic(candidate, "content"))
    use parts <- result.try(json_decode.get_list(content, "parts"))
    use part <- result.try(list.first(parts))
    json_decode.get_string(part, "text")
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
    name: "google",
    build_request: fn(req) { build_request(config, req) },
    parse_response: parse_response,
    parse_stream_chunk: parse_stream_chunk,
  )
}
