// View — /campaigns/:id/sequence
// Block-style vertical editor: step card → "wait N days" inline editor →
// next step → terminal block. Below: language, tracking, auto-approve.
//
// CALL-OUT: brief says "auto-approve toggle (only when unlocked — show
// both locked and unlocked variants)". I've made "unlocked" mean "user has
// sent ≥50 emails with healthy reply rate" — the exact unlock criteria
// isn't in the brief but the design exposes them as copy. Tweak the gate
// in product to whatever the rule actually is.

function ViewSequence({ accent, density, autoApproveUnlocked = false }) {
  const seq = LIID_SENDING_DATA.sequenceDraft;
  return (
    <LiidShell accent={accent} active="sequence">
      <PageHead
        kicker="Sending · Sequence"
        title={<>The <em style={{ fontStyle: 'italic', color: accent }}>shape</em> of every email we'll send.</>}
        sub="One template, applied to every approved contact. The AI rewrites the body per contact; the structure (steps, waits, terminal action) is fixed here."
        right={
          <LiidBtn small primary mono>
            <LiidIcon name="check" size={11} color={liidTokens.paper} />
            Save sequence
          </LiidBtn>
        }
      />

      <div style={{ flex: 1, overflow: 'auto', padding: '28px 36px 60px', display: 'flex', justifyContent: 'center' }} className="liid-scroll">
        <div style={{ width: '100%', maxWidth: 760, display: 'flex', flexDirection: 'column', gap: 0 }}>
          {seq.map((s, i) => (
            <React.Fragment key={s.step}>
              {i > 0 && <SequenceWait days={s.waitDays} accent={accent} />}
              <SequenceBlock step={s} accent={accent} />
            </React.Fragment>
          ))}
          <SequenceWait days={7} accent={accent} terminal />
          <SequenceTerminal accent={accent} />

          <button style={{
            marginTop: 28,
            padding: '14px',
            background: 'transparent',
            border: `1px dashed ${liidTokens.ink20}`,
            color: liidTokens.ink55,
            fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.08,
            textTransform: 'uppercase',
            cursor: 'pointer',
            borderRadius: 2,
          }}>+ add step</button>

          {/* Settings sections below the sequence */}
          <SectionDivider label="Language" />
          <SettingRow label="Drafts written in"
            hint="GPT-4o will write every email in this language. Mart's email above is in English.">
            <Select value="English" options={['English', 'Estonian', 'Finnish', 'Swedish', 'German']} />
          </SettingRow>

          <SectionDivider label="Tracking" />
          <SettingRow label="Open tracking" hint="Pixel embedded in every email. Available on a CNAME you set up yourself.">
            <Toggle on={true} accent={accent} />
          </SettingRow>
          <SettingRow label="Click tracking" hint="Wraps every link through a redirector on the same CNAME.">
            <Toggle on={true} accent={accent} />
          </SettingRow>
          <CnameCard accent={accent} />

          <SectionDivider label="Approval" />
          <AutoApproveRow accent={accent} unlocked={autoApproveUnlocked} />
        </div>
      </div>
    </LiidShell>
  );
}

function SequenceBlock({ step, accent }) {
  return (
    <div style={{
      border: `1px solid ${liidTokens.rule}`,
      borderRadius: 2,
      background: liidTokens.paper,
      overflow: 'hidden',
    }}>
      {/* Header strip */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 14,
        padding: '12px 18px',
        background: liidTokens.paperAlt,
        borderBottom: `1px solid ${liidTokens.rule}`,
      }}>
        <span style={{
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          width: 22, height: 22, borderRadius: 999,
          background: liidTokens.ink, color: liidTokens.paper,
          fontFamily: liidTokens.mono, fontSize: 11, fontWeight: 600,
        }}>{step.step}</span>
        <span style={{ fontSize: 14, color: liidTokens.ink, fontWeight: 500 }}>
          {step.step === 1 ? 'First email' : `Follow-up ${step.step - 1}`}
        </span>
        <span style={{ flex: 1 }} />
        <LiidIcon name="x" size={12} color={liidTokens.ink40} />
      </div>
    </div>
  );
}

