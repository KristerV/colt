defmodule ColtWeb.TermsLive do
  use ColtWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Terms of Service"))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} landing={true}>
      <.legal_page kicker="Liid · legal" title="Terms of Service" updated="8 June 2026">
        <.legal_section title="Agreement">
          <p>
            These Terms of Service ("Terms") govern your use of Liid, a lead-generation and
            email-outreach service operated by <strong>Täp OÜ</strong>
            (Estonian registry code <strong>12125250</strong>), registered in Tallinn, Estonia ("Liid", "we", "us"). By
            creating an account or using the service you agree to these Terms. If you do not
            agree, do not use Liid.
          </p>
        </.legal_section>

        <.legal_section n="1" title="The service">
          <p>
            Liid helps you research business prospects, draft outreach emails with AI assistance,
            and send sequenced campaigns from your own connected mailboxes. Liid is currently
            offered on an <strong>invite-only beta</strong> basis and is provided "as is"; features
            may change, and availability is not guaranteed.
          </p>
        </.legal_section>

        <.legal_section n="2" title="Accounts">
          <p>
            You are responsible for keeping your account credentials secure and for all activity
            under your account. You must provide accurate information and be at least 18 years old
            and acting on behalf of a business.
          </p>
        </.legal_section>

        <.legal_section n="3" title="Connected mailboxes">
          <p>
            When you connect a mailbox (Gmail, Microsoft 365, or IMAP), you authorise Liid to send
            messages you approve and to read replies to those messages on your behalf. You may
            disconnect a mailbox at any time, which revokes that access. You are responsible for
            complying with the terms of your email provider.
          </p>
        </.legal_section>

        <.legal_section n="4" title="Acceptable use">
          <p>You agree <strong>not</strong> to use Liid to:</p>
          <ul>
            <li>
              send unsolicited bulk email (spam), or messages to recipients from whom consent is required but not held;
            </li>
            <li>send deceptive, fraudulent, harassing, or unlawful content;</li>
            <li>impersonate any person or misrepresent your affiliation;</li>
            <li>
              violate any applicable anti-spam, data-protection, or marketing law, including the GDPR and the ePrivacy rules of the recipient's jurisdiction;
            </li>
            <li>
              circumvent sending limits, security controls, or the rate limits of any email provider.
            </li>
          </ul>
          <p>
            You are solely responsible for the content of your outreach and for having a lawful
            basis to contact each recipient. You must honour opt-out requests promptly. We may
            suspend or terminate accounts that breach this section.
          </p>
        </.legal_section>

        <.legal_section n="5" title="Your data &amp; privacy">
          <p>
            Our handling of personal data is described in our <.link navigate={~p"/privacy"}>Privacy Policy</.link>. As between you and Liid, you
            retain ownership of the content and prospect data you bring to or generate in the
            service. You grant us the rights needed to host and process that data to provide the
            service.
          </p>
        </.legal_section>

        <.legal_section n="6" title="AI-generated content">
          <p>
            Liid uses AI to draft emails and classify replies. AI output may be inaccurate; you are
            responsible for reviewing and approving any message before it is sent. We make no
            warranty as to the suitability of AI-generated drafts.
          </p>
        </.legal_section>

        <.legal_section n="7" title="Fees">
          <p>
            Paid plans, where offered, are billed through Stripe according to the pricing shown at
            sign-up. Fees are stated in EUR and exclude VAT unless noted. You can cancel from the
            billing portal; cancellation stops future charges but does not refund the current
            period unless required by law.
          </p>
        </.legal_section>

        <.legal_section n="8" title="Intellectual property">
          <p>
            Liid, including its software, design, and brand, is owned by Täp OÜ. These Terms grant
            you a limited, non-exclusive, non-transferable right to use the service. You may not
            copy, resell, reverse-engineer, or create derivative works from the service.
          </p>
        </.legal_section>

        <.legal_section n="9" title="Disclaimers">
          <p>
            The service is provided "as is" and "as available" without warranties of any kind,
            whether express or implied, to the maximum extent permitted by law. We do not warrant
            that the service will be uninterrupted, error-free, or that any outreach will achieve a
            particular result.
          </p>
        </.legal_section>

        <.legal_section n="10" title="Limitation of liability">
          <p>
            To the maximum extent permitted by law, Liid and Täp OÜ are not liable for indirect,
            incidental, or consequential damages, or for loss of profits, data, or goodwill. Our
            total aggregate liability arising from the service is limited to the amount you paid us
            in the twelve months preceding the event giving rise to the claim, or €100 if no fees
            were paid.
          </p>
        </.legal_section>

        <.legal_section n="11" title="Indemnity">
          <p>
            You agree to indemnify and hold Liid and Täp OÜ harmless from claims arising out of your
            use of the service, your outreach content, or your breach of these Terms or of
            applicable law.
          </p>
        </.legal_section>

        <.legal_section n="12" title="Suspension &amp; termination">
          <p>
            You may stop using Liid and close your account at any time. We may suspend or terminate
            access if you breach these Terms, create risk for us or other users, or fail to pay
            fees. On termination your right to use the service ends and we handle your data per the
            Privacy Policy.
          </p>
        </.legal_section>

        <.legal_section n="13" title="Governing law">
          <p>
            These Terms are governed by the laws of <strong>Estonia</strong>, without regard to
            conflict-of-law rules. Disputes are subject to the exclusive jurisdiction of the courts
            of Estonia, without prejudice to any mandatory consumer-protection rights you may have.
          </p>
        </.legal_section>

        <.legal_section n="14" title="Changes">
          <p>
            We may update these Terms as the product evolves. Material changes will be reflected by
            the "last updated" date above. Continued use after changes take effect constitutes
            acceptance.
          </p>
        </.legal_section>

        <.legal_section n="15" title="Contact">
          <p>
            Questions about these Terms: <a href="mailto:liid@krister.ee">liid@krister.ee</a>.
          </p>
        </.legal_section>
      </.legal_page>
    </Layouts.app>
    """
  end

  attr :kicker, :string, required: true
  attr :title, :string, required: true
  attr :updated, :string, required: true
  slot :inner_block, required: true

  def legal_page(assigns) do
    ~H"""
    <div class="max-w-[760px] mx-auto w-full">
      <article class="bg-card border border-border rounded-[11px] [box-shadow:var(--shadow-card)] px-6 py-9 md:px-12 md:py-14">
        <header class="pb-7 mb-8 border-b border-border">
          <div class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold mb-3">
            {@kicker}
          </div>
          <h1 class="font-semibold text-[28px] md:text-[34px] leading-[1.1] tracking-[-0.02em] m-0 text-ink text-pretty">
            {@title}
          </h1>
          <p class="mt-3 text-[12px] text-inkFaint tabular-nums m-0">
            Last updated {@updated}
          </p>
        </header>
        <div class="space-y-9">
          {render_slot(@inner_block)}
        </div>
      </article>
    </div>
    """
  end

  attr :n, :string, default: nil
  attr :title, :string, required: true
  slot :inner_block, required: true

  def legal_section(assigns) do
    ~H"""
    <section class="space-y-3">
      <h2 class="font-semibold text-[18px] md:text-[20px] tracking-[-0.01em] text-ink m-0 scroll-mt-24">
        <span :if={@n} class="text-inkFaint mr-2 tabular-nums">{@n}</span>{@title}
      </h2>
      <div class={[
        "text-[15px] leading-[1.65] text-inkSoft space-y-3",
        "[&_a]:text-accent [&_a]:no-underline hover:[&_a]:underline",
        "[&_strong]:text-ink [&_strong]:font-semibold",
        "[&_ul]:list-disc [&_ul]:pl-5 [&_ul]:space-y-1.5 [&_li]:marker:text-inkFaint",
        "[&_h3]:text-ink [&_h3]:font-semibold [&_h3]:text-[15px] [&_h3]:mt-5 [&_h3]:mb-1"
      ]}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
