/// Runtime abstraction for HTTP transport.
///
/// The Runtime type provides an abstraction over HTTP clients, allowing
/// the agent/loop to work with any HTTP implementation on any target.
///
/// ## Erlang Example
///
/// ```gleam
/// import gleam/httpc
///
/// let runtime = runtime.new(fn(req) {
///   httpc.send(req)
///   |> result.map_error(fn(_) { gai.HttpError(0, "Request failed") })
/// })
/// ```
///
/// ## JavaScript Example
///
/// ```gleam
/// // Note: JS requires async handling - see runtime/fetch.gleam
/// ```
import gai.{type Error}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}

/// Runtime provides HTTP transport abstraction.
///
/// The send function takes an HTTP request and returns a response
/// or an error. This allows the agent to be agnostic about the
/// underlying HTTP client.
pub type Runtime {
  Runtime(send: fn(Request(String)) -> Result(Response(String), Error))
}

/// Create a new runtime from a send function.
///
/// ## Example
///
/// ```gleam
/// let runtime = runtime.new(fn(req) {
///   // Your HTTP client here
///   my_http_client.send(req)
/// })
/// ```
pub fn new(
  send send: fn(Request(String)) -> Result(Response(String), Error),
) -> Runtime {
  Runtime(send:)
}

/// Send an HTTP request using the runtime.
pub fn send(
  runtime: Runtime,
  request: Request(String),
) -> Result(Response(String), Error) {
  runtime.send(request)
}