function SequenceWait({ days, accent, terminal }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14,
      padding: '14px 0',
      paddingLeft: 32,
      position: 'relative',
    }}>
      <span style={{
        position: 'absolute', left: 14, top: 0, bottom: 0,
        width: 1, background: liidTokens.ink20,
      }} />
      <span style={{
        position: 'absolute', left: 9, top: 'calc(50% - 5px)',
        width: 11, height: 11, borderRadius: 999,
        background: liidTokens.paper,
        border: `1px solid ${liidTokens.ink20}`,
      }} />
      <span style={{
        fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.06,
        display: 'inline-flex', alignItems: 'center', gap: 8,
      }}>
        wait
        <input defaultValue={days} type="number" min={0} style={{
          width: 44, padding: '4px 6px',
          border: `1px solid ${liidTokens.ink20}`, borderRadius: 2,
          fontFamily: liidTokens.mono, fontSize: 12, textAlign: 'center',
          background: liidTokens.paper, color: liidTokens.ink,
          fontVariantNumeric: 'tabular-nums',
        }} />
        days
      </span>
      {terminal && (
        <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink40, letterSpacing: 0.04 }}>
          · then
        </span>
      )}
    </div>
  );
}

function SequenceTerminal({ accent }) {
  return (
    <div style={{
      border: `1px dashed ${liidTokens.ink20}`,
      borderRadius: 2,
      padding: '16px 18px',
      background: liidTokens.paperAlt,
      display: 'flex', alignItems: 'center', gap: 14,
    }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        width: 22, height: 22, borderRadius: 999,
        background: 'transparent', border: `1px solid ${liidTokens.ink40}`,
        color: liidTokens.ink55,
        fontFamily: liidTokens.mono, fontSize: 11, fontWeight: 600,
      }}>×</span>
      <span style={{ fontSize: 13, color: liidTokens.ink70 }}>
        If still no reply, mark contact as
      </span>
      <Select value="no_reply" options={['no_reply', 'Ready for call']} accent={accent} />
      <span style={{ flex: 1 }} />
      <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, letterSpacing: 0.04 }}>
        end of sequence
      </span>
    </div>
  );
}

// ── Settings rows ─────────────────────────────────────────────────────
function SectionDivider({ label }) {
  return (
    <div style={{
      marginTop: 40, marginBottom: 16,
      paddingBottom: 8,
      borderBottom: `1px solid ${liidTokens.rule}`,
      fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14,
      textTransform: 'uppercase', color: liidTokens.ink55,
    }}>{label}</div>
  );
}

function SettingRow({ label, hint, children }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: '1fr auto',
      gap: 24, padding: '14px 0',
      borderBottom: `1px solid ${liidTokens.rule}`,
      alignItems: 'center',
    }}>
      <div>
        <div style={{ fontSize: 13, color: liidTokens.ink, fontWeight: 500, marginBottom: 2 }}>{label}</div>
        {hint && <div style={{ fontSize: 12, color: liidTokens.ink55, lineHeight: 1.5 }}>{hint}</div>}
      </div>
      <div>{children}</div>
    </div>
  );
}

function Select({ value, options, sm, accent }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: sm ? '4px 10px' : '6px 12px',
      border: `1px solid ${liidTokens.ink20}`,
      background: liidTokens.paper,
      borderRadius: 2,
      fontFamily: value === 'no_reply' ? liidTokens.mono : liidTokens.sans,
      fontSize: sm ? 11 : 12,
      color: accent || liidTokens.ink,
      cursor: 'pointer',
    }}>
      {value}
      <LiidIcon name="chev" size={10} color={liidTokens.ink55} />
    </span>
  );
}

function Toggle({ on, accent }) {
  return (
    <span style={{
      position: 'relative', display: 'inline-block',
      width: 34, height: 18,
      borderRadius: 999,
      background: on ? accent : liidTokens.ink20,
      cursor: 'pointer',
      transition: 'background .12s',
    }}>
      <span style={{
        position: 'absolute',
        top: 2, left: on ? 18 : 2,
        width: 14, height: 14, borderRadius: 999,
        background: liidTokens.paper,
        boxShadow: '0 1px 2px rgba(0,0,0,0.2)',
        transition: 'left .12s',
      }} />
    </span>
  );
}

