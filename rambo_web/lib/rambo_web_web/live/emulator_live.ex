defmodule RamboWebWeb.EmulatorLive do
  use RamboWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:rom_name, nil)
     |> assign(:status, :idle)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("rom-loaded", %{"name" => name}, socket) do
    {:noreply,
     socket
     |> assign(:rom_name, name)
     |> assign(:status, :running)
     |> assign(:error, nil)}
  end

  def handle_event("rom-error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign(:status, :idle)
     |> assign(:error, message)}
  end

  def handle_event("rom-clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:rom_name, nil)
     |> assign(:status, :idle)
     |> assign(:error, nil)
     |> push_event("rambo:shutdown", %{})}
  end

  def handle_event("pause", _params, socket) do
    {:noreply,
     socket
     |> assign(:status, :paused)
     |> push_event("rambo:pause", %{})}
  end

  def handle_event("resume", _params, socket) do
    {:noreply,
     socket
     |> assign(:status, :running)
     |> push_event("rambo:resume", %{})}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(:status, :running)
     |> push_event("rambo:reset", %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="rambo-emulator"
      class="container mx-auto max-w-4xl px-4 py-6 space-y-6"
      phx-hook="RamboEmulator"
      data-wasm-path={~p"/rambo.wasm"}
    >
      <div class="flex flex-col gap-6 lg:flex-row">
        <div class="rounded-lg border border-slate-700 bg-slate-900 p-4 shadow-lg">
          <canvas
            id="rambo-canvas"
            width="256"
            height="240"
            class="h-[360px] w-[384px] max-w-full rounded bg-black"
          >
          </canvas>
          <p class="mt-2 text-sm text-slate-400">
            Use arrow keys for D-pad, X for A, Z for B, Enter for Start, Shift for Select.
          </p>
        </div>

        <div class="flex-1 space-y-4">
          <section class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
            <h2 class="text-lg font-semibold text-slate-900">Load ROM</h2>
            <p class="text-sm text-slate-600">
              Select an iNES-compatible ROM file to run the emulator in your browser.
            </p>
            <div class="mt-3 flex items-center gap-3">
              <input
                type="file"
                accept=".nes,.NES"
                class="block w-full cursor-pointer rounded border border-slate-300 p-2 text-sm file:mr-4 file:rounded file:border-0 file:bg-indigo-600 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-white hover:file:bg-indigo-700"
              />
              <button
                type="button"
                phx-click="rom-clear"
                class="rounded border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={is_nil(@rom_name)}
              >
                Eject ROM
              </button>
            </div>
            <%= if @rom_name do %>
              <p class="mt-2 rounded bg-slate-100 px-3 py-2 text-sm text-slate-700">
                Loaded ROM: <span class="font-medium"><%= @rom_name %></span>
              </p>
            <% end %>
            <%= if @error do %>
              <p class="mt-2 rounded bg-red-100 px-3 py-2 text-sm text-red-700">
                <%= @error %>
              </p>
            <% end %>
          </section>

          <section class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
            <h2 class="text-lg font-semibold text-slate-900">Controls</h2>
            <div class="mt-3 flex flex-wrap gap-3">
              <button
                type="button"
                phx-click="resume"
                class="rounded bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-700 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={@status == :running or is_nil(@rom_name)}
              >
                Resume
              </button>
              <button
                type="button"
                phx-click="pause"
                class="rounded bg-slate-200 px-4 py-2 text-sm font-semibold text-slate-800 hover:bg-slate-300 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={@status != :running}
              >
                Pause
              </button>
              <button
                type="button"
                phx-click="reset"
                class="rounded border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={is_nil(@rom_name)}
              >
                Reset
              </button>
            </div>
            <p class="mt-3 text-sm text-slate-600">
              Status: <span class="font-medium capitalize text-slate-800"><%= @status %></span>
            </p>
          </section>
        </div>
      </div>
    </div>
    """
  end
end
