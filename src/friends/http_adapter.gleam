//// Bridge Wisp requests/responses to Lightspeed HTTP types.

import friends/session
import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lightspeed/framework/http as ls_http
import wisp

pub fn from_wisp(wisp_request: wisp.Request) -> ls_http.Request {
  ls_http.request(
    method: method_from_wisp(wisp_request.method),
    path: wisp_request.path,
    headers: wisp_request.headers,
    body: read_body(wisp_request),
    session_id: session_id(wisp_request),
    csrf_token: csrf_token(wisp_request),
    origin: origin(wisp_request),
    session: session_values(wisp_request),
    flash: [],
  )
}

pub fn to_wisp(
  wisp_request: wisp.Request,
  conn_response: ls_http.Response,
) -> wisp.Response {
  let response =
    wisp.response(conn_response.status)
    |> wisp.set_body(wisp.Text(conn_response.body))
    |> set_headers(conn_response.headers)

  list.fold(conn_response.session, response, fn(acc, entry) {
    let #(key, value) = entry
    wisp.set_cookie(
      acc,
      wisp_request,
      key,
      value,
      wisp.Signed,
      60 * 60 * 24 * 7,
    )
  })
}

fn set_headers(
  response: wisp.Response,
  headers: List(#(String, String)),
) -> wisp.Response {
  // set-cookie must be prepended: gleam_http set_header replaces by key and
  // would collapse multiple cookies into one.
  list.fold(headers, response, fn(acc, header) {
    let #(key, value) = header
    case string.lowercase(key) {
      "set-cookie" -> response.prepend_header(acc, "set-cookie", value)
      _ -> response.set_header(acc, key, value)
    }
  })
}

fn read_body(wisp_request: wisp.Request) -> String {
  case wisp.read_body_bits(wisp_request) {
    Ok(bits) -> bit_array.to_string(bits) |> result.unwrap("")
    Error(_) -> ""
  }
}

fn method_from_wisp(method: http.Method) -> ls_http.Method {
  case method {
    http.Get -> ls_http.Get
    http.Post -> ls_http.Post
    http.Put -> ls_http.Put
    http.Patch -> ls_http.Patch
    http.Delete -> ls_http.Delete
    http.Head -> ls_http.Head
    http.Options -> ls_http.Options
    http.Other(label) -> ls_http.Other(label)
    http.Connect -> ls_http.Other("CONNECT")
    http.Trace -> ls_http.Other("TRACE")
  }
}

fn session_id(wisp_request: wisp.Request) -> String {
  case wisp.get_cookie(wisp_request, "friends_ls_session", wisp.Signed) {
    Ok(value) -> value
    Error(_) -> "guest"
  }
}

fn csrf_token(wisp_request: wisp.Request) -> String {
  case wisp.get_cookie(wisp_request, "friends_csrf", wisp.Signed) {
    Ok(value) -> value
    Error(_) -> "dev"
  }
}

fn origin(wisp_request: wisp.Request) -> String {
  case request.get_header(wisp_request, "origin") {
    Ok(value) -> value
    Error(_) ->
      case request.get_header(wisp_request, "host") {
        Ok(host) -> "https://" <> host
        Error(_) -> "http://localhost"
      }
  }
}

fn session_values(wisp_request: wisp.Request) -> List(#(String, String)) {
  case session.read(wisp_request) {
    Some(user) -> [
      #("user_sub", user.sub),
      #("user_name", session.display_name(user)),
    ]
    None -> []
  }
}
