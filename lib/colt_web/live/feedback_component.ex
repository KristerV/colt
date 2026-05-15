defmodule ColtWeb.FeedbackComponent do
  @moduledoc """
  Navbar feedback modal. Mounted once via `Layouts.app`.
  Open/close are client-side via JS commands; submit goes to the server.
  """
  use ColtWeb, :live_component

  alias Colt.Resources.Feedback
  alias ColtWeb.Components.Liid
  alias Phoenix.LiveView.JS

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="feedback-modal"
      phx-hook="FeedbackModal"
      class="hidden fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
      phx-window-keydown={close()}
      phx-key="escape"
    >
      <div
        class="bg-paper border border-ink20 rounded-sharp w-full max-w-[520px] my-auto px-6 py-7 md:px-9 md:pt-8 md:pb-7"
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away={close()}
      >
        <div class="flex justify-between items-start gap-3 mb-6">
          <div class="min-w-0">
            <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-1.5">
              Feedback
            </div>
            <h2 class="font-serif font-normal text-[24px] md:text-[32px] leading-[1.1] tracking-[-0.02em] m-0">
              Tell us what's <em class="italic">off</em>.
            </h2>
          </div>
          <button
            type="button"
            class="w-6 h-6 flex items-center justify-center cursor-pointer"
            phx-click={close()}
          >
            <Liid.icon name="x" size={14} />
          </button>
        </div>

        <form phx-submit="submit" phx-target={@myself} class="flex flex-col gap-4">
          <textarea
            id="feedback-body"
            name="body"
            rows="6"
            required
            placeholder="What's broken, missing, or just bad?"
            class="w-full bg-transparent border border-ink20 rounded-sharp px-3.5 py-3 text-[14px] text-ink placeholder:text-ink40 focus:outline-none focus:border-ink resize-y"
          ></textarea>

          <div class="flex justify-end gap-2">
            <Liid.btn variant={:secondary} phx-click={close()}>
              Cancel
            </Liid.btn>
            <Liid.btn variant={:primary} type="submit">
              Send
            </Liid.btn>
          </div>
        </form>
      </div>
    </div>
    """
  end

  def close do
    JS.add_class("hidden", to: "#feedback-modal")
  end

  @impl true
  def handle_event("submit", %{"body" => body}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, socket}
    else
      user_id = socket.assigns.current_user && socket.assigns.current_user.id
      {:ok, _} = Feedback.submit(body, user_id)
      {:noreply, push_event(socket, "feedback:sent", %{})}
    end
  end
end
