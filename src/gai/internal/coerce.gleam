/// Internal coerce utility for existential type patterns.
///
/// This module provides a way to "erase" type parameters while maintaining
/// runtime safety. It works because neither Erlang nor JavaScript have
/// runtime type checking - types are a compile-time construct only.
/// Coerce a value to a different type.
/// 
/// This is safe at runtime because:
/// - Erlang/BEAM doesn't have runtime type checking
/// - JavaScript doesn't have runtime type checking
/// 
/// The Gleam compiler sees a type change, but at runtime it's a no-op
/// (just returns the value unchanged).
/// 
/// **Warning**: This bypasses Gleam's type system. Only use when you're
/// certain the runtime representation is compatible (e.g., erasing phantom
/// type parameters).
@external(erlang, "gleam@function", "identity")
@external(javascript, "../gleam_stdlib/gleam/function", "identity")
pub fn unsafe_coerce(value: a) -> b
