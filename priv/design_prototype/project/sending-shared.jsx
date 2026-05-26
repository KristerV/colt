// Liid — Sending half · shared chrome
//
// CALL-OUTS (spec-vs-design conflicts I noticed in the brief):
//
//  · The brief says the sidebar "replaces the current top stepper for
//    campaign routes" — i.e. once you're inside a campaign, sidebar is the
//    only chrome. I've designed the sidebar to expose BOTH the ENRICHMENT
//    routes (the linear setup flow you've already shipped) and the SENDING
//    routes, on the assumption that after enrichment completes, the linear
//    stepper retires and users can revisit any of those steps from the
//    sidebar. If the stepper should stay for ENRICHMENT and the sidebar
//    only shows SENDING + ACCOUNT, easy swap.
//
//  · "Panic-switch toggle lives in the SENDING section header" — I've put
//    it inline-right of the SENDING label. The toggle is the off-state; the
//    red banner below is the on-state. Both states are present in the
//    artboard collection (sidebar-collapsed-panic and the funnel/writing
//    artboards show the banner when panic_on).
//
//  · Cross-domain auto-attached reply — surfaced as a small mono chip on
//    the inbound message ("auto-attached · different domain") plus a
//    "detach" affordance in the message's hover menu. Not in the brief's
//    spec citations but called out as "things to surface, not solve
//    silently".

