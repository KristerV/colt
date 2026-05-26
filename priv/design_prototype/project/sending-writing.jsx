// View — /campaigns/:id/writing
// Single-contact workspace. Three states exposed as separate artboards:
//   · default   — drafted sequence, ready to approve
//   · drafting  — skeleton with pulsing "drafting…"
//   · empty     — no contacts pending; "Bring in N enriched contacts"
//   · empty-auto— auto-approve enabled (nothing for you to do, you're golden)
//
// CALL-OUT: brief says "terminal step shows what'll happen". I read this as
// the last block in the sequence editor — not a real sendable step, but a
// preview of the post-sequence behaviour (mark as no_reply or wait-for-call).
// If terminal is supposed to be a sendable email, this needs revisiting.

function ViewWriting({ accent, density, state = 'default' }) {
  const C = LIID_SENDING_DATA.focusContact;
  const seq = LIID_SENDING_DATA.sequenceDraft;

  return (
    <LiidShell accent={accent} active="writing">
      <PageHead
        kicker="Sending · Writing"
        title={<>Draft for <em style={{ fontStyle: 'italic', color: accent }}>Mart</em>.</>}
        sub="One contact at a time. Approve to send the first step; the rest schedules itself."
        right={
          <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55 }}>
            <span style={{ color: liidTokens.ink }}>47</span> / 188 pending
          </span>
        }
      />

      {state === 'empty'     && <WritingEmpty accent={accent} autoApprove={false} />}
      {state === 'empty-auto'&& <WritingEmpty accent={accent} autoApprove={true} />}
      {(state === 'default' || state === 'drafting') && (
        <div style={{ flex: 1, minHeight: 0, overflow: 'auto', padding: '24px 36px 110px' }} className="liid-scroll">
          <ContactHeaderCard contact={C} accent={accent} />

          {/* Gmail preview — full width, between contact + sequence */}
          <div style={{ marginTop: 28 }}>
            <div style={{
              marginBottom: 10,
              fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14,
              textTransform: 'uppercase', color: liidTokens.ink55,
            }}>How it lands in Mart's inbox</div>
            <InboxPreview accent={accent} />
          </div>

          {/* Subject — separate card above sequence */}
          <div style={{ marginTop: 32 }}>
            <div style={{
              marginBottom: 10,
              fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14,
              textTransform: 'uppercase', color: liidTokens.ink55,
            }}>Subject</div>
            <div style={{
              padding: '16px 20px',
              border: `1px solid ${liidTokens.ink20}`,
              borderLeft: `2px solid ${accent}`,
              background: liidTokens.paper,
              borderRadius: 2,
              fontSize: 17, color: liidTokens.ink, fontWeight: 500,
              letterSpacing: -0.1,
            }}>
              {seq[0].subject}
            </div>
            <div style={{
              marginTop: 6,
              fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, letterSpacing: 0.04,
            }}>follow-ups re-use this subject as “re: …”</div>
          </div>

          {/* Sequence editor */}
          <div style={{ marginTop: 28, display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
            <div style={{
              fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14,
              textTransform: 'uppercase', color: liidTokens.ink55,
            }}>Sequence draft</div>
            {state === 'drafting' && (
              <div style={{
                fontFamily: liidTokens.mono, fontSize: 10, color: accent, letterSpacing: 0.06,
                display: 'inline-flex', alignItems: 'center', gap: 6,
              }}>
                <span style={{ width: 5, height: 5, borderRadius: 999, background: accent, animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
                drafting…
              </div>
            )}
          </div>

          <div style={{ marginTop: 12 }}>
            {seq.map((s, i) => (
              <React.Fragment key={s.step}>
                {i > 0 && <WaitTimer days={s.waitDays} accent={accent} />}
                {state === 'drafting' && i > 0
                  ? <StepSkeleton step={s.step} accent={accent} />
                  : <SequenceStep step={s} accent={accent} drafting={state === 'drafting' && i === 0} active={i === 0} />}
              </React.Fragment>
            ))}
            <WaitTimer days={7} accent={accent} terminal />
            <TerminalStep accent={accent} />
          </div>
        </div>
      )}

      {(state === 'default' || state === 'drafting') && (
        <ActionBar accent={accent} drafting={state === 'drafting'} />
      )}
    </LiidShell>
  );
}

// ── Sequence step ─────────────────────────────────────────────────────
function SequenceStep({ step, accent, drafting, active }) {
  return (
    <div style={{
      border: `1px solid ${active ? liidTokens.ink20 : liidTokens.rule}`,
      borderLeft: `2px solid ${active ? accent : liidTokens.ink20}`,
      borderRadius: 2,
      background: liidTokens.paper,
      marginBottom: 4,
    }}>
      {/* Body */}
      <div style={{
        display: 'flex', gap: 14,
        padding: '18px 20px',
      }}>
        <span style={{
          fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40,
          textTransform: 'uppercase', letterSpacing: 0.12, minWidth: 64,
          paddingTop: 3,
        }}>Step {step.step}</span>
        <pre style={{
          margin: 0, flex: 1,
          fontFamily: liidTokens.sans, fontSize: 13.5, lineHeight: 1.6,
          color: liidTokens.ink70, whiteSpace: 'pre-wrap',
        }}>{step.body}</pre>
      </div>
    </div>
  );
}

function StepSkeleton({ step, accent }) {
  return (
    <div style={{
      border: `1px solid ${liidTokens.rule}`,
      borderLeft: `2px solid ${liidTokens.ink20}`,
      borderRadius: 2,
      padding: '16px 18px',
      marginBottom: 4,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 12 }}>
        <span style={{
          fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12, textTransform: 'uppercase',
          color: liidTokens.ink40,
        }}>Step {step}</span>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          fontFamily: liidTokens.mono, fontSize: 10, color: accent, letterSpacing: 0.06,
        }}>
          <span style={{ width: 5, height: 5, borderRadius: 999, background: accent, animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
          drafting…
        </span>
      </div>
      <div className="liid-shimmer" style={{ height: 12, width: '60%', marginBottom: 14, background: liidTokens.ink10 }} />
      <div className="liid-shimmer" style={{ height: 10, width: '95%', marginBottom: 6, background: liidTokens.ink10 }} />
      <div className="liid-shimmer" style={{ height: 10, width: '90%', marginBottom: 6, background: liidTokens.ink10 }} />
      <div className="liid-shimmer" style={{ height: 10, width: '70%', background: liidTokens.ink10 }} />
    </div>
  );
}

function WaitTimer({ days, accent, terminal }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '8px 0',
      paddingLeft: 18,
      position: 'relative',
    }}>
      <span style={{ width: 2, height: 18, background: liidTokens.ink20, position: 'absolute', left: 2 }} />
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 8,
        fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.08,
        color: liidTokens.ink55, textTransform: 'uppercase',
      }}>
        wait
        <span style={{ fontSize: 12, color: liidTokens.ink, fontVariantNumeric: 'tabular-nums' }}>{days}</span>
        days
        {terminal && <span style={{ color: liidTokens.ink40 }}>· then</span>}
      </span>
    </div>
  );
}

