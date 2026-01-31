//// Internal helpers for provider implementations.
////
//// Shared utilities for working with dynamic JSON data and messages.
//// This module is internal and not part of the public API.

import gai
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Get a string field from dynamic data
pub fn get_string(data: Dynamic, field: String) -> Result(String, Nil) {
  let decoder = {
    use value <- decode.field(field, decode.string)
    decode.success(value)
  }
  decode.run(data, decoder)
  |> result.replace_error(Nil)
}

/// Get an int field from dynamic data
pub fn get_int(data: Dynamic, field: String) -> Result(Int, Nil) {
  let decoder = {
    use value <- decode.field(field, decode.int)
    decode.success(value)
  }
  decode.run(data, decoder)
  |> result.replace_error(Nil)
}

/// Get a dynamic field from dynamic data (preserves nested structure)
pub fn get_dynamic(data: Dynamic, field: String) -> Result(Dynamic, Nil) {
  let decoder = {
    use value <- decode.field(field, decode.dynamic)
    decode.success(value)
  }
  decode.run(data, decoder)
  |> result.replace_error(Nil)
}

/// Get a list of dynamic values from a field
pub fn get_list(data: Dynamic, field: String) -> Result(List(Dynamic), Nil) {
  let decoder = {
    use value <- decode.field(field, decode.list(decode.dynamic))
    decode.success(value)
  }
  decode.run(data, decoder)
  |> result.replace_error(Nil)
}

/// Encode a dynamic value as JSON.
/// Handles nested objects, arrays, and primitive types.
pub fn encode_dynamic(value: Dynamic) -> json.Json {
  // Try as object (dict of key-value pairs)
  case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
    Ok(d) -> {
      d
      |> dict.to_list
      |> list.map(fn(pair) { #(pair.0, encode_dynamic(pair.1)) })
      |> json.object
    }
    Error(_) -> {
      // Try as array
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(items) -> json.array(items, encode_dynamic)
        Error(_) -> encode_primitive(value)
      }
    }
  }
}

/// System message extraction result with text and cache control
pub type SystemMessage {
  SystemMessage(text: String, cache_control: Option(gai.CacheControl))
}

/// Extract system message from message list.
/// Returns the system message info (if present) and the non-system messages.
/// Used by providers that require system message in a separate field.
pub fn extract_system_message(
  messages: List(gai.Message),
) -> #(Option(SystemMessage), List(gai.Message)) {
  let #(system_msgs, non_system) =
    list.partition(messages, fn(m) {
      case m {
        gai.Message(role: gai.System, ..) -> True
        _ -> False
      }
    })

  let system_info = case system_msgs {
    [gai.Message(content: [gai.Text(text)], cache_control:, ..)] ->
      Some(SystemMessage(text:, cache_control:))
    _ -> None
  }

  #(system_info, non_system)
}

/// Parse error message from API response body.
/// Tries to extract error.message from JSON, falls back to default.
pub fn parse_error_message(body: String, default_message: String) -> String {
  case json.parse(body, decode.dynamic) {
    Ok(data) -> {
      let error_obj = get_dynamic(data, "error") |> result.unwrap(data)
      get_string(error_obj, "message") |> result.unwrap(default_message)
    }
    Error(_) -> default_message
  }
}

/// Strip fields from a JSON object that are not supported by certain APIs.
/// Specifically removes "$schema" and "additionalProperties" recursively.
/// Used by Google provider which doesn't support these JSON Schema fields.
pub fn strip_unsupported_schema_fields(schema: json.Json) -> json.Json {
  let json_str = json.to_string(schema)
  case json.parse(json_str, decode.dynamic) {
    Ok(data) -> strip_fields_from_dynamic(data)
    Error(_) -> schema
  }
}

fn strip_fields_from_dynamic(data: Dynamic) -> json.Json {
  // Try as object (dict of key-value pairs)
  case decode.run(data, decode.dict(decode.string, decode.dynamic)) {
    Ok(dict) -> {
      dict
      |> dict.to_list
      |> list.filter(fn(pair) {
        let #(key, _) = pair
        key != "$schema" && key != "additionalProperties"
      })
      |> list.map(fn(pair) {
        let #(key, value) = pair
        #(key, strip_fields_from_dynamic(value))
      })
      |> json.object
    }
    Error(_) -> {
      // Try as array
      case decode.run(data, decode.list(decode.dynamic)) {
        Ok(items) -> json.array(items, strip_fields_from_dynamic)
        Error(_) -> encode_primitive(data)
      }
    }
  }
}

fn encode_primitive(data: Dynamic) -> json.Json {
  let string_result = decode.run(data, decode.string)
  let int_result = decode.run(data, decode.int)
  let float_result = decode.run(data, decode.float)
  let bool_result = decode.run(data, decode.bool)

  case string_result, int_result, float_result, bool_result {
    Ok(s), _, _, _ -> json.string(s)
    _, Ok(i), _, _ -> json.int(i)
    _, _, Ok(f), _ -> json.float(f)
    _, _, _, Ok(b) -> json.bool(b)
    _, _, _, _ -> json.null()
  }
}
