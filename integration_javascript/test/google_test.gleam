import envoy
import gai
import gai/google
import gai/request
import gai/response
import gai/schema
import gleam/fetch
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/string
import sextant

const model = "gemini-2.0-flash"

fn with_api_key(test_fn: fn(String) -> Promise(Nil)) -> Promise(Nil) {
  case envoy.get("GOOGLE_API_KEY") {
    Ok(api_key) -> test_fn(api_key)
    Error(_) -> promise.resolve(Nil)
  }
}

pub fn basic_completion_test() -> Promise(Nil) {
  use api_key <- with_api_key

  let config = google.new(api_key)
  let req =
    request.new(model, [gai.user_text("Say 'hello' and nothing else.")])
    |> request.with_max_tokens(10)

  let http_req = google.build_request(config, req)

  fetch.send(http_req)
  |> promise.try_await(fetch.read_text_body)
  |> promise.map(fn(result) {
    let assert Ok(http_resp) = result
    let assert Ok(completion) = google.parse_response(http_resp)
    let text = response.text_content(completion)
    assert string.contains(string.lowercase(text), "hello")
    Nil
  })
}

pub fn json_mode_test() -> Promise(Nil) {
  use api_key <- with_api_key

  let config = google.new(api_key)
  let req =
    request.new(model, [
      gai.user_text(
        "Return a JSON object with a single key 'greeting' and value 'hello'.",
      ),
    ])
    |> request.with_max_tokens(50)
    |> request.with_response_format(request.JsonFormat)

  let http_req = google.build_request(config, req)

  fetch.send(http_req)
  |> promise.try_await(fetch.read_text_body)
  |> promise.map(fn(result) {
    let assert Ok(http_resp) = result
    let assert Ok(completion) = google.parse_response(http_resp)
    let text = response.text_content(completion)
    assert string.contains(text, "greeting")
    assert string.contains(text, "hello")
    Nil
  })
}

pub fn json_schema_test() -> Promise(Nil) {
  use api_key <- with_api_key

  let schema =
    json.object([
      #("type", json.string("object")),
      #(
        "properties",
        json.object([
          #("greeting", json.object([#("type", json.string("string"))])),
        ]),
      ),
      #("required", json.preprocessed_array([json.string("greeting")])),
    ])

  let config = google.new(api_key)
  let req =
    request.new(model, [gai.user_text("Generate a greeting message.")])
    |> request.with_max_tokens(50)
    |> request.with_response_format(request.JsonSchemaFormat(
      schema: schema,
      name: "greeting_response",
      strict: True,
    ))

  let http_req = google.build_request(config, req)

  fetch.send(http_req)
  |> promise.try_await(fetch.read_text_body)
  |> promise.map(fn(result) {
    let assert Ok(http_resp) = result
    let assert Ok(completion) = google.parse_response(http_resp)
    let text = response.text_content(completion)
    assert string.contains(text, "greeting")
    Nil
  })
}

pub type GreetingResponse {
  GreetingResponse(greeting: String)
}

pub fn typed_schema_test() -> Promise(Nil) {
  use api_key <- with_api_key

  let greeting_schema =
    schema.new("greeting_response", {
      use greeting <- sextant.field("greeting", sextant.string())
      sextant.success(GreetingResponse(greeting))
    })

  let config = google.new(api_key)
  let req =
    request.new(model, [gai.user_text("Say hello to the user.")])
    |> request.with_max_tokens(50)
    |> request.with_schema(greeting_schema)

  let http_req = google.build_request(config, req)

  fetch.send(http_req)
  |> promise.try_await(fetch.read_text_body)
  |> promise.map(fn(result) {
    let assert Ok(http_resp) = result
    let assert Ok(completion) = google.parse_response(http_resp)
    let text = response.text_content(completion)
    let assert Ok(GreetingResponse(greeting)) =
      schema.parse(greeting_schema, text)
    assert greeting != ""
    Nil
  })
}
