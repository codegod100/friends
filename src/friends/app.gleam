//// Application routes and request dispatch.

import friends/auth
import friends/config.{type Config}
import friends/feed
import friends/html
import friends/session
import friends/store
import friends/views/home
import gleam/bit_array
import gleam/http
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import wisp

pub type App {
  App(config: Config)
}

pub fn new(config: Config) -> App {
  App(config:)
}

pub fn handle(app: App, request: wisp.Request) -> wisp.Response {
  case request.method, request.path {
    http.Get, "/" -> serve_home(app, request)
    http.Get, "/feed.atom" -> serve_feed(app, request)
    http.Get, "/auth/login" -> auth_login(app, request)
    http.Get, "/auth/callback" -> auth_callback(app, request)
    http.Get, "/auth/complete" -> auth_complete(app, request)
    http.Get, "/auth/logout" -> auth.logout(request)
    http.Post, "/handles" -> add_handle(app, request)
    http.Post, path -> {
      case is_delete_handle_path(path) {
        True -> delete_handle(app, request, path)
        False -> wisp.not_found()
      }
    }
    _, _ -> wisp.not_found()
  }
}

fn is_delete_handle_path(path: String) -> Bool {
  string.starts_with(path, "/handles/") && string.ends_with(path, "/delete")
}

fn serve_home(app: App, request: wisp.Request) -> wisp.Response {
  let body =
    home.render(
      app.config,
      session.read(request),
      store.open(app.config.data_path),
      read_flash(request),
    )

  wisp.html_response(body, 200)
  |> clear_flash(request)
}

fn serve_feed(app: App, request: wisp.Request) -> wisp.Response {
  case session.read(request) {
    None -> wisp.redirect("/auth/login")
    Some(user) -> {
      let current = store.open(app.config.data_path)
      case feed.build_atom(app.config, current, user.sub) {
        Ok(body) ->
          wisp.response(200)
          |> wisp.set_header(
            "content-type",
            "application/atom+xml; charset=utf-8",
          )
          |> wisp.set_header("cache-control", "public, max-age=300")
          |> wisp.set_body(wisp.Text(body))

        Error(reason) ->
          wisp.response(400)
          |> wisp.set_header("content-type", "text/plain; charset=utf-8")
          |> wisp.set_body(wisp.Text(reason))
      }
    }
  }
}

fn auth_login(app: App, request: wisp.Request) -> wisp.Response {
  case session.read(request) {
    Some(_) -> wisp.redirect("/")
    None -> auth.login_redirect(app.config, request)
  }
}

fn auth_callback(app: App, request: wisp.Request) -> wisp.Response {
  case auth.callback(app.config, request) {
    Ok(response) -> response
    Error(reason) -> auth_error(reason)
  }
}

fn auth_complete(app: App, request: wisp.Request) -> wisp.Response {
  case auth.complete(app.config, request) {
    Ok(#(user, response)) -> {
      let body =
        home.render(
          app.config,
          Some(user),
          store.open(app.config.data_path),
          None,
        )
      response
      |> wisp.set_header("content-type", "text/html; charset=utf-8")
      |> wisp.set_body(wisp.Text(body))
    }
    Error(reason) -> auth_error(reason)
  }
}

fn auth_error(reason: String) -> wisp.Response {
  wisp.html_response(
    html.page(
      "Sign in failed",
      "<p>Could not complete sign in: "
        <> html.escape_text(reason)
        <> "</p><p><a href=\"/auth/login\">Try again</a></p>",
    ),
    400,
  )
}

fn add_handle(app: App, request: wisp.Request) -> wisp.Response {
  case session.read(request) {
    None -> wisp.redirect("/auth/login")
    Some(user) -> {
      let form = parse_form(request)
      case list.key_find(form, "handle") {
        Ok(handle) -> {
          let current = store.open(app.config.data_path)
          case store.add_handle(current, user.sub, handle) {
            Ok(#(_next, added)) -> {
              let message = case added {
                True -> "Added @" <> store.normalize_handle(handle)
                False -> "Handle is already on your list"
              }
              redirect_with_flash(request, message)
            }
            Error(reason) -> redirect_with_flash(request, reason)
          }
        }
        Error(_) -> redirect_with_flash(request, "missing handle")
      }
    }
  }
}

fn delete_handle(
  app: App,
  request: wisp.Request,
  path: String,
) -> wisp.Response {
  let encoded_handle =
    path
    |> string.drop_start(up_to: 9)
    |> string.drop_end(up_to: 7)

  let handle =
    uri.percent_decode(encoded_handle)
    |> result.unwrap(encoded_handle)

  case session.read(request) {
    None -> wisp.redirect("/auth/login")
    Some(user) -> {
      let current = store.open(app.config.data_path)
      case store.remove_handle(current, user.sub, handle) {
        Ok(#(_next, _removed)) ->
          redirect_with_flash(request, "Removed @" <> handle)
        Error(reason) -> redirect_with_flash(request, reason)
      }
    }
  }
}

fn redirect_with_flash(
  request: wisp.Request,
  message: String,
) -> wisp.Response {
  wisp.redirect("/")
  |> wisp.set_cookie(request, "friends_flash", message, wisp.Signed, 60)
}

fn read_flash(request: wisp.Request) -> Option(String) {
  case wisp.get_cookie(request, "friends_flash", wisp.Signed) {
    Ok(message) -> Some(message)
    Error(_) -> None
  }
}

fn clear_flash(
  response: wisp.Response,
  request: wisp.Request,
) -> wisp.Response {
  case wisp.get_cookie(request, "friends_flash", wisp.Signed) {
    Ok(_) ->
      wisp.set_cookie(response, request, "friends_flash", "", wisp.Signed, 0)
    Error(_) -> response
  }
}

fn parse_form(request: wisp.Request) -> List(#(String, String)) {
  case wisp.read_body_bits(request) {
    Ok(bits) ->
      case bit_array.to_string(bits) {
        Ok(text) -> uri.parse_query(text) |> result.unwrap([])
        Error(_) -> []
      }
    Error(_) -> []
  }
}
