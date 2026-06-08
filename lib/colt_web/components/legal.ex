defmodule ColtWeb.Components.Legal do
  @moduledoc """
  Shared layout components for the static legal pages (privacy policy, terms of
  service). Plain-prose styling that respects the design tokens — serif page
  title, mono kicker + meta, comfortable measure on body copy.
  """
  use Phoenix.Component

  @doc """
  Page wrapper: mono kicker, serif title, "last updated" meta line, then the
  article body. Constrains to a readable measure.
  """
  attr :kicker, :string, required: true
  attr :title, :string, required: true
  attr :updated, :string, required: true
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div class="max-w-[760px] mx-auto w-full">
      <section class="pt-10 md:pt-20 pb-8 md:pb-10">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-5">
          {@kicker}
        </div>
        <h1 class="font-serif font-normal text-[40px] md:text-[64px] leading-[1.02] tracking-[-0.04em] m-0 text-pretty">
          {@title}
        </h1>
        <p class="mt-5 font-mono text-[11px] tracking-[0.08em] uppercase text-ink40 m-0">
          Last updated {@updated}
        </p>
      </section>
      <article class="pb-20 md:pb-28 space-y-9">
        {render_slot(@inner_block)}
      </article>
    </div>
    """
  end

  @doc """
  A numbered section: mono index + sans heading, then prose body. Body slot is
  styled for paragraphs, lists and inline links via descendant selectors.
  """
  attr :n, :string, default: nil
  attr :title, :string, required: true
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section class="space-y-3">
      <h2 class="font-sans font-medium text-[19px] md:text-[22px] tracking-[-0.01em] text-ink m-0 scroll-mt-24">
        <span :if={@n} class="font-mono text-[13px] text-ink40 mr-2">{@n}</span>{@title}
      </h2>
      <div class={[
        "text-[15px] leading-[1.65] text-ink70 space-y-3",
        "[&_a]:text-accent [&_a]:no-underline hover:[&_a]:underline",
        "[&_strong]:text-ink [&_strong]:font-medium",
        "[&_ul]:list-disc [&_ul]:pl-5 [&_ul]:space-y-1.5 [&_li]:marker:text-ink40",
        "[&_h3]:text-ink [&_h3]:font-medium [&_h3]:text-[15px] [&_h3]:mt-5 [&_h3]:mb-1"
      ]}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
