defmodule ColtWeb.PrivacyLive do
  use ColtWeb, :live_view

  alias ColtWeb.Components.Legal

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Privacy Policy"))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} landing={true}>
      <Legal.page kicker="Liid · legal" title="Privacy Policy" updated="8 June 2026">
        <Legal.section title="Who we are">
          <p>
            Liid is a lead-generation and email-outreach product operated by <strong>Täp OÜ</strong>
            (Estonian registry code <strong>12125250</strong>),
            registered in Tallinn, Estonia ("Liid", "we", "us"). Täp OÜ is the
            <strong>data controller</strong>
            for the personal data described in this policy.
          </p>
          <p>
            For any privacy question, request, or complaint, contact us at <a href="mailto:liid@krister.ee">liid@krister.ee</a>.
          </p>
        </Legal.section>

        <Legal.section n="1" title="What this policy covers">
          <p>
            This policy explains what personal data Liid processes, why, on what legal
            basis, who we share it with, and the rights you have. It covers two distinct
            categories of people:
          </p>
          <ul>
            <li>
              <strong>Our users</strong> — the people who sign up for Liid, connect their
              mailboxes, and run outreach campaigns.
            </li>
            <li>
              <strong>Prospects</strong> — the business contacts our users research and email
              through the service. We process their data as a <strong>processor</strong> on
              our users' behalf; the user is the controller for that outreach.
            </li>
          </ul>
        </Legal.section>

        <Legal.section n="2" title="Data we collect">
          <h3>Account data</h3>
          <p>
            Your name and email address when you register, and authentication metadata. We
            never see or store passwords for third-party providers.
          </p>

          <h3>Connected mailbox data</h3>
          <p>
            When you connect a Gmail, Microsoft 365, or IMAP mailbox, the OAuth tokens that
            authorise access are held by our email-infrastructure provider, <strong>Nylas</strong>
            (EU/UK region) — <strong>Liid never receives or stores your
              mailbox password or OAuth tokens.</strong>
            We store only an opaque connection
            identifier, the mailbox address, and its display name. Through that connection we:
          </p>
          <ul>
            <li>send the outbound emails and follow-ups you approve;</li>
            <li>
              read inbound replies to those threads so we can show the conversation and stop sequences when someone responds;
            </li>
            <li>detect bounce and delivery notifications to protect sender reputation.</li>
          </ul>

          <h3>Campaign &amp; message content</h3>
          <p>
            Email drafts, subjects and bodies (AI-generated and your edits), sent messages,
            inbound replies, and notes — stored so we can display threads and improve the
            drafts we generate for you.
          </p>

          <h3>Prospect data</h3>
          <p>
            Company and business-contact information (company name, industry, size, public
            business email addresses, job titles) gathered during enrichment to build your
            target lists.
          </p>

          <h3>Billing data</h3>
          <p>
            Subscription and payment processing is handled by <strong>Stripe</strong>. We do
            not store full card numbers; we keep a customer reference and your plan status.
          </p>

          <h3>Technical data</h3>
          <p>
            Standard server logs (IP address, browser, timestamps) and a session cookie
            required to keep you signed in.
          </p>
        </Legal.section>

        <Legal.section n="3" title="Google user data &amp; Limited Use">
          <p>
            Where you connect a Google (Gmail / Google Workspace) account, Liid's access to
            and use of information received from Google APIs adheres to the <a
              href="https://developers.google.com/terms/api-services-user-data-policy"
              target="_blank"
              rel="noopener"
            >
              Google API Services User Data Policy</a>, including the
            <strong>Limited Use</strong>
            requirements. Specifically:
          </p>
          <ul>
            <li>
              We use Gmail data <strong>only</strong> to provide and improve the user-facing
              features described above — sending your approved messages, threading replies,
              classifying replies, and detecting bounces.
            </li>
            <li>
              We <strong>do not</strong> transfer Gmail data to others except as necessary to
              provide or improve those features, to comply with applicable law, or as part of
              a merger or acquisition with appropriate notice.
            </li>
            <li>
              We <strong>do not</strong> use Gmail data for advertising, and we do not sell it.
            </li>
            <li>
              We <strong>do not</strong> allow humans to read your Gmail data, except: with
              your explicit consent (e.g. when you ask for support); where necessary for
              security purposes such as investigating abuse; to comply with applicable law; or
              where the data has been aggregated and anonymised.
            </li>
          </ul>
          <p>
            Reply classification and draft generation are performed by an automated AI service
            (see §4). Email content sent to that service is used solely to deliver these
            user-facing features and is not used to train third-party models.
          </p>
        </Legal.section>

        <Legal.section n="4" title="Who we share data with (sub-processors)">
          <p>
            We share data only with the service providers needed to run Liid. Each acts as our
            processor under data-processing terms consistent with the GDPR.
          </p>
          <ul>
            <li>
              <strong>Nylas</strong> — email connectivity and mailbox sync (EU/UK data region).
              Holds the mailbox OAuth grant and relays send/read operations.
            </li>
            <li>
              <strong>Anthropic, accessed via OpenRouter</strong> — generates email drafts and
              classifies inbound replies. Receives the message content needed for that task;
              does not use it to train models.
            </li>
            <li>
              <strong>Stripe</strong> — subscription billing and payment processing.
            </li>
            <li>
              <strong>Our cloud hosting and database provider</strong> — stores application
              data on infrastructure located in the EU.
            </li>
          </ul>
          <p>
            We do not sell personal data or share it for advertising.
          </p>
        </Legal.section>

        <Legal.section n="5" title="Legal bases (GDPR)">
          <ul>
            <li><strong>Contract</strong> — to provide the service you signed up for.</li>
            <li>
              <strong>Legitimate interests</strong>
              — to operate, secure and improve Liid, and to enable B2B outreach to business contacts.
            </li>
            <li>
              <strong>Consent</strong>
              — where you explicitly connect a mailbox or grant a specific permission.
            </li>
            <li>
              <strong>Legal obligation</strong> — to meet accounting, tax and legal requirements.
            </li>
          </ul>
        </Legal.section>

        <Legal.section n="6" title="International transfers">
          <p>
            We host application data in the EU. Our email provider Nylas operates in its
            EU/UK region, which may store data in the United Kingdom — a transfer covered by
            the UK adequacy decision. Where any provider processes data outside the EU/EEA,
            that transfer is covered by an adequacy decision or by Standard Contractual Clauses
            with appropriate safeguards.
          </p>
        </Legal.section>

        <Legal.section n="7" title="Retention">
          <p>
            We keep account and campaign data for as long as your account is active. When you
            disconnect a mailbox we revoke the connection and delete the stored connection
            identifier. When you close your account we delete or anonymise your personal data
            within 90 days, except where we must retain records to meet legal obligations.
          </p>
        </Legal.section>

        <Legal.section n="8" title="Your rights">
          <p>
            Under the GDPR you may request access to, correction of, deletion of, or a portable
            copy of your personal data, and you may object to or restrict certain processing.
            To exercise any right, email <a href="mailto:liid@krister.ee">liid@krister.ee</a>.
            You also have the right to lodge a complaint with the Estonian Data Protection
            Inspectorate (<em>Andmekaitse Inspektsioon</em>) or your local supervisory authority.
          </p>
          <p>
            If you are a prospect contacted through Liid and wish to be removed, you may reply
            to the email asking to opt out, or contact us directly and we will route your
            request to the relevant user.
          </p>
        </Legal.section>

        <Legal.section n="9" title="Security">
          <p>
            We apply industry-standard safeguards: encryption in transit, restricted access on
            a need-to-know basis, and storage of mailbox credentials with a specialised
            provider rather than in our own systems.
          </p>
        </Legal.section>

        <Legal.section n="10" title="Changes to this policy">
          <p>
            We may update this policy as the product evolves. Material changes will be
            reflected by the "last updated" date above and, where appropriate, notified to you.
          </p>
        </Legal.section>
      </Legal.page>
    </Layouts.app>
    """
  end
end
