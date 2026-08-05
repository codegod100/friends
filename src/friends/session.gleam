//// Signed browser session for authenticated users.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import wisp

pub const cookie_name = "friends_session"

pub const cookie_max_age = 604_800

pub type UserSession {
  UserSession(sub: String, name: Option(String))
}

pub fn encode(session: UserSession) -> String {
  let name = case session.name {
    Some(value) -> json.string(value)
    None -> json.null()
  }

  json.to_string(
    json.object([
      #("sub", json.string(session.sub)),
      #("name", name),
    ]),
  )
}

pub fn decode(raw: String) -> Result(UserSession, Nil) {
  let decoder = {
    use sub <- decode.field("sub", decode.string)
    // Accept missing name, JSON null, or a string.
    use name <- decode.optional_field(
      "name",
      None,
      decode.optional(decode.string),
    )
    decode.success(UserSession(sub:, name:))
  }

  json.parse(raw, decoder)
  |> result.map_error(fn(_) { Nil })
}

pub fn read(request: wisp.Request) -> Option(UserSession) {
  case wisp.get_cookie(request, cookie_name, wisp.Signed) {
    Ok(raw) ->
      case decode(raw) {
        Ok(session) -> Some(session)
        Error(_) -> None
      }
    Error(_) -> None
  }
}

pub fn write(
  response: wisp.Response,
  request: wisp.Request,
  session: UserSession,
) -> wisp.Response {
  response
  |> wisp.set_cookie(
    request,
    cookie_name,
    encode(session),
    wisp.Signed,
    cookie_max_age,
  )
}

pub fn clear(response: wisp.Response, request: wisp.Request) -> wisp.Response {
  response
  |> wisp.set_cookie(request, cookie_name, "", wisp.Signed, 0)
}

pub fn display_name(session: UserSession) -> String {
  case session.name {
    Some(name) -> name
    None -> session.sub
  }
}
