/// Response memoization types for caching LLM responses.
///
/// Provides types and key generation for caching responses locally.
/// gai is transport-agnostic, so actual storage is the caller's responsibility.
import gai.{type Content, type Message}
import gai/request.{type CompletionRequest, type ResponseFormat, type ToolChoice}
import gai/tool
import gleam/bit_array
import gleam/crypto
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string

// ============================================================================
// CacheKey
// ============================================================================

/// Opaque cache key wrapping a deterministic hash of the request
pub opaque type CacheKey {
  CacheKey(hash: String)
}

/// Generate a deterministic cache key from a completion request.
/// The key includes: model, messages, max_tokens, temperature, tools, tool_choice, response_format.
/// It excludes: provider_options (may contain non-deterministic values).
pub fn cache_key(req: CompletionRequest) -> CacheKey {
  let json_str = serialise_request(req)
  let hash = hash_string(json_str)
  CacheKey(hash:)
}

/// Convert a cache key to a string for use as storage key
pub fn key_to_string(key: CacheKey) -> String {
  key.hash
}

// ============================================================================
// CacheConfig
// ============================================================================

/// Configuration for response caching
pub opaque type CacheConfig {
  CacheConfig(ttl_seconds: Int)
}

/// Create default cache config with 1 hour TTL
pub fn default_cache_config() -> CacheConfig {
  CacheConfig(ttl_seconds: 3600)
}

/// Create cache config with custom TTL in seconds
pub fn with_ttl(ttl_seconds: Int) -> CacheConfig {
  CacheConfig(ttl_seconds:)
}

/// Get TTL in seconds from cache config
pub fn ttl_seconds(config: CacheConfig) -> Int {
  config.ttl_seconds
}

// ============================================================================
// Serialization
// ============================================================================

fn serialise_request(req: CompletionRequest) -> String {
  let fields = [
    #("model", json.string(req.model)),
    #("messages", json.array(req.messages, serialise_message)),
  ]

  let fields = case req.max_tokens {
    Some(n) -> [#("max_tokens", json.int(n)), ..fields]
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
    Some(seqs) -> [#("stop", json.array(seqs, json.string)), ..fields]
    None -> fields
  }

  let fields = case req.tools {
    Some(tools) -> [#("tools", json.array(tools, serialise_tool)), ..fields]
    None -> fields
  }

  let fields = case req.tool_choice {
    Some(choice) -> [#("tool_choice", serialise_tool_choice(choice)), ..fields]
    None -> fields
  }

  let fields = case req.response_format {
    Some(fmt) -> [
      #("response_format", serialise_response_format(fmt)),
      ..fields
    ]
    None -> fields
  }

  // Sort fields by key for deterministic ordering
  let sorted_fields = list.sort(fields, fn(a, b) { string.compare(a.0, b.0) })

  json.to_string(json.object(sorted_fields))
}

fn serialise_message(msg: Message) -> json.Json {
  let gai.Message(role:, content:, cache_control:) = msg
  let role_str = case role {
    gai.System -> "system"
    gai.User -> "user"
    gai.Assistant -> "assistant"
  }

  let fields = [
    #("role", json.string(role_str)),
    #("content", json.array(content, serialise_content)),
  ]

  let fields = case cache_control {
    Some(gai.Ephemeral) -> [
      #("cache_control", json.string("ephemeral")),
      ..fields
    ]
    None -> fields
  }

  json.object(fields)
}

fn serialise_content(content: Content) -> json.Json {
  case content {
    gai.Text(text) ->
      json.object([#("type", json.string("text")), #("text", json.string(text))])
    gai.Image(source) -> {
      let source_json = case source {
        gai.ImageUrl(url) ->
          json.object([
            #("type", json.string("url")),
            #("url", json.string(url)),
          ])
        gai.ImageBase64(data, media_type) ->
          json.object([
            #("type", json.string("base64")),
            #("data", json.string(data)),
            #("media_type", json.string(media_type)),
          ])
      }
      json.object([#("type", json.string("image")), #("source", source_json)])
    }
    gai.Document(source, media_type) -> {
      let source_json = case source {
        gai.DocumentUrl(url) ->
          json.object([
            #("type", json.string("url")),
            #("url", json.string(url)),
          ])
        gai.DocumentBase64(data) ->
          json.object([
            #("type", json.string("base64")),
            #("data", json.string(data)),
          ])
      }
      json.object([
        #("type", json.string("document")),
        #("source", source_json),
        #("media_type", json.string(media_type)),
      ])
    }
    gai.ToolUse(id, name, arguments_json) ->
      json.object([
        #("type", json.string("tool_use")),
        #("id", json.string(id)),
        #("name", json.string(name)),
        #("arguments", json.string(arguments_json)),
      ])
    gai.ToolResult(tool_use_id, result_content) ->
      json.object([
        #("type", json.string("tool_result")),
        #("tool_use_id", json.string(tool_use_id)),
        #("content", json.array(result_content, serialise_content)),
      ])
    gai.Thinking(text) ->
      json.object([
        #("type", json.string("thinking")),
        #("text", json.string(text)),
      ])
  }
}

fn serialise_tool(t: tool.ToolSchema) -> json.Json {
  json.object([
    #("name", json.string(t.name)),
    #("description", json.string(t.description)),
    #("schema", t.schema),
  ])
}

fn serialise_tool_choice(choice: ToolChoice) -> json.Json {
  case choice {
    request.Auto -> json.string("auto")
    request.ToolNone -> json.string("none")
    request.Required -> json.string("required")
    request.Specific(name) ->
      json.object([
        #("type", json.string("specific")),
        #("name", json.string(name)),
      ])
  }
}

fn serialise_response_format(fmt: ResponseFormat) -> json.Json {
  case fmt {
    request.TextFormat -> json.string("text")
    request.JsonFormat -> json.string("json")
    request.JsonSchemaFormat(schema:, name:, strict:) ->
      json.object([
        #("type", json.string("json_schema")),
        #("schema", schema),
        #("name", json.string(name)),
        #("strict", json.bool(strict)),
      ])
  }
}

fn hash_string(s: String) -> String {
  let bytes = bit_array.from_string(s)
  let hash = crypto.hash(crypto.Sha256, bytes)
  base16_encode(hash)
}

fn base16_encode(bytes: BitArray) -> String {
  bytes
  |> bit_array.base16_encode
  |> string.lowercase
}
