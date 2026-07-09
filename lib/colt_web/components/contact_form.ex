defmodule ColtWeb.Components.ContactForm do
  @moduledoc """
  The hand-entered contact form: person + company fields and the funnel picker.
  Extracted as its own component so the same fields can be reused wherever a
  contact is created (sales funnel today; potentially elsewhere later).

  Fully controlled — `values` (a string-keyed map) and `error` come from the
  host, so a failed submit re-renders with the user's input intact. The host
  wires `change_event` (per-keystroke, keeps `values` fresh) and `submit_event`.
  """
  use Phoenix.Component
  use Gettext, backend: ColtWeb.Gettext

  @markets [:ee, :fi, :lv, :lt, :se, :no, :dk, :pl]

  @doc "The markets offered in the company select."
  def markets, do: @markets

  attr :id, :string, default: "contact-form"
  attr :values, :map, required: true, doc: "string-keyed field values"
  attr :error, :any, default: nil
  attr :change_event, :string, default: "validate_contact"
  attr :submit_event, :string, default: "create_contact"

  def form(assigns) do
    ~H"""
    <form id={@id} phx-change={@change_event} phx-submit={@submit_event} class="flex flex-col gap-3">
      <div :if={@error} class="text-[12.5px] text-red font-medium">{@error}</div>

      <.field label={gettext("Name") <> " *"}>
        <.text_input name="name" value={@values["name"]} placeholder={gettext("Jane Tamm")} autofocus />
      </.field>

      <div class="grid grid-cols-2 gap-3">
        <.field label={gettext("Title")}>
          <.text_input name="title" value={@values["title"]} placeholder={gettext("optional")} />
        </.field>
        <.field label={gettext("Phone")}>
          <.text_input name="phone" value={@values["phone"]} placeholder={gettext("optional")} />
        </.field>
      </div>

      <.field label={gettext("Email")}>
        <.text_input
          type="email"
          name="email"
          value={@values["email"]}
          placeholder={gettext("optional")}
        />
      </.field>

      <div class="mt-1 flex flex-col gap-3 bg-bgSoft border border-border rounded-[8px] p-3">
        <div class="text-[11.5px] font-semibold text-inkSoft">{gettext("Company")}</div>

        <.field label={gettext("Name") <> " *"}>
          <.text_input
            name="company_name"
            value={@values["company_name"]}
            placeholder={gettext("Kohvik OÜ")}
          />
        </.field>

        <div class="grid grid-cols-2 gap-3">
          <.field label={gettext("Reg. code") <> " *"}>
            <.text_input name="registry_code" value={@values["registry_code"]} placeholder="12345678" />
          </.field>
          <.field label={gettext("Market") <> " *"}>
            <select
              name="market"
              class="w-full px-3 py-2.5 border border-border rounded-[8px] text-[14px] outline-none focus:border-accentRing bg-card"
            >
              <option :for={m <- markets()} value={m} selected={to_string(m) == @values["market"]}>
                {String.upcase(to_string(m))}
              </option>
            </select>
          </.field>
        </div>

        <.field label={gettext("Region")}>
          <.text_input name="region" value={@values["region"]} placeholder={gettext("optional")} />
        </.field>
      </div>

      <div class="mt-1 flex flex-col gap-2 bg-bgSoft border border-border rounded-[8px] p-3">
        <div class="text-[11.5px] font-semibold text-inkSoft">{gettext("Add to")}</div>
        <.checkbox name="in_funnel_sending" checked={@values["in_funnel_sending"] == "on"}>
          {gettext("Sending funnel — write & send emails")}
        </.checkbox>
        <.checkbox name="in_funnel_sales" checked={@values["in_funnel_sales"] == "on"}>
          {gettext("Sales funnel — start onboarding this lead")}
        </.checkbox>
      </div>
    </form>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp field(assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <label class="text-[11.5px] font-semibold text-inkSoft">{@label}</label>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :placeholder, :string, default: nil
  attr :rest, :global

  defp text_input(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      class="w-full px-3 py-2.5 border border-border rounded-[8px] text-[14px] outline-none focus:border-accentRing bg-card"
      {@rest}
    />
    """
  end

  attr :name, :string, required: true
  attr :checked, :boolean, default: false
  slot :inner_block, required: true

  defp checkbox(assigns) do
    ~H"""
    <label class="flex items-center gap-2.5 text-[13px] text-ink cursor-pointer">
      <input type="checkbox" name={@name} checked={@checked} class="accent-accent w-[15px] h-[15px]" />
      <span>{render_slot(@inner_block)}</span>
    </label>
    """
  end
end
