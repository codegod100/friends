import friends/app
import friends/config
import gleam/erlang/process
import gleam/int
import gleam/io
import mist
import wisp/wisp_mist

pub fn main() {
  case config.load() {
    Ok(app_config) -> {
      let application = app.new(app_config)
      let secret_key_base = app_config.secret_key_base

      io.println(
        "Friends listening on http://localhost:"
        <> int.to_string(app_config.port),
      )

      let assert Ok(_) =
        fn(request) { app.handle(application, request) }
        |> wisp_mist.handler(secret_key_base)
        |> mist.new
        |> mist.port(app_config.port)
        |> mist.bind("0.0.0.0")
        |> mist.start

      process.sleep_forever()
    }

    Error(reason) -> {
      io.println("Failed to start Friends: " <> reason)
    }
  }
}
