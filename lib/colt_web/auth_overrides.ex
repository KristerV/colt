defmodule ColtWeb.AuthOverrides do
  @moduledoc """
  Liid styling for the AshAuthentication.Phoenix sign-in / magic-link / confirm
  / reset screens. Layered before the DaisyUI defaults so these win.

  Keep visuals consistent with `docs/design.md` ("Calm Pro") and the
  living demos in `priv/design_demos/`.
  """
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.Components

  alias AshAuthentication.Phoenix.{
    ConfirmLive,
    MagicSignInLive,
    ResetLive,
    SignInLive,
    SignOutLive
  }

  @page_root "min-h-screen grid place-items-center bg-canvas text-ink px-4 py-12"
  @card_class "w-full max-w-[420px] bg-card border border-border rounded-[11px] shadow-card p-8 flex flex-col gap-6"
  @label_class "text-[28px] font-semibold leading-[1.1] tracking-[-0.02em] text-ink mb-2"
  @input_class """
  w-full bg-card border border-borderStrong rounded-[8px] px-4 py-3
  text-[14px] text-ink placeholder:text-inkFaint focus:outline-none
  focus:border-accent focus:ring-2 focus:ring-accentRing
  """
  @primary_button """
  w-full inline-flex items-center justify-center gap-2 px-[18px] py-[10px]
  bg-accent text-white border border-transparent rounded-[8px]
  text-[14px] font-semibold
  hover:bg-[#2f6acb] cursor-pointer transition-colors
  """
  @hint_class "text-[13px] text-inkSoft"

  override SignInLive do
    set :root_class, @page_root
  end

  override SignOutLive do
    set :root_class, @page_root
  end

  override ConfirmLive do
    set :root_class, @page_root
  end

  override ResetLive do
    set :root_class, @page_root
  end

  override MagicSignInLive do
    set :root_class, @page_root
  end

  override Components.Banner do
    set :root_class, "w-full flex justify-center py-2 mb-4"
    set :href_url, "/"
    set :href_class, "flex items-baseline gap-1.5 no-underline text-ink"
    set :image_class, "hidden"
    set :dark_image_class, "hidden"
    set :image_url, ""
    set :dark_image_url, ""
    set :text_class, "text-[28px] font-semibold leading-none tracking-[-0.02em] text-ink"
    set :text, "Liid"
  end

  override Components.SignIn do
    set :root_class, @card_class
    set :strategy_class, "w-full"
    set :authentication_error_container_class, @hint_class <> " text-center"
    set :authentication_error_text_class, "text-red"
    set :strategy_display_order, :forms_first
  end

  override Components.MagicLink do
    set :root_class, "w-full"
    set :label_class, @label_class
    set :form_class, "flex flex-col gap-3"

    set :request_flash_text,
        "If this user exists, a sign-in link is on its way."

    set :disable_button_text, "Requesting…"
  end

  override Components.MagicLink.Input do
    set :submit_class, @primary_button <> " mt-2"
    set :submit_label, "Complete log in"
    set :input_debounce, 350
    set :remember_me_class, "flex items-center gap-2 mt-2 mb-2 text-inkSoft"
    set :remember_me_input_label, "Remember me"
    set :checkbox_class, "accent-accent mr-2"
    set :checkbox_label_class, "text-[13px] text-inkSoft"
  end

  override Components.SignOut do
    set :root_class, @card_class
    set :h2_class, @label_class
    set :h2_text, "Sign out"
    set :info_text, "Sure?"
    set :info_text_class, "text-[14px] text-inkSoft mb-4"
    set :form_class, nil
    set :button_text, "Sign out"
    set :button_class, @primary_button
  end

  override Components.Confirm do
    set :root_class, @card_class
    set :strategy_class, "w-full"
  end

  override Components.Confirm.Input do
    set :submit_class, @primary_button <> " mt-4"
  end

  override Components.Reset do
    set :root_class, @card_class
    set :strategy_class, "w-full"
  end

  override Components.Reset.Form do
    set :root_class, nil
    set :label_class, @label_class
    set :form_class, "flex flex-col gap-3"
    set :spacer_class, "py-1"
    set :button_text, "Change password"
    set :disable_button_text, "Changing password…"
  end

  override Components.HorizontalRule do
    set :root_class, "relative my-3"
    set :hr_outer_class, "absolute inset-0 flex items-center"
    set :hr_inner_class, "w-full border-t border-border"
    set :text_outer_class, "relative flex justify-center"

    set :text_inner_class,
        "px-3 bg-card text-[11px] uppercase tracking-[0.08em] text-inkFaint font-semibold"

    set :text, "or"
  end

  override Components.Flash do
    set :message_class_info,
        "fixed top-4 right-4 w-80 z-50 rounded-[11px] border border-border bg-card shadow-card px-4 py-3 text-[13px] text-ink"

    set :message_class_error,
        "fixed top-4 right-4 w-80 z-50 rounded-[11px] border border-red bg-redSoft shadow-card px-4 py-3 text-[13px] text-red"
  end

  override Components.Password do
    set :root_class, "w-full"
    set :interstitial_class, "flex flex-row justify-between text-[12px] mt-3"

    set :toggler_class,
        "text-[13px] text-inkSoft hover:text-ink"

    set :sign_in_toggle_text, "Have an account?"
    set :register_toggle_text, "Need an account?"
    set :reset_toggle_text, "Forgot password?"
    set :show_first, :sign_in
    set :hide_class, "hidden"
  end

  override Components.Password.SignInForm do
    set :root_class, nil
    set :label_class, @label_class
    set :form_class, "flex flex-col gap-3"
    set :slot_class, ""
    set :button_text, "Sign in"
    set :disable_button_text, "Signing in…"
  end

  override Components.Password.RegisterForm do
    set :root_class, nil
    set :label_class, @label_class
    set :form_class, "flex flex-col gap-3"
    set :slot_class, ""
    set :button_text, "Register"
    set :disable_button_text, "Registering…"
  end

  override Components.Password.ResetForm do
    set :root_class, nil
    set :label_class, @label_class
    set :form_class, "flex flex-col gap-3"
    set :slot_class, ""
    set :button_text, "Reset password"
    set :disable_button_text, "Resetting…"
  end

  override Components.Password.Input do
    set :field_class, "flex flex-col gap-1"
    set :label_class, "text-[11px] uppercase tracking-[0.08em] text-inkSoft font-semibold"
    set :input_class, @input_class
    set :input_class_with_error, @input_class <> " border-red"
    set :submit_class, @primary_button <> " mt-2"
    set :error_ul, "text-[12px] text-red mt-1"
    set :error_li, ""
    set :identity_input_label, "Email"
    set :password_input_label, "Password"
    set :password_confirmation_input_label, "Confirm"
    set :identity_input_placeholder, "you@example.com"
    set :input_debounce, 350
  end
end
