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
    <div class="max-w-[640px] border border-rule rounded-[2px] bg-paper p-8">
      <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-3.5">
        {@kicker}
      </div>
      <h1 class="font-serif font-normal text-[32px] leading-[1.05] tracking-[-0.03em] m-0 text-pretty">
        {@title}
      </h1>
      <p class="mt-5 text-[15px] leading-[1.55] text-ink55 max-w-[520px] text-pretty">
        {@body}
      </p>
      <div class="mt-7 font-mono text-[11px] tracking-[0.08em] uppercase text-ink40">
        coming soon
      </div>
    </div>
    """
  end
end
