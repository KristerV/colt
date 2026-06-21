defmodule ColtWeb.Sending.Stubs do
  @moduledoc """
  Shared placeholder card for sending views that are not yet implemented.
  Each phase replaces its own view with a real implementation.
  """
  use Phoenix.Component

  attr :kicker, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true

  def coming_soon(assigns) do
    ~H"""
    <div
      class="max-w-[640px] border border-border rounded-[11px] bg-card p-8"
      style="box-shadow:var(--shadow)"
    >
      <div class="text-[11px] tracking-[0.08em] uppercase text-inkFaint font-semibold mb-3.5">
        {@kicker}
      </div>
      <h1 class="text-[28px] font-semibold leading-[1.1] tracking-[-0.02em] m-0 text-ink text-pretty">
        {@title}
      </h1>
      <p class="mt-5 text-[15px] leading-[1.55] text-inkSoft max-w-[520px] text-pretty">
        {@body}
      </p>
      <div class="mt-7 text-[11px] tracking-[0.08em] uppercase text-inkFaint font-semibold">
        coming soon
      </div>
    </div>
    """
  end
end