// ── Sending-side seed data ─────────────────────────────────────────────
const LIID_SENDING_DATA = {
  campaign: { name: 'Nordic CTOs Q2', id: 'nctos-q2', enriched: 312, written: 188, sent: 142 },

  // Current focused contact in the writing view
  focusContact: {
    name: 'Mart Tamm',
    title: 'CTO',
    company: 'Pipedrive AS',
    domain: 'pipedrive.com',
    email: 'm.tamm@pipedrive.com',
    industry: 'SaaS · CRM',
    size: 920,
    growth: '2x',
    city: 'Tallinn',
    icpScore: 0.86,
    icpReason: 'Engineering-led B2B SaaS, EU-based, 50–500 band, shipped public API rewrite in Mar 2026.',
    summary: 'Pipedrive builds CRM software for B2B sales teams. Founded 2010 in Tallinn, ~920 employees across 10 offices, primary markets US and EU mid-market. Engineering org is ~40% of headcount, polyrepo on Buildkite CI, public engineering blog posts ~monthly. Acquired by Vista Equity in 2020 at €1.5B valuation.',
    snippet: '"Mart spent 6 years at Skype before joining Pipedrive. Posts about build-time regressions and developer happiness on LinkedIn ~2x/month."',
  },

  // 3-step sequence drafts for focus contact
  sequenceDraft: [
    {
      step: 1, status: 'drafted', waitDays: 0,
      subject: 'build times at pipedrive after the API rewrite',
      body: `Hi Mart,\n\nSaw your Mar 14 post on the Pipedrive engineering blog about the API rewrite — particularly the bit on test suite times creeping past 22min on CI.\n\nWe build observability for monorepos at that exact band — 50–500 engineers, polyrepo with a fat shared kernel. Customers see 35–60% wall-clock drop on the CI critical path within 3 weeks.\n\nWorth 15 min next week? I can show you what your build graph would look like before you commit to anything.\n\n— Karl`,
    },
    {
      step: 2, status: 'drafted', waitDays: 4,
      subject: 're: build times at pipedrive after the API rewrite',
      body: `Mart — bumping this in case it slipped past inbox triage.\n\nQuick context, since the original email was vague: we plug into your existing CI (you're on Buildkite, right?) and surface the regression-per-commit graph. No agents on developer machines.\n\nHappy to send a 90-second loom instead of taking a meeting if that's easier.`,
    },
    {
      step: 3, status: 'drafted', waitDays: 7,
      subject: 'last note',
      body: `Mart, last one from me. If build-time is solved or not a priority right now, totally fine — I'll close the loop here.\n\nIf there's a better person on your platform team to talk to, would appreciate a redirect.`,
    },
  ],

  // Inbox preview — 4 unread items; our drafted email blends in at row 3
  inbox: [
    { from: 'Mart Tamm',     subj: 'Re: Q2 platform review · pushed to Thu',                 preview: 'Liis, sorry for the late notice — I want to fold in the buildkite migration findings before we sit down.', when: '08:42', read: false },
    { from: 'Linear',        subj: 'You were mentioned in PIP-1842 by tonis',                 preview: '@m.tamm could you take a look at the staging deploy retry logic? It\'s been flaky since the API rewrite landed.', when: '08:31', read: false },
    { from: 'Karl Soosalu',  subj: 'build times at pipedrive after the API rewrite',          preview: 'Hi Mart, Saw your Mar 14 post on the Pipedrive engineering blog about the API rewrite — particularly the bit on…', when: '07:58', read: false, isDraft: true },
    { from: 'GitHub',        subj: '[pipedrive/core] PR #4012 ready for review',              preview: 'build green · 1 approving review required · 2 files changed · +147 −38 · @platform-team', when: '07:14', read: false },
  ],

  // Stats for sending funnel
  stats: { replyRate: 14.2, interestRate: 6.1, totalSent: 412, dailyAvg: 38, bounceRate: 1.8 },

  // Buckets for sending funnel
  buckets: [
    { k: 'pending',   label: 'Pending approval', n: 46 },
    { k: 'step1',     label: 'Step 1 sent',      n: 98 },
    { k: 'step2',     label: 'Step 2 sent',      n: 71 },
    { k: 'step3',     label: 'Step 3 sent',      n: 52 },
    { k: 'callready', label: 'Call ready',       n: 14, accent: true },
    { k: 'replied-y', label: 'Replied · interested',     n: 18, accent: true },
    { k: 'replied-n', label: 'Replied · not interested', n: 23 },
    { k: 'replied-o', label: 'Replied · OOO',            n: 7 },
    { k: 'noreply',   label: 'No reply',         n: 89 },
    { k: 'bounced',   label: 'Bounced',          n: 9, warn: true },
    { k: 'failed',    label: 'Failed',           n: 3, fail: true },
  ],

  // Sending accounts — globally connected at the user/workspace level.
  // The per-inbox daily quota is GLOBAL (one number for every account)
  // and lives in the user-level Email accounts view.
  perAccountDaily: 15,
  sendingAccounts: [
    { addr: 'karl@liid-outreach.com',   status: 'active',       campaigns: 2, sent: 1240, replyRate: 16.4, bounceRate: 1.2, selectedForCampaign: true },
    { addr: 'karl@liid-mail.com',       status: 'active',       campaigns: 1, sent: 820,  replyRate: 12.1, bounceRate: 2.0, selectedForCampaign: true },
    { addr: 'k.soosalu@liid-go.com',    status: 'active',       campaigns: 3, sent: 1560, replyRate: 14.8, bounceRate: 1.7, selectedForCampaign: true },
    { addr: 'karl@liid-reach.io',       status: 'paused',       campaigns: 1, sent: 384,  replyRate: 8.6,  bounceRate: 4.2, selectedForCampaign: false, reason: 'Manual pause · Mar 22' },
    { addr: 'karl@liid-direct.co',      status: 'disconnected', campaigns: 2, sent: 612,  replyRate: 11.0, bounceRate: 2.4, selectedForCampaign: true, reason: 'OAuth expired · re-auth needed' },
    { addr: 'hello@karl-soosalu.com',   status: 'active',       campaigns: 1, sent: 290,  replyRate: 18.2, bounceRate: 0.7, selectedForCampaign: false },
  ],

  // Sidebar nav
  navWorkspace: [
    { id: 'campaigns',      label: 'Campaigns', icon: 'grid' },
    { id: 'email-accounts', label: 'Email accounts',  icon: 'mail' },
    { id: 'billing',        label: 'Billing',   icon: 'file' },
  ],
  navEnrichment: [
    { id: 'name',    label: 'Name',     icon: 'file' },
    { id: 'icp',     label: 'ICP',      icon: 'user' },
    { id: 'market',  label: 'Market',   icon: 'globe' },
    { id: 'filters', label: 'Filters',  icon: 'filter' },
    { id: 'funnel',  label: 'Funnel',   icon: 'grid' },
  ],
  navSending: [
    { id: 'sequence',  label: 'Sequence',         icon: 'code' },
    { id: 'accounts',  label: 'Sending accounts', icon: 'mail' },
    { id: 'writing',   label: 'Writing',          icon: 'spark' },
    { id: 'sf',        label: 'Sending funnel',   icon: 'grid' },
  ],
};
window.LIID_SENDING_DATA = LIID_SENDING_DATA;