function TerminalStep({ accent }) {
  return (
    <div style={{
      border: `1px dashed ${liidTokens.ink20}`,
      borderRadius: 2,
      padding: '14px 18px',
      display: 'flex', alignItems: 'center', gap: 14,
    }}>
      <span style={{
        fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12, textTransform: 'uppercase',
        color: liidTokens.ink40, minWidth: 56,
      }}>Then</span>
      <span style={{ fontSize: 13, color: liidTokens.ink70 }}>
        If still no reply, mark contact as
      </span>
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: '4px 10px',
        border: `1px solid ${liidTokens.ink20}`,
        background: liidTokens.paper,
        fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink,
        borderRadius: 2,
      }}>
        no_reply
        <LiidIcon name="chev" size={10} color={liidTokens.ink55} />
      </div>
      <span style={{ fontSize: 12, color: liidTokens.ink40, fontStyle: 'italic', fontFamily: liidTokens.serif }}>
        — or set "Ready for call" if you got a positive signal earlier.
      </span>
    </div>
  );
}

// ── Inbox preview (Gmail-style) ───────────────────────────────────────
function InboxPreview({ accent }) {
  return (
    <div style={{
      border: `1px solid ${liidTokens.rule}`,
      borderRadius: 2,
      background: liidTokens.paper,
      overflow: 'hidden',
    }}>
      {/* Gmail toolbar only */}
      <div style={{
        padding: '8px 18px',
        borderBottom: `1px solid ${liidTokens.rule}`,
        background: liidTokens.paperAlt,
        display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
          <span style={{ width: 14, height: 14, border: `1px solid ${liidTokens.ink40}`, borderRadius: 2, display: 'inline-block' }} />
          <LiidIcon name="chev" size={9} color={liidTokens.ink55} />
        </span>
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke={liidTokens.ink55} strokeWidth="1.4" strokeLinecap="round"><path d="M3 8a5 5 0 0 1 8.5-3.5L14 7M14 2v5h-5"/></svg>
        <svg width="14" height="14" viewBox="0 0 16 16" fill={liidTokens.ink55}><circle cx="8" cy="3.5" r="1.2"/><circle cx="8" cy="8" r="1.2"/><circle cx="8" cy="12.5" r="1.2"/></svg>
      </div>

      <div>
        {LIID_SENDING_DATA.inbox.map((m, i) => <GmailRow key={i} m={m} accent={accent} />)}
      </div>
    </div>
  );
}

function GmailRow({ m, accent }) {
  const unread = !m.read;
  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: '22px 18px 180px 1fr 80px',
      alignItems: 'center', gap: 14,
      padding: '9px 18px',
      borderBottom: `1px solid ${liidTokens.rule}`,
      background: unread ? liidTokens.paper : liidTokens.paperAlt,
      cursor: 'pointer',
    }}>
      {/* Checkbox */}
      <span style={{
        width: 14, height: 14, borderRadius: 2,
        border: `1px solid ${liidTokens.ink40}`, display: 'inline-block',
      }} />

      {/* Star */}
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none"
        stroke={liidTokens.ink40} strokeWidth="1.2" strokeLinejoin="round">
        <path d="M8 1.5l1.9 3.85 4.25.62-3.07 3 .72 4.23L8 11.2l-3.8 2 .72-4.23-3.07-3 4.25-.62L8 1.5z"/>
      </svg>

      {/* Sender */}
      <span style={{
        fontSize: 13,
        fontWeight: unread ? 700 : 400,
        color: liidTokens.ink,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
      }}>{m.from}</span>

      {/* Subject + preview inline */}
      <span style={{
        fontSize: 13,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        minWidth: 0,
      }}>
        <span style={{ fontWeight: unread ? 700 : 400, color: liidTokens.ink }}>
          {m.subj}
        </span>
        <span style={{ color: liidTokens.ink55, fontWeight: 400 }}>
          {' '}- {m.preview}
        </span>
      </span>

      {/* Time */}
      <span style={{
        fontFamily: liidTokens.mono, fontSize: 11,
        color: unread ? liidTokens.ink : liidTokens.ink55,
        fontWeight: unread ? 600 : 400,
        textAlign: 'right',
        whiteSpace: 'nowrap',
      }}>{m.when}</span>
    </div>
  );
}

