import gai
import gai/provider
import gai/request
import gai/response
import gai/streaming
import gleam/http/request as http_request
import gleam/http/response as http_response
import gleam/option

fn test_usage(input: Int, output: Int) -> gai.Usage {
  gai.Usage(
    input_tokens: input,
    output_tokens: output,
    cache_creation_input_tokens: option.None,
    cache_read_input_tokens: option.None,
  )
}

pub fn provider_name_test() {
  let p = make_test_provider()
  provider.name(p)
  |> should_equal("test")
}

pub fn provider_build_request_test() {
  let p = make_test_provider()
  let req = request.new("test-model", [gai.user_text("Hello")])

  let http_req = provider.build_request(p, req)
  let assert http_request.Request(body: "test request body", ..) = http_req
}

pub fn provider_parse_response_test() {
  let p = make_test_provider()
  let http_resp =
    http_response.new(200)
    |> http_response.set_body("test response")

  let assert Ok(resp) = provider.parse_response(p, http_resp)
  let assert response.CompletionResponse(id: "test-id", ..) = resp
}

// Helper to create a test provider
fn make_test_provider() -> provider.Provider {
  provider.Provider(
    name: "test",
    build_request: fn(_req) {
      http_request.new()
      |> http_request.set_body("test request body")
    },
    parse_response: fn(_resp) {
      Ok(response.CompletionResponse(
        id: "test-id",
        model: "test-model",
        content: [gai.Text("Test response")],
        stop_reason: gai.EndTurn,
        usage: test_usage(10, 5),
      ))
    },
    parse_stream_chunk: fn(_chunk) { Ok(streaming.Ping) },
  )
}

fn should_equal(actual: a, expected: a) -> Nil {
  assert actual == expected
}
