// View — Thread (right pane in sending funnel, also a route on its own)
// Vertical timeline, newest at bottom. Mixed message types:
//   · outbound — paper bg
//   · inbound  — paperAlt bg, sender chip
//   · note     — italic serif (internal)
//   · system   — mono one-liner
//
// Header has status badge + override dropdown + Stop sequence.
// Sticky composer with Reply / Note tabs.
//
// CALL-OUT: cross-domain auto-attached reply is surfaced as a small mono
// chip on the inbound message + "detach" affordance in hover menu. The
// brief doesn't specify what should happen when you detach (does the
// thread split? does the reply get moved to a different contact?) — needs
// product input.

const THREAD_SEED = [
  { kind: 'outbound', when: 'Mar 14 · 09:18', step: 1, from: 'karl@liid-outreach.com', to: 'm.tamm@pipedrive.com',
    subj: 'build times at pipedrive after the API rewrite',
    body: 'Hi Mart,\n\nSaw your Mar 14 post on the Pipedrive engineering blog about the API rewrite — particularly the bit on test suite times creeping past 22min on CI.\n\nWe build observability for monorepos at that exact band — 50–500 engineers, polyrepo with a fat shared kernel. Customers see 35–60% wall-clock drop on the CI critical path within 3 weeks.\n\nWorth 15 min next week?\n\n— Karl',
    opened: 3, clicked: false },
  { kind: 'outbound', when: 'Mar 18 · 09:00', step: 2, from: 'karl@liid-outreach.com', to: 'm.tamm@pipedrive.com',
    subj: 're: build times at pipedrive after the API rewrite',
    body: 'Mart — bumping this in case it slipped past inbox triage.\n\nQuick context, since the original email was vague: we plug into your existing CI (you\'re on Buildkite, right?) and surface the regression-per-commit graph. No agents on developer machines.\n\nHappy to send a 90-second loom instead of taking a meeting if that\'s easier.',
    opened: 1, clicked: true },
  { kind: 'note',     when: 'Mar 18 · 11:30', author: 'Karl', txt: 'They clicked the loom link but didn\'t reply. Going to wait it out to step 3 instead of switching channels.' },
  { kind: 'inbound',  when: 'Mar 19 · 16:42',
    from: 'Mart Tamm <mart@pipedriveofficial.com>',
    crossDomain: true, attachedTo: 'm.tamm@pipedrive.com',
    subj: 're: build times at pipedrive after the API rewrite',
    body: 'Karl — thanks for the patient nudges.\n\nWe\'re actually about to start scoping CI tooling for FY26. Can I bring our head of platform, Liis, onto a 30 min call next week? Buildkite is right.\n\nTuesday or Wednesday afternoon EET works.\n\n— M' },
  { kind: 'system',   when: 'Mar 19 · 16:42', txt: 'Sequence halted · reply detected · classified as interested (0.94)' },
];

function ViewThread({ accent, density, standalone = true }) {
  const C = LIID_SENDING_DATA.focusContact;
  return (
    <LiidShell accent={accent} active={standalone ? 'sf' : 'sf'}>
      {standalone && (
        <PageHead
          kicker="Sending funnel · Thread"
          title={<>Conversation with <em style={{ fontStyle: 'italic', color: accent }}>Mart Tamm</em>.</>}
          right={
            <>
              <LiidBtn small><LiidIcon name="chevL" size={11} /> Back to funnel</LiidBtn>
            </>
          }
        />
      )}
      <ThreadPane accent={accent} contact={C} />
    </LiidShell>
  );
}

