# RamboWeb

Phoenix LiveView front-end for the RAMBO NES emulator WebAssembly build.

## Setup

```bash
# From the repository root build the wasm artifact
zig build wasm

# Install Elixir dependencies and JS toolchain
cd rambo_web
mix setup

# Optional: rebuild static assets after tweaking the UI
mix assets.build
```

## Run the web UI

```bash
cd rambo_web
mix phx.server
```

Then open [http://localhost:5000](http://localhost:5000) to upload an iNES ROM, control the emulator directly in the browser, and stream frames rendered from the WebAssembly core.

## Production

Ready to deploy? Review the official [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) and ensure the `rambo.wasm` asset is served alongside the compiled static files.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