function CnameCard({ accent }) {
  return (
    <div style={{
      marginTop: 14,
      padding: '18px 20px',
      background: liidTokens.paperAlt,
      border: `1px solid ${liidTokens.rule}`,
      borderRadius: 2,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 14 }}>
        <div>
          <div style={{ fontSize: 13, color: liidTokens.ink, fontWeight: 500 }}>Tracking CNAME</div>
          <div style={{ fontSize: 12, color: liidTokens.ink55, marginTop: 2 }}>
            Required for opens/clicks. Set one CNAME at your DNS provider and reuse across all your sending accounts.
          </div>
        </div>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '3px 9px',
          background: `${accent}14`, border: `1px solid ${accent}55`,
          fontFamily: liidTokens.mono, fontSize: 10, color: accent, letterSpacing: 0.06, textTransform: 'uppercase',
          borderRadius: 2, fontWeight: 600,
        }}>
          <LiidIcon name="check" size={9} color={accent} />
          verified
        </span>
      </div>
      <div style={{
        display: 'grid', gridTemplateColumns: '70px 1fr 1fr',
        gap: 1, background: liidTokens.rule, border: `1px solid ${liidTokens.rule}`,
        fontFamily: liidTokens.mono, fontSize: 11,
      }}>
        {['TYPE', 'HOST', 'POINTS TO'].map((h) => (
          <div key={h} style={{
            padding: '8px 12px', background: liidTokens.paper, color: liidTokens.ink40,
            fontSize: 9, letterSpacing: 0.14,
          }}>{h}</div>
        ))}
        <div style={{ padding: '10px 12px', background: liidTokens.paper, color: liidTokens.ink }}>CNAME</div>
        <div style={{ padding: '10px 12px', background: liidTokens.paper, color: liidTokens.ink }}>track.liid.studio</div>
        <div style={{ padding: '10px 12px', background: liidTokens.paper, color: liidTokens.ink }}>tracking.liidmail.com</div>
      </div>
    </div>
  );
}

function AutoApproveRow({ accent, unlocked }) {
  if (!unlocked) {
    return (
      <div style={{
        padding: '18px 20px',
        background: liidTokens.paperAlt,
        border: `1px solid ${liidTokens.rule}`,
        borderRadius: 2,
        display: 'flex', alignItems: 'flex-start', gap: 16,
      }}>
        <span style={{
          width: 28, height: 28, borderRadius: 2,
          background: liidTokens.ink10,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={liidTokens.ink55} strokeWidth="1.4" strokeLinecap="round">
            <rect x="3" y="6.5" width="8" height="6" rx="0.5" />
            <path d="M4.5 6.5V4a2.5 2.5 0 0 1 5 0v2.5" />
          </svg>
        </span>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4 }}>
            <span style={{ fontSize: 13, color: liidTokens.ink, fontWeight: 500 }}>Auto-approve drafts</span>
            <span style={{
              fontFamily: liidTokens.mono, fontSize: 9, letterSpacing: 0.14, textTransform: 'uppercase',
              color: liidTokens.ink55, padding: '2px 6px',
              border: `1px solid ${liidTokens.ink20}`, borderRadius: 2,
            }}>locked</span>
          </div>
          <div style={{ fontSize: 12, color: liidTokens.ink55, lineHeight: 1.5, marginBottom: 10 }}>
            We unlock auto-approve after you've manually reviewed and sent <span style={{ color: liidTokens.ink }}>50 emails</span> with
            a reply rate above <span style={{ color: liidTokens.ink }}>3%</span>. You've reviewed{' '}
            <span style={{ color: liidTokens.ink, fontFamily: liidTokens.mono }}>34 / 50</span>.
          </div>
          <div style={{ height: 4, background: liidTokens.ink10, borderRadius: 1, position: 'relative', maxWidth: 360 }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '68%', background: accent }} />
          </div>
        </div>
        <Toggle on={false} accent={liidTokens.ink20} />
      </div>
    );
  }
  return (
    <div style={{
      padding: '18px 20px',
      background: liidTokens.paper,
      border: `1px solid ${liidTokens.ink20}`,
      borderRadius: 2,
      display: 'flex', alignItems: 'center', gap: 16,
    }}>
      <span style={{
        width: 28, height: 28, borderRadius: 2,
        background: `${accent}14`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <LiidIcon name="spark" size={14} color={accent} />
      </span>
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4 }}>
          <span style={{ fontSize: 13, color: liidTokens.ink, fontWeight: 500 }}>Auto-approve drafts</span>
          <span style={{
            fontFamily: liidTokens.mono, fontSize: 9, letterSpacing: 0.14, textTransform: 'uppercase',
            color: accent, padding: '2px 6px',
            background: `${accent}14`, border: `1px solid ${accent}55`, borderRadius: 2, fontWeight: 600,
          }}>unlocked</span>
        </div>
        <div style={{ fontSize: 12, color: liidTokens.ink55, lineHeight: 1.5 }}>
          Drafts go out as soon as GPT-4o finishes writing them. You can still intercept any draft
          from the Writing view before the wait timer fires.
        </div>
      </div>
      <Toggle on={true} accent={accent} />
    </div>
  );
}

Object.assign(window, { ViewSequence });