// ── Sticky action bar ─────────────────────────────────────────────────
function ActionBar({ accent, drafting }) {
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0,
      borderTop: `1px solid ${liidTokens.ink20}`,
      background: liidTokens.paper,
      padding: '14px 32px',
      display: 'flex', alignItems: 'center', gap: 16,
      boxShadow: '0 -4px 24px rgba(0,0,0,0.04)',
    }}>
      <span style={{ flex: 1 }} />
      <button disabled={drafting} style={{
        display: 'inline-flex', alignItems: 'center', gap: 10,
        padding: '10px 20px',
        fontFamily: liidTokens.sans, fontSize: 13, fontWeight: 500,
        background: drafting ? liidTokens.ink20 : liidTokens.ink,
        color: liidTokens.paper,
        border: `1px solid ${drafting ? liidTokens.ink20 : liidTokens.ink}`,
        borderRadius: 2,
        cursor: drafting ? 'not-allowed' : 'pointer',
      }}>
        <LiidIcon name="check" size={12} color={liidTokens.paper} />
        Approve & next
        <span style={{ fontFamily: liidTokens.mono, fontSize: 10, opacity: 0.7, marginLeft: 4, padding: '1px 4px', border: `1px solid ${liidTokens.paper}33`, borderRadius: 2 }}>
          ⌘ ⏎
        </span>
      </button>
    </div>
  );
}

