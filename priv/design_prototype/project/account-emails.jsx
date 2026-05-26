// View — /email-accounts  (user/workspace level)
// Where the user manages every inbox they own: add new ones, set the
// global daily quota per inbox so no account gets over-used across
// campaigns, monitor lifetime health (sent / reply / bounce), and re-auth
// when OAuth expires.
//
// Separate from /campaigns/:id/sending-accounts, which is the
// per-campaign selection of which accounts to use.

function ViewEmailAccounts({ accent, density }) {
  const accounts = LIID_SENDING_DATA.sendingAccounts;
  const active = accounts.filter((a) => a.status === 'active');
  const perAccountDaily = LIID_SENDING_DATA.perAccountDaily;
  const totalDaily = active.length * perAccountDaily;

  return (
    <LiidShell accent={accent} active="email-accounts">
      <PageHead
        kicker="Email accounts"
        title={<>Every inbox we can <em style={{ fontStyle: 'italic', color: accent }}>send</em> from.</>}
        sub="Set a per-inbox daily ceiling here. Campaigns pick from this pool and share the quota — no single account ever sends more than its limit, no matter how many campaigns it's in."
        right={
          <LiidBtn primary small mono>
            <LiidIcon name="plus" size={11} color={liidTokens.paper} />
            Connect account
          </LiidBtn>
        }
      />

      <div style={{ flex: 1, overflow: 'auto', padding: '24px 36px 80px' }} className="liid-scroll">
        {/* Summary strip */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
          border: `1px solid ${liidTokens.rule}`, borderRadius: 2,
          marginBottom: 24,
        }}>
          <SummaryTile label="Connected"    big={accounts.length.toString()} sub="inboxes" accent={accent} />
          <SummaryTile label="Active"       big={active.length.toString()}    sub="sending right now" tone="accent" accent={accent} pulse />
          <GlobalQuotaTile value={perAccountDaily} totalDaily={totalDaily} accent={accent} />
          <SummaryTile label="Disconnected" big={accounts.filter((a) => a.status === 'disconnected').length.toString()} sub="need re-auth" tone="fail" accent={accent} last />
        </div>

        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 90px 90px 90px 140px 120px',
          gap: 0,
          border: `1px solid ${liidTokens.rule}`,
          borderRadius: 2,
        }}>
          <HCell label="Account" />
          <HCell label="Sent" right />
          <HCell label="Reply" right />
          <HCell label="Bounce" right />
          <HCell label="Status" />
          <HCell label="" />

          {accounts.map((a, i) => (
            <EmailAccountRow key={a.addr} a={a} accent={accent} last={i === accounts.length - 1} />
          ))}
        </div>

        <div style={{
          marginTop: 16, fontFamily: liidTokens.mono, fontSize: 11,
          color: liidTokens.ink55, letterSpacing: 0.04,
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <LiidIcon name="spark" size={11} color={liidTokens.ink55} />
          <span>
            Inbox providers throttle accounts sending more than ~20 cold emails / day.
            Keeping each below that line is how you stay out of spam.
          </span>
        </div>
      </div>
    </LiidShell>
  );
}

function SummaryTile({ label, big, sub, tone, accent, pulse, last }) {
  const color = tone === 'accent' ? accent : (tone === 'fail' ? liidTokens.fail : liidTokens.ink);
  return (
    <div style={{
      padding: '14px 18px',
      borderRight: last ? 'none' : `1px solid ${liidTokens.rule}`,
      background: liidTokens.paper,
    }}>
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
        textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 6,
      }}>
        {pulse && (
          <span style={{ width: 5, height: 5, borderRadius: 999, background: color,
            animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
        )}
        {label}
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
        <span style={{
          fontFamily: liidTokens.serif, fontSize: 36, fontWeight: 400,
          letterSpacing: -0.6, lineHeight: 1, color,
          fontVariantNumeric: 'tabular-nums',
        }}>{big}</span>
        <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04 }}>
          {sub}
        </span>
      </div>
    </div>
  );
}

function HCell({ label, right }) {
  return (
    <div style={{
      padding: '11px 14px',
      borderBottom: `1px solid ${liidTokens.rule}`,
      background: liidTokens.paperAlt,
      fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
      textTransform: 'uppercase', color: liidTokens.ink55,
      textAlign: right ? 'right' : 'left',
    }}>{label}</div>
  );
}

