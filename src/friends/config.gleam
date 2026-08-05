//// Runtime configuration from environment variables.

import envoy
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const default_issuer = "https://id.openbao.boxd.sh"

pub const default_port = 8000

pub const session_cookie = "friends_session"

pub const oauth_state_cookie = "friends_oauth_state"

pub type Config {
  Config(
    port: Int,
    base_url: String,
    secret_key_base: String,
    data_path: String,
    oidc_issuer: String,
    oidc_client_id: String,
    oidc_client_secret: String,
    oidc_redirect_uri: String,
    websocket_path: String,
  )
}

pub fn load() -> Result(Config, String) {
  use port <- result.try(read_int("FRIENDS_PORT", default_port))
  use base_url <- result.try(require_env_or(
    "FRIENDS_BASE_URL",
    "http://localhost:8000",
  ))
  use secret_key_base <- result.try(require_env_or(
    "FRIENDS_SECRET_KEY_BASE",
    "development-secret-key-base-change-me-in-production-please",
  ))
  use data_path <- result.try(require_env_or(
    "FRIENDS_DATA_PATH",
    "data/handles.json",
  ))
  use oidc_issuer <- result.try(require_env_or(
    "FRIENDS_OIDC_ISSUER",
    default_issuer,
  ))
  use oidc_client_id <- result.try(require_env("FRIENDS_OIDC_CLIENT_ID"))
  use oidc_client_secret <- result.try(require_env("FRIENDS_OIDC_CLIENT_SECRET"))
  use redirect_uri <- result.try(require_env_or(
    "FRIENDS_OIDC_REDIRECT_URI",
    base_url <> "/auth/callback",
  ))

  Ok(Config(
    port: port,
    base_url: trim_trailing_slash(base_url),
    secret_key_base: secret_key_base,
    data_path: data_path,
    oidc_issuer: trim_trailing_slash(oidc_issuer),
    oidc_client_id: oidc_client_id,
    oidc_client_secret: oidc_client_secret,
    oidc_redirect_uri: redirect_uri,
    websocket_path: "/live",
  ))
}

pub fn discovery_url(config: Config) -> String {
  config.oidc_issuer <> "/.well-known/openid-configuration"
}

pub fn authorize_url(config: Config) -> String {
  // Pocket ID exposes /authorize at the issuer root.
  config.oidc_issuer <> "/authorize"
}

pub fn token_url(config: Config) -> String {
  // Pocket ID token endpoint is under /api/oidc (see .well-known/openid-configuration).
  config.oidc_issuer <> "/api/oidc/token"
}

fn require_env(name: String) -> Result(String, String) {
  case envoy.get(name) {
    Ok(value) ->
      case string.trim(value) {
        "" -> Error("missing environment variable: " <> name)
        trimmed -> Ok(trimmed)
      }
    Error(_) -> Error("missing environment variable: " <> name)
  }
}

fn require_env_or(name: String, default: String) -> Result(String, String) {
  case envoy.get(name) {
    Ok(value) ->
      case string.trim(value) {
        "" -> Ok(default)
        trimmed -> Ok(trimmed)
      }
    Error(_) -> Ok(default)
  }
}

fn read_int(name: String, default: Int) -> Result(Int, String) {
  case envoy.get(name) {
    Error(_) -> Ok(default)
    Ok(value) ->
      case int.parse(string.trim(value)) {
        Ok(parsed) -> Ok(parsed)
        Error(_) -> Error("invalid integer for " <> name)
      }
  }
}

fn trim_trailing_slash(value: String) -> String {
  case string.ends_with(value, "/") {
    True -> string.drop_end(value, 1)
    False -> value
  }
}