// ── Sidebar ────────────────────────────────────────────────────────────
function LiidSidebar({ accent, active = 'writing', collapsed = false, panicOn = false }) {
  const W = collapsed ? 56 : 240;
  return (
    <div style={{
      width: W, flexShrink: 0, height: '100%',
      borderRight: `1px solid ${liidTokens.rule}`,
      background: liidTokens.paper,
      display: 'flex', flexDirection: 'column',
      fontFamily: liidTokens.sans,
    }}>
      {/* Wordmark */}
      <div style={{
        padding: collapsed ? '20px 0' : '20px 22px',
        borderBottom: `1px solid ${liidTokens.rule}`,
        display: 'flex', alignItems: 'center',
        justifyContent: collapsed ? 'center' : 'flex-start',
      }}>
        {collapsed ? (
          <span style={{
            fontFamily: liidTokens.serif, fontSize: 22, lineHeight: 1, color: liidTokens.ink,
          }}>L<span style={{ color: accent }}>.</span></span>
        ) : (
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 5 }}>
            <span style={{ fontFamily: liidTokens.serif, fontSize: 24, lineHeight: 1, letterSpacing: -0.4 }}>Liid</span>
            <span style={{ width: 5, height: 5, borderRadius: 999, background: accent, display: 'inline-block', transform: 'translateY(-2px)' }} />
          </div>
        )}
      </div>

      <div style={{ flex: 1, overflow: 'auto' }} className="liid-scroll">
        {/* Workspace nav — top-level routes outside any campaign */}
        <SidebarSection
          items={LIID_SENDING_DATA.navWorkspace}
          active={active}
          accent={accent}
          collapsed={collapsed}
          variant="workspace"
        />

        {/* Campaign scope header */}
        <CampaignScopeHeader collapsed={collapsed} accent={accent} />

        {/* Campaign-scoped sections */}
        <SidebarSection label="Enrichment" collapsed={collapsed} items={LIID_SENDING_DATA.navEnrichment} active={active} accent={accent} scoped />
        <SidebarSection label="Sending" collapsed={collapsed} items={LIID_SENDING_DATA.navSending} active={active} accent={accent} scoped
          headerExtra={<PanicSwitch on={panicOn} accent={accent} collapsed={collapsed} />} />
      </div>

      {/* User chip */}
      <div style={{
        padding: collapsed ? '14px 0' : '14px 18px',
        borderTop: `1px solid ${liidTokens.rule}`,
        display: 'flex', alignItems: 'center',
        justifyContent: collapsed ? 'center' : 'flex-start',
        gap: 10,
      }}>
        <div style={{
          width: 26, height: 26, borderRadius: 999, background: liidTokens.ink,
          color: liidTokens.paper, display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 11, fontWeight: 600, flexShrink: 0,
        }}>K</div>
        {!collapsed && (
          <div style={{ minWidth: 0 }}>
            <div style={{ fontSize: 12, color: liidTokens.ink, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>Karl Soosalu</div>
            <div style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, marginTop: 1 }}>karl@liid.studio</div>
          </div>
        )}
      </div>
    </div>
  );
}

