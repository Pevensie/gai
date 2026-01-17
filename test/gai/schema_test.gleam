import gai/schema
import gleam/json
import gleam/string
import sextant

pub type Greeting {
  Greeting(message: String)
}

pub fn new_schema_test() {
  let sextant_schema = {
    use message <- sextant.field("message", sextant.string())
    sextant.success(Greeting(message))
  }

  let s = schema.new("greeting", sextant_schema)

  let assert "greeting" = schema.name(s)
  assert schema.strict(s)
}

pub fn with_strict_test() {
  let sextant_schema = {
    use message <- sextant.field("message", sextant.string())
    sextant.success(Greeting(message))
  }

  let s =
    schema.new("greeting", sextant_schema)
    |> schema.with_strict(False)

  let assert False = schema.strict(s)
}

pub fn to_json_schema_test() {
  let sextant_schema = {
    use message <- sextant.field("message", sextant.string())
    sextant.success(Greeting(message))
  }

  let s = schema.new("greeting", sextant_schema)
  let json_schema = schema.to_json_schema(s)

  // Should produce valid JSON with expected structure
  let json_str = json.to_string(json_schema)
  assert string.contains(json_str, "\"type\"")
  assert string.contains(json_str, "\"properties\"")
  assert string.contains(json_str, "\"message\"")
}

pub fn parse_valid_json_test() {
  let sextant_schema = {
    use message <- sextant.field("message", sextant.string())
    sextant.success(Greeting(message))
  }

  let s = schema.new("greeting", sextant_schema)

  let assert Ok(Greeting("hello")) = schema.parse(s, "{\"message\": \"hello\"}")
}

pub fn parse_invalid_json_test() {
  let sextant_schema = {
    use message <- sextant.field("message", sextant.string())
    sextant.success(Greeting(message))
  }

  let s = schema.new("greeting", sextant_schema)

  let assert Error(_) = schema.parse(s, "not valid json")
}

pub fn parse_missing_field_test() {
  let sextant_schema = {
    use message <- sextant.field("message", sextant.string())
    sextant.success(Greeting(message))
  }

  let s = schema.new("greeting", sextant_schema)

  let assert Error(_) = schema.parse(s, "{}")
}