function EmailAccountRow({ a, accent, last }) {
  const bd = last ? 'none' : `1px solid ${liidTokens.rule}`;
  const isPaused = a.status === 'paused';
  const isDisconnected = a.status === 'disconnected';
  const muted = isPaused || isDisconnected;

  const statusMap = {
    active:       { label: 'active',       col: accent,           bg: `${accent}14`,         border: `${accent}55` },
    paused:       { label: 'paused',       col: liidTokens.ink55, bg: liidTokens.ink10,      border: liidTokens.ink20 },
    disconnected: { label: 'disconnected', col: liidTokens.fail,  bg: `${liidTokens.fail}14`,border: `${liidTokens.fail}55` },
  };
  const s = statusMap[a.status];

  return (
    <>
      <div style={{ padding: '13px 18px', borderBottom: bd, opacity: muted ? 0.65 : 1 }}>
        <div style={{ fontFamily: liidTokens.mono, fontSize: 13, color: liidTokens.ink, fontWeight: 500 }}>
          {a.addr}
        </div>
        {a.reason && (
          <div style={{ fontSize: 11, color: isDisconnected ? liidTokens.fail : liidTokens.ink55, marginTop: 3 }}>
            {a.reason}
          </div>
        )}
        <div style={{
          fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40,
          letterSpacing: 0.04, marginTop: 3,
        }}>
          in {a.campaigns} {a.campaigns === 1 ? 'campaign' : 'campaigns'}
        </div>
      </div>
      <CellNum value={a.sent.toLocaleString()} bd={bd} muted={muted} />
      <CellNum value={`${a.replyRate}%`} bd={bd} muted={muted} />
      <CellNum value={`${a.bounceRate}%`} bd={bd} muted={muted}
        color={a.bounceRate >= 3 ? liidTokens.fail : liidTokens.ink70} />
      <div style={{ padding: '13px 14px', borderBottom: bd, display: 'flex', alignItems: 'center' }}>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '3px 9px',
          background: s.bg, border: `1px solid ${s.border}`,
          fontFamily: liidTokens.mono, fontSize: 10, color: s.col, letterSpacing: 0.06, textTransform: 'uppercase',
          borderRadius: 2, fontWeight: 600,
        }}>
          <span style={{
            width: 6, height: 6, borderRadius: 999, background: s.col,
            animation: a.status === 'active' ? 'liid-pulse 1.4s ease-in-out infinite' : 'none',
          }} />
          {s.label}
        </span>
      </div>
      <div style={{ padding: '13px 14px', borderBottom: bd, textAlign: 'right' }}>
        {isDisconnected ? (
          <button style={{
            padding: '4px 10px', background: liidTokens.fail, color: liidTokens.paper,
            border: 'none', fontFamily: liidTokens.mono, fontSize: 10,
            letterSpacing: 0.08, textTransform: 'uppercase', cursor: 'pointer', borderRadius: 2,
          }}>re-auth</button>
        ) : (
          <button style={{
            padding: '4px 10px', background: 'transparent', color: liidTokens.ink55,
            border: `1px solid ${liidTokens.ink20}`, fontFamily: liidTokens.mono, fontSize: 10,
            letterSpacing: 0.08, textTransform: 'uppercase', cursor: 'pointer', borderRadius: 2,
          }}>{isPaused ? 'resume' : 'pause'}</button>
        )}
      </div>
    </>
  );
}

function CellNum({ value, bd, muted, color }) {
  return (
    <div style={{
      padding: '13px 14px', borderBottom: bd,
      display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
      opacity: muted ? 0.5 : 1,
    }}>
      <span style={{
        fontFamily: liidTokens.mono, fontSize: 12,
        color: color || liidTokens.ink70,
        fontVariantNumeric: 'tabular-nums',
      }}>{value}</span>
    </div>
  );
}

function GlobalQuotaTile({ value, totalDaily, accent }) {
  return (
    <div style={{
      padding: '14px 18px',
      borderRight: `1px solid ${liidTokens.rule}`,
      background: liidTokens.paper,
    }}>
      <div style={{
        fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
        textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 8,
      }}>Daily quota · per inbox</div>
      <div style={{
        display: 'inline-flex', alignItems: 'center',
        border: `1px solid ${liidTokens.ink20}`,
        borderRadius: 2,
        background: liidTokens.paper,
      }}>
        <button style={qBtn}>−</button>
        <div style={{
          padding: '2px 12px',
          fontFamily: liidTokens.serif, fontSize: 28, lineHeight: 1,
          color: liidTokens.ink, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.4,
          borderLeft: `1px solid ${liidTokens.rule}`, borderRight: `1px solid ${liidTokens.rule}`,
          minWidth: 44, textAlign: 'center',
        }}>{value}</div>
        <button style={qBtn}>+</button>
      </div>
      <div style={{
        marginTop: 8, fontFamily: liidTokens.mono, fontSize: 11,
        color: liidTokens.ink55, letterSpacing: 0.04,
      }}>
        ~{totalDaily} emails / day total
      </div>
    </div>
  );
}

function QuotaStepper({ value, accent, disabled }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center',
      border: `1px solid ${liidTokens.ink20}`, borderRadius: 2,
      background: disabled ? 'transparent' : liidTokens.paper,
    }}>
      <button disabled={disabled} style={qBtn}>−</button>
      <div style={{
        padding: '4px 10px',
        fontFamily: liidTokens.mono, fontSize: 12, color: liidTokens.ink,
        fontVariantNumeric: 'tabular-nums',
        borderLeft: `1px solid ${liidTokens.rule}`, borderRight: `1px solid ${liidTokens.rule}`,
        minWidth: 32, textAlign: 'center',
      }}>{value}</div>
      <button disabled={disabled} style={qBtn}>+</button>
    </div>
  );
}

const qBtn = {
  width: 24, padding: '4px 0',
  background: 'transparent', border: 'none',
  fontFamily: liidTokens.mono, fontSize: 13, color: liidTokens.ink70,
  cursor: 'pointer',
};

Object.assign(window, { ViewEmailAccounts });