function ThreadPane({ accent, contact, embedded = false }) {
  const C = contact;
  return (
    <div style={{
      flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column',
      background: liidTokens.paper,
      borderLeft: embedded ? `1px solid ${liidTokens.rule}` : 'none',
      position: 'relative',
    }}>
      {/* Thread header */}
      <div style={{
        padding: '16px 28px 14px',
        borderBottom: `1px solid ${liidTokens.rule}`,
        display: 'flex', alignItems: 'flex-start', gap: 16,
      }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, flexWrap: 'wrap' }}>
            <span style={{ fontFamily: liidTokens.serif, fontSize: 24, letterSpacing: -0.4, color: liidTokens.ink, lineHeight: 1 }}>
              {C.name}
            </span>
            <span style={{ fontSize: 12, color: liidTokens.ink55 }}>{C.title} · {C.company}</span>
            <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40 }}>{C.email}</span>
          </div>
        </div>

        {/* Status dropdown */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <button style={{
            display: 'inline-flex', alignItems: 'center', gap: 8,
            padding: '5px 10px',
            background: `${accent}14`,
            border: `1px solid ${accent}66`,
            fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.08, textTransform: 'uppercase',
            color: accent, fontWeight: 600,
            borderRadius: 2, cursor: 'pointer',
          }}>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: accent }} />
            interested
            <LiidIcon name="chev" size={9} color={accent} />
          </button>
        </div>
      </div>

      {/* Timeline + composer (composer is inline at the bottom, not sticky) */}
      <div style={{ flex: 1, overflow: 'auto', padding: '24px 28px 60px' }} className="liid-scroll">
        {THREAD_SEED.map((m, i) => <ThreadItem key={i} m={m} accent={accent} />)}
        <Composer accent={accent} />
      </div>
    </div>
  );
}

function ThreadItem({ m, accent }) {
  if (m.kind === 'system') {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12,
        margin: '14px 0',
        fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, letterSpacing: 0.04,
      }}>
        <span style={{ width: 5, height: 5, borderRadius: 999, background: liidTokens.ink20, flexShrink: 0 }} />
        <span>{m.when}</span>
        <span style={{ width: 1, height: 10, background: liidTokens.ink20 }} />
        <span style={{ color: liidTokens.ink70 }}>{m.txt}</span>
        <span style={{ flex: 1, height: 1, background: liidTokens.rule }} />
      </div>
    );
  }
  if (m.kind === 'note') {
    return (
      <div style={{
        margin: '14px 0',
        padding: '14px 18px',
        background: '#fef4a8',
        border: `1px solid rgba(220, 190, 80, 0.4)`,
        borderRadius: 2,
        maxWidth: 620,
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6,
          fontFamily: liidTokens.mono, fontSize: 10, color: 'rgba(90, 74, 42, 0.7)', letterSpacing: 0.08,
          textTransform: 'uppercase',
        }}>
          <span>Note · {m.author}</span>
          <span>{m.when}</span>
        </div>
        <div style={{
          fontFamily: liidTokens.serif, fontStyle: 'italic', fontSize: 16,
          lineHeight: 1.5, color: '#5a4a2a',
        }}>{m.txt}</div>
      </div>
    );
  }
  const outbound = m.kind === 'outbound';
  return (
    <div style={{
      margin: '14px 0',
      maxWidth: 720,
      marginLeft: outbound ? 0 : 'auto',
      marginRight: outbound ? 'auto' : 0,
    }}>
      {/* Sender chip + meta */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        marginBottom: 6,
        fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink55, letterSpacing: 0.04,
      }}>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '2px 8px',
          background: outbound ? liidTokens.ink : `${accent}1c`,
          color: outbound ? liidTokens.paper : accent,
          borderRadius: 2,
          fontSize: 10, letterSpacing: 0.06, textTransform: 'uppercase', fontWeight: 600,
        }}>
          {outbound ? `step ${m.step}` : 'reply'}
        </span>
        <span>{outbound ? m.from : m.from.split(' <')[0]}</span>
        <span>·</span>
        <span>{m.when}</span>
        {outbound && (
          <span style={{ marginLeft: 8, display: 'inline-flex', gap: 8 }}>
            <span style={{ color: m.opened ? accent : liidTokens.ink40 }}>
              {m.opened ? `opened ${m.opened}×` : 'not opened'}
            </span>
            {m.clicked && <span style={{ color: accent }}>clicked</span>}
          </span>
        )}
      </div>

      {/* Message body */}
      <div style={{
        padding: '16px 20px',
        background: outbound ? liidTokens.paper : liidTokens.paperAlt,
        border: `1px solid ${liidTokens.rule}`,
        borderLeft: outbound ? `1px solid ${liidTokens.rule}` : `2px solid ${accent}`,
        borderRadius: 2,
      }}>
        <div style={{
          fontSize: 13, fontWeight: 600, color: liidTokens.ink, marginBottom: 10,
        }}>{m.subj}</div>
        <div style={{
          fontSize: 13, lineHeight: 1.6, color: liidTokens.ink70,
          whiteSpace: 'pre-wrap',
        }}>{m.body}</div>
      </div>
    </div>
  );
}

