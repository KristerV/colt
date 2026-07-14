# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_oban, pro?: false

# Nylas v3 base URL (default EU per docs/email-sending.md §0).
# Override in dev.secrets.exs or via NYLAS_API_URI in prod when on a different region.
config :colt, :nylas, api_uri: "https://api.eu.nylas.com"

# LLM model per tier. Single place to swap models — see Colt.Services.Ai.Complete.
config :colt, :ai,
  models: [
    cheap: "z-ai/glm-4.7",
    smart: "google/gemini-3.5-flash"
  ]

# Canonical list of markets — the single source of truth. The landing page, the
# campaign country picker, the `market` enum on Company, the contact form's
# market select, /admin/countries and the ingest cron schedule all derive from
# this; nothing re-lists countries anywhere else.
#
# `available: false` means "declared but not offered": the market keeps its enum
# slot, registry links and its monthly ingest, but is greyed out on the landing
# and absent from the campaign picker. This is the intended path for a new
# registry — let it ingest and fill up while hidden, watch the counts on
# /admin/countries, then flip the flag. Only flip once rows have landed *in
# prod*: an available market with no data shows users an empty result set.
#
# `job` is the monthly ingest (see the Oban crontab below); `job: nil` means the
# market simply isn't scheduled, so an unwritten ingest can't be half-wired.
#
# `language` / `language_name` drive the writer's per-template language picker.
markets = [
  %{
    code: "EE",
    name: "Estonia",
    api: "rik.ee",
    market: :ee,
    available: true,
    language: "et",
    language_name: "Estonian",
    job: Colt.Jobs.Ingest.Ee
  },
  %{
    code: "FI",
    name: "Finland",
    api: "ytj.fi",
    market: :fi,
    available: true,
    language: "fi",
    language_name: "Finnish",
    job: Colt.Jobs.Ingest.Fi
  },
  %{
    code: "LV",
    name: "Latvia",
    api: "ur.gov.lv",
    market: :lv,
    available: true,
    language: "lv",
    language_name: "Latvian",
    job: Colt.Jobs.Ingest.Lv
  },
  %{
    code: "LT",
    name: "Lithuania",
    api: "registrucentras.lt",
    market: :lt,
    available: true,
    language: "lt",
    language_name: "Lithuanian",
    job: Colt.Jobs.Ingest.Lt
  },
  %{
    code: "NO",
    name: "Norway",
    api: "brreg.no",
    market: :no,
    available: true,
    language: "nb",
    language_name: "Norwegian",
    job: Colt.Jobs.Ingest.No
  },
  # Ingest is written and verified in dev, but prod has zero rows — leaving this
  # available offered users an empty Denmark in the campaign picker.
  %{
    code: "DK",
    name: "Denmark",
    api: "datacvr.dk",
    market: :dk,
    available: false,
    language: "da",
    language_name: "Danish",
    job: Colt.Jobs.Ingest.Dk
  },
  # Blocked on Bolagsverket OAuth client credentials (human-issued, form-gated).
  %{
    code: "SE",
    name: "Sweden",
    api: "bolagsverket.se",
    market: :se,
    available: false,
    language: "sv",
    language_name: "Swedish",
    job: Colt.Jobs.Ingest.Se
  },
  # No ingest yet: KRS has no revenue/employees, eKRS bulk is Incapsula-gated.
  %{
    code: "PL",
    name: "Poland",
    api: "krs.gov.pl",
    market: :pl,
    available: false,
    language: "pl",
    language_name: "Polish",
    job: nil
  }
]

config :colt, :markets, markets

# Monthly registry ingests, derived from the market list above so the schedule
# can't drift from the countries we declare. Availability deliberately doesn't
# gate this: a market ingests as soon as it has a job, which is what lets a new
# registry fill up before anyone can select it.
#
# Every ingest fires at once because they all run on the :registry queue, which
# has concurrency 1 — they queue on insert and drain one at a time. Spreading
# them across the morning only reordered that queue; the registries are separate
# national APIs with nothing shared to spread load across. Give a market its own
# time only if its source actually publishes on a different schedule.
ingest_cron = "0 3 1 * *"

ingest_crontab = for %{job: job} <- markets, job != nil, do: {ingest_cron, job}

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :colt, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10, registry: 1, scrape: 4, ai: 5, export: 1, sending: 4, ai_writer: 4],
  repo: Colt.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 3},
    {Oban.Plugins.Cron,
     crontab:
       ingest_crontab ++
         [
           {"* * * * *", Colt.Jobs.SendDueEmails},
           {"0 * * * *", Colt.Jobs.AutoApproveDue},
           {"* * * * *", Colt.Jobs.PollInbounds},
           {"*/10 * * * *", Colt.Jobs.PollTracking},
           {"0 6 * * *", Colt.Jobs.SyncRevenue}
         ]}
  ]

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :colt,
  ecto_repos: [Colt.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Colt.Accounts, Colt.Domain],
  rik_ee_cache_dir: "priv/ingest_cache",
  prh_fi_cache_dir: "priv/ingest_cache_fi",
  ur_lv_cache_dir: "priv/ingest_cache_lv",
  rc_lt_cache_dir: "priv/ingest_cache_lt_rc",
  cvr_dk_cache_dir: "priv/ingest_cache_dk",
  brreg_no_cache_dir: "priv/ingest_cache_no",
  ingest_max_years: 3,
  topup_max_sample: 1000,
  topup_min_batch: 10,
  ash_authentication: [return_error_on_invalid_magic_link_token?: true],
  discord_webhook_url: nil

# Configure the endpoint
config :colt, ColtWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ColtWeb.ErrorHTML, json: ColtWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Colt.PubSub,
  live_view: [signing_salt: "YtXVB52X"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :colt, Colt.Mailer, adapter: Swoosh.Adapters.Local

config :colt, :mail_from, {"Liid", "noreply@mg.liid.ee"}

# Billing — Stripe price-id → monthly enriched-contact capacity. Populated from
# env vars in runtime.exs for prod. Dev/test override via dev.secrets.exs.
config :colt, Colt.Billing, price_capacity: %{}

config :stripity_stripe, api_key: System.get_env("STRIPE_SECRET_KEY", "")

config :colt, ColtWeb.Gettext,
  locales: ~w(en et lv lt fi sv nb da is),
  default_locale: "en"

# TLD → locale. .com / unknown → en. .no maps to nb (canonical Norwegian).
config :colt, :locales,
  tld_map: %{
    "ee" => "et",
    "lv" => "lv",
    "lt" => "lt",
    "fi" => "fi",
    "se" => "sv",
    "no" => "nb",
    "dk" => "da",
    "is" => "is"
  },
  available: ~w(en et lv lt fi sv nb da is),
  default: "en"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  colt: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  colt: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