// ── Campaign scope header ─────────────────────────────────────────────
// Marks the start of the campaign-scoped portion of the sidebar.
// Everything below this header (ENRICHMENT + SENDING) is scoped to the
// chosen campaign; everything above (Campaigns / Accounts / Billing) is
// workspace-level.
function CampaignScopeHeader({ collapsed, accent }) {
  if (collapsed) {
    return (
      <div style={{
        margin: '6px 12px',
        padding: '10px 0',
        borderTop: `1px solid ${liidTokens.rule}`,
        borderBottom: `1px solid ${liidTokens.rule}`,
        display: 'flex', justifyContent: 'center',
      }} title="Nordic CTOs Q2">
        <span style={{
          width: 26, height: 26, borderRadius: 2,
          background: liidTokens.ink,
          color: liidTokens.paper,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontFamily: liidTokens.serif, fontSize: 15, letterSpacing: -0.2, lineHeight: 1,
          position: 'relative',
        }}>
          N
          <span style={{
            position: 'absolute', bottom: -1, right: -1,
            width: 5, height: 5, borderRadius: 999, background: accent,
            boxShadow: `0 0 0 1.5px ${liidTokens.paper}`,
          }} />
        </span>
      </div>
    );
  }
  return (
    <div style={{
      padding: '16px 18px 12px',
      borderTop: `1px solid ${liidTokens.rule}`,
      borderBottom: `1px solid ${liidTokens.rule}`,
      background: liidTokens.paperAlt,
      marginBottom: 10,
    }}>
      <div style={{
        fontFamily: liidTokens.mono, fontSize: 9, letterSpacing: 0.14,
        textTransform: 'uppercase', color: liidTokens.ink40, marginBottom: 6,
      }}>Campaign</div>
      <button style={{
        display: 'flex', alignItems: 'center', gap: 8,
        width: '100%', padding: 0,
        background: 'transparent', border: 'none', cursor: 'pointer',
        textAlign: 'left',
      }}>
        <span style={{
          fontFamily: liidTokens.serif, fontSize: 20, color: liidTokens.ink,
          letterSpacing: -0.3, lineHeight: 1.1, flex: 1,
        }}>Nordic CTOs Q2</span>
        <LiidIcon name="chev" size={11} color={liidTokens.ink55} />
      </button>
      <div style={{
        marginTop: 6, display: 'flex', alignItems: 'center', gap: 10,
        fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, letterSpacing: 0.04,
      }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
          <span style={{ width: 5, height: 5, borderRadius: 999, background: accent }} />
          312 enriched
        </span>
        <span>·</span>
        <span>142 sent</span>
      </div>
    </div>
  );
}

function SidebarSection({ label, items, active, accent, collapsed, headerExtra, variant = 'default' }) {
  return (
    <div style={{
      marginBottom: variant === 'workspace' ? 6 : 14,
      paddingTop: variant === 'workspace' ? 12 : 0,
    }}>
      {!collapsed && label && (
        <div style={{
          padding: '6px 18px 6px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <span style={{
            fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14,
            textTransform: 'uppercase', color: liidTokens.ink40,
          }}>{label}</span>
          {headerExtra}
        </div>
      )}
      {!collapsed && !label && headerExtra && (
        <div style={{ padding: '6px 18px 6px', display: 'flex', justifyContent: 'flex-end' }}>{headerExtra}</div>
      )}
      {collapsed && headerExtra && (
        <div style={{ display: 'flex', justifyContent: 'center', padding: '2px 0 4px' }}>{headerExtra}</div>
      )}
      <div>
        {items.map((it) => {
          const isActive = it.id === active;
          return (
            <div key={it.id} title={collapsed ? it.label : undefined} style={{
              position: 'relative',
              display: 'flex', alignItems: 'center',
              gap: 10,
              padding: collapsed ? '8px 0' : '7px 18px 7px 18px',
              cursor: 'pointer',
              background: isActive ? liidTokens.paperAlt : 'transparent',
              justifyContent: collapsed ? 'center' : 'flex-start',
            }}>
              {isActive && (
                <span style={{
                  position: 'absolute', left: 0, top: 4, bottom: 4, width: 2, background: accent,
                }} />
              )}
              <LiidIcon name={it.icon} size={13} color={isActive ? liidTokens.ink : liidTokens.ink55} />
              {!collapsed && (
                <span style={{
                  fontSize: 13,
                  color: isActive ? liidTokens.ink : liidTokens.ink70,
                  fontWeight: isActive ? 500 : 400,
                }}>{it.label}</span>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function PanicSwitch({ on, accent, collapsed }) {
  // `on` (legacy name) means "panic engaged · sending halted".
  // We render an inverted toggle: ON = sending active, OFF = halted.
  const sendingOn = !on;
  if (collapsed) {
    return (
      <span title={sendingOn ? 'Sending on' : 'Sending paused'} style={{
        position: 'relative', display: 'inline-block',
        width: 22, height: 12, borderRadius: 999,
        background: sendingOn ? accent : liidTokens.ink20,
        transition: 'background .12s',
      }}>
        <span style={{
          position: 'absolute', top: 1, left: sendingOn ? 11 : 1,
          width: 10, height: 10, borderRadius: 999,
          background: liidTokens.paper,
          transition: 'left .12s',
        }} />
      </span>
    );
  }
  return (
    <span title={sendingOn ? 'Sending on · click to pause' : 'Sending paused · click to resume'} style={{
      position: 'relative', display: 'inline-block',
      width: 24, height: 13, borderRadius: 999,
      background: sendingOn ? accent : liidTokens.ink20,
      cursor: 'pointer',
      transition: 'background .12s',
    }}>
      <span style={{
        position: 'absolute',
        top: 1, left: sendingOn ? 12 : 1,
        width: 11, height: 11, borderRadius: 999,
        background: liidTokens.paper,
        boxShadow: '0 1px 2px rgba(0,0,0,0.2)',
        transition: 'left .12s',
      }} />
    </span>
  );
}

// ── Panic banner ───────────────────────────────────────────────────────
function PanicBanner({ accent }) {
  return (
    <div style={{
      background: liidTokens.fail, color: liidTokens.paper,
      padding: '10px 24px',
      display: 'flex', alignItems: 'center', gap: 16,
      fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.06,
      borderBottom: `1px solid ${liidTokens.fail}`,
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 999, background: liidTokens.paper,
        animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
      <span style={{ textTransform: 'uppercase', fontWeight: 600, letterSpacing: 0.12 }}>Sending halted</span>
    </div>
  );
}

// ── Shell that uses sidebar instead of LiidTopBar ──────────────────────
function LiidShell({ children, accent, active, collapsed, panicOn }) {
  return (
    <div style={{
      width: '100%', height: '100%',
      display: 'flex',
      background: liidTokens.paper,
      color: liidTokens.ink,
      fontFamily: liidTokens.sans,
    }}>
      <LiidSidebar accent={accent} active={active} collapsed={collapsed} panicOn={panicOn} />
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', position: 'relative' }}>
        {panicOn && <PanicBanner accent={accent} />}
        <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>{children}</div>
      </div>
    </div>
  );
}

// ── Page header (inside main pane, replaces serif h1 from LiidScreen) ──
function PageHead({ kicker, title, sub, right }) {
  return (
    <div style={{
      padding: '28px 36px 22px',
      borderBottom: `1px solid ${liidTokens.rule}`,
      display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: 24,
    }}>
      <div>
        {kicker && (
          <div style={{
            fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14,
            textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 6,
          }}>{kicker}</div>
        )}
        <h1 style={{
          fontFamily: liidTokens.serif, fontWeight: 400,
          fontSize: 40, lineHeight: 1, letterSpacing: -0.8, margin: 0,
        }}>{title}</h1>
        {sub && (
          <div style={{ marginTop: 8, fontSize: 13, color: liidTokens.ink55, maxWidth: 540 }}>{sub}</div>
        )}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>{right}</div>
    </div>
  );
}

// ── Contact header card (used in writing + thread) ─────────────────────
function ContactHeaderCard({ contact, accent, dense = false }) {
  const c = contact;
  return (
    <div style={{
      border: `1px solid ${liidTokens.rule}`,
      borderRadius: 2,
      padding: dense ? '14px 18px' : '20px 24px',
      background: liidTokens.paper,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, flexWrap: 'wrap' }}>
        <span style={{ fontFamily: liidTokens.serif, fontSize: dense ? 24 : 30, letterSpacing: -0.5, color: liidTokens.ink, lineHeight: 1 }}>
          {c.name}
        </span>
        <span style={{ fontSize: 13, color: liidTokens.ink55 }}>{c.title}</span>
        <span style={{ width: 3, height: 3, borderRadius: 999, background: liidTokens.ink20, display: 'inline-block' }} />
        <span style={{ fontSize: 13, color: liidTokens.ink }}>{c.company}</span>
        <span style={{ width: 3, height: 3, borderRadius: 999, background: liidTokens.ink20, display: 'inline-block' }} />
        <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55 }}>{c.domain}</span>
      </div>
      {!dense && (
        <div style={{
          marginTop: 12, display: 'flex', gap: 18, alignItems: 'center', flexWrap: 'wrap',
          fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
        }}>
          <span><LiidIcon name="mail" size={10} color={liidTokens.ink55} /> &nbsp;{c.email}</span>
          <span>·</span>
          <span>{c.industry}</span>
          <span>·</span>
          <span>{c.size.toLocaleString()} ppl</span>
          <span>·</span>
          <span>{c.city}</span>
          <span style={{ marginLeft: 8, display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: accent }} />
            <span style={{ color: liidTokens.ink70 }}>icp {c.icpScore}</span>
          </span>
        </div>
      )}
      {!dense && (
        <div style={{
          marginTop: 18, paddingTop: 18,
          borderTop: `1px solid ${liidTokens.rule}`,
          display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 32,
        }}>
          <div>
            <div style={{
              fontFamily: liidTokens.mono, fontSize: 9, letterSpacing: 0.14,
              textTransform: 'uppercase', color: liidTokens.ink40, marginBottom: 8,
            }}>What they do</div>
            <div style={{ fontSize: 13, lineHeight: 1.55, color: liidTokens.ink70 }}>
              {c.summary}
            </div>
          </div>
          <div>
            <div style={{
              fontFamily: liidTokens.mono, fontSize: 9, letterSpacing: 0.14,
              textTransform: 'uppercase', color: liidTokens.ink40, marginBottom: 8,
            }}>Why we picked them</div>
            <div style={{ fontSize: 13, lineHeight: 1.55, color: liidTokens.ink70 }}>
              {c.icpReason}
            </div>
            {c.snippet && (
              <div style={{
                marginTop: 10, fontFamily: liidTokens.serif, fontStyle: 'italic',
                fontSize: 14, lineHeight: 1.5, color: liidTokens.ink55,
              }}>
                {c.snippet}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

Object.assign(window, {
  LIID_SENDING_DATA, LiidSidebar, PanicSwitch, PanicBanner, LiidShell, PageHead, ContactHeaderCard, CampaignScopeHeader,
});