function Composer({ accent }) {
  return (
    <div style={{
      marginTop: 32,
      maxWidth: 720,
      background: liidTokens.paper,
      border: `1px solid ${liidTokens.ink20}`,
      borderRadius: 2,
    }}>
      {/* Tabs */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 0,
        borderBottom: `1px solid ${liidTokens.rule}`,
        padding: '0 24px',
      }}>
        {[
          { id: 'reply', label: 'Reply', active: true, kbd: '⌘ R' },
          { id: 'note',  label: 'Note',  active: false, kbd: '⌘ N' },
        ].map((t) => (
          <button key={t.id} style={{
            display: 'inline-flex', alignItems: 'center', gap: 8,
            padding: '12px 18px',
            background: 'transparent',
            border: 'none',
            borderBottom: `2px solid ${t.active ? liidTokens.ink : 'transparent'}`,
            color: t.active ? liidTokens.ink : liidTokens.ink55,
            fontFamily: liidTokens.sans, fontSize: 12, fontWeight: t.active ? 600 : 400,
            cursor: 'pointer',
            marginBottom: -1,
          }}>
            {t.label}
            <span style={{ fontFamily: liidTokens.mono, fontSize: 9, color: liidTokens.ink40, letterSpacing: 0.04 }}>
              {t.kbd}
            </span>
          </button>
        ))}
        <span style={{ flex: 1 }} />
        <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40 }}>
          To: m.tamm@pipedrive.com · from karl@liid-outreach.com
        </span>
      </div>

      {/* Body */}
      <div style={{ padding: '14px 24px 14px' }}>
        <div style={{
          minHeight: 70,
          padding: '8px 0',
          fontSize: 13, lineHeight: 1.6, color: liidTokens.ink40,
          fontStyle: 'italic',
        }}>
          Tue or Wed afternoon works on my end too — sending an invite for Wed Mar 26, 14:00 EET. Liis is welcome…
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 8 }}>
          <button style={ghostBtnSm}>B</button>
          <button style={{ ...ghostBtnSm, fontStyle: 'italic' }}>I</button>
          <button style={{ ...ghostBtnSm, textDecoration: 'underline' }}>U</button>
          <span style={{ width: 1, height: 14, background: liidTokens.ink20 }} />
          <button style={ghostBtnSm}>+ link</button>
          <button style={ghostBtnSm}>+ image</button>
          <span style={{ flex: 1 }} />
          <LiidBtn small>Save draft</LiidBtn>
          <LiidBtn primary small mono>
            <LiidIcon name="arrow" size={11} color={liidTokens.paper} />
            Send reply
          </LiidBtn>
        </div>
      </div>
    </div>
  );
}

const ghostBtnSm = {
  background: 'transparent', border: 'none',
  color: liidTokens.ink55, padding: '4px 8px',
  fontSize: 12, cursor: 'pointer', borderRadius: 2,
};

Object.assign(window, { ViewThread, ThreadPane });