// ── Empty states ──────────────────────────────────────────────────────
function WritingEmpty({ accent, autoApprove }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: 48, textAlign: 'center',
      gap: 24,
    }}>
      {autoApprove ? (
        <>
          <div style={{
            width: 56, height: 56, borderRadius: 999,
            background: `${accent}14`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <span style={{
              width: 14, height: 14, borderRadius: 999, background: accent,
              boxShadow: `0 0 0 5px ${accent}22`,
              animation: 'liid-pulse 2.4s ease-in-out infinite',
            }} />
          </div>
          <h2 style={{
            fontFamily: liidTokens.serif, fontWeight: 400, fontSize: 44,
            letterSpacing: -0.8, lineHeight: 1.05, margin: 0, maxWidth: 480,
          }}>You're <em style={{ color: accent }}>off the hook</em>.</h2>
          <p style={{ fontSize: 14, color: liidTokens.ink55, maxWidth: 460, lineHeight: 1.6, margin: 0 }}>
            Auto-approve is on. Sequences ship as soon as they're drafted — no
            review step. 188 contacts queued for the next 14 days.
          </p>
          <div style={{
            display: 'flex', gap: 24,
            padding: '14px 22px',
            background: liidTokens.paperAlt,
            border: `1px solid ${liidTokens.rule}`,
            borderRadius: 2,
            fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink70,
          }}>
            <span><span style={{ color: liidTokens.ink40 }}>drafted today</span> &nbsp;47</span>
            <span><span style={{ color: liidTokens.ink40 }}>sent</span> &nbsp;142</span>
            <span><span style={{ color: liidTokens.ink40 }}>queue</span> &nbsp;188</span>
          </div>
          <LiidBtn small>Turn off auto-approve</LiidBtn>
        </>
      ) : (
        <>
          <div style={{
            fontFamily: liidTokens.serif, fontSize: 96, lineHeight: 1, color: accent,
            opacity: 0.4,
          }}>0</div>
          <h2 style={{
            fontFamily: liidTokens.serif, fontWeight: 400, fontSize: 44,
            letterSpacing: -0.8, lineHeight: 1.05, margin: 0, maxWidth: 520,
          }}>Nothing to <em style={{ color: accent }}>review</em>.</h2>
          <p style={{ fontSize: 14, color: liidTokens.ink55, maxWidth: 460, lineHeight: 1.6, margin: 0 }}>
            All 188 contacts that have been enriched so far are already
            approved or sent. There are still 124 enriched contacts available
            you haven't pulled into sending.
          </p>
          <LiidBtn primary mono>
            <LiidIcon name="arrow" size={12} color={liidTokens.paper} />
            Bring in 124 enriched contacts
          </LiidBtn>
          <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40 }}>
            or turn on auto-approve in <span style={{ color: liidTokens.ink70 }}>Sequence settings</span>
          </span>
        </>
      )}
    </div>
  );
}

const ghostBtn = {
  background: 'transparent',
  border: 'none',
  color: liidTokens.ink55,
  fontFamily: liidTokens.mono,
  fontSize: 10,
  letterSpacing: 0.08,
  textTransform: 'uppercase',
  cursor: 'pointer',
  padding: '4px 6px',
};

Object.assign(window, { ViewWriting });
