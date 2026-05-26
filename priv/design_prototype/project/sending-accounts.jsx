// View — /campaigns/:id/sending-accounts  (campaign level)
// Two modes:
//   · 'default'  — list of accounts CURRENTLY enrolled in this campaign,
//                  each with a "remove" action. "+ Add accounts" header
//                  button opens the picker mode (a separate route).
//   · 'picker'   — full list of all user-level accounts with checkboxes,
//                  Save / Cancel.
//
// User-level concerns (connect, re-auth, daily quota) all live in
// /email-accounts.

function ViewSendingAccounts({ accent, density, mode = 'default' }) {
  return mode === 'picker'
    ? <SendingAccountsPicker accent={accent} />
    : <SendingAccountsDefault accent={accent} />;
}

// ── DEFAULT: enrolled accounts only ───────────────────────────────────
function SendingAccountsDefault({ accent }) {
  const all = LIID_SENDING_DATA.sendingAccounts;
  const perAccountDaily = LIID_SENDING_DATA.perAccountDaily;
  const enrolled = all.filter((a) => a.selectedForCampaign);
  const sendingNow = enrolled.filter((a) => a.status === 'active');
  const totalDaily = sendingNow.length * perAccountDaily;
  const totalMonthly = totalDaily * 22;
  const sequenceLen = 3;
  const totalWaitDays = 11;
  const contactsPerDay = Math.max(1, Math.round(totalDaily / sequenceLen));

  return (
    <LiidShell accent={accent} active="accounts">
      <PageHead
        kicker="Sending · Accounts"
        title={<>Which inboxes this campaign <em style={{ fontStyle: 'italic', color: accent }}>sends through</em>.</>}
        sub={<>Connect, re-auth and quota are managed in <span style={{ color: liidTokens.ink, textDecoration: 'underline', textUnderlineOffset: 3 }}>Email accounts</span>.</>}
        right={
          <LiidBtn primary small mono>
            <LiidIcon name="plus" size={11} color={liidTokens.paper} />
            Add accounts
          </LiidBtn>
        }
      />

      <div style={{ flex: 1, overflow: 'auto', padding: '24px 36px 80px' }} className="liid-scroll">
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 90px 90px 90px 140px 90px',
          gap: 0,
          border: `1px solid ${liidTokens.rule}`,
          borderRadius: 2,
        }}>
          <SHCell label="Account" />
          <SHCell label="Sent" right />
          <SHCell label="Reply" right />
          <SHCell label="Bounce" right />
          <SHCell label="Status" />
          <SHCell label="" />

          {enrolled.length === 0 && (
            <EmptyRow accent={accent} />
          )}
          {enrolled.map((a, i) => (
            <EnrolledRow key={a.addr} a={a} accent={accent} last={i === enrolled.length - 1} />
          ))}
        </div>

        <div style={{
          marginTop: 14,
          fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
        }}>
          {enrolled.length} of {all.length} connected accounts in this campaign
        </div>

        {/* Capacity card */}
        <div style={{
          marginTop: 28,
          padding: '24px 28px',
          background: liidTokens.paperAlt,
          border: `1px solid ${liidTokens.rule}`,
          borderRadius: 2,
        }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 18 }}>
            <div>
              <div style={{
                fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14, textTransform: 'uppercase',
                color: liidTokens.ink55, marginBottom: 4,
              }}>Capacity for this campaign</div>
              <div style={{ fontFamily: liidTokens.serif, fontSize: 26, letterSpacing: -0.4, lineHeight: 1 }}>
                Live-computed from active inboxes.
              </div>
            </div>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              padding: '3px 9px',
              background: `${accent}14`,
              border: `1px solid ${accent}55`,
              fontFamily: liidTokens.mono, fontSize: 10, color: accent, letterSpacing: 0.06, textTransform: 'uppercase',
              borderRadius: 2, fontWeight: 600,
            }}>
              <span style={{ width: 6, height: 6, borderRadius: 999, background: accent, animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
              {sendingNow.length} sending now
            </span>
          </div>

          <div style={{
            display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
            gap: 1, background: liidTokens.rule,
            border: `1px solid ${liidTokens.rule}`,
            borderRadius: 2, overflow: 'hidden',
          }}>
            <CapacityTile label="Daily"      big={`~${totalDaily}`} sub="emails / day" accent={accent} />
            <CapacityTile label="Monthly"    big={`~${(totalMonthly / 1000).toFixed(1)}k`} sub="emails / month" />
            <CapacityTile label="Throughput" big={`${contactsPerDay}`} sub={`contacts / day · ${totalWaitDays}d each`} />
          </div>

          <div style={{
            marginTop: 18,
            display: 'flex', alignItems: 'center', gap: 12,
            fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
          }}>
            <LiidIcon name="spark" size={11} color={liidTokens.ink55} />
            <span>
              At this rate, sending the 188 approved contacts will take{' '}
              <span style={{ color: liidTokens.ink, fontWeight: 600 }}>~{Math.ceil(188 / contactsPerDay)} days</span>.
              Add more accounts to finish faster.
            </span>
          </div>
        </div>
      </div>
    </LiidShell>
  );
}

function EnrolledRow({ a, accent, last }) {
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
      </div>
      <NCell value={a.sent.toLocaleString()} bd={bd} muted={muted} dim />
      <NCell value={`${a.replyRate}%`} bd={bd} muted={muted} dim />
      <NCell value={`${a.bounceRate}%`} bd={bd} muted={muted}
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
        <button style={{
          padding: '4px 10px', background: 'transparent', color: liidTokens.ink55,
          border: `1px solid ${liidTokens.ink20}`, fontFamily: liidTokens.mono, fontSize: 10,
          letterSpacing: 0.08, textTransform: 'uppercase', cursor: 'pointer', borderRadius: 2,
        }}>remove</button>
      </div>
    </>
  );
}

function EmptyRow({ accent }) {
  return (
    <div style={{
      gridColumn: '1 / -1',
      padding: '36px 24px',
      textAlign: 'center',
    }}>
      <div style={{
        fontFamily: liidTokens.serif, fontSize: 22, color: liidTokens.ink55,
        letterSpacing: -0.2, marginBottom: 6,
      }}>
        No inboxes enrolled yet.
      </div>
      <div style={{ fontSize: 12, color: liidTokens.ink40, marginBottom: 14 }}>
        This campaign can't send until at least one is added.
      </div>
      <LiidBtn primary small mono>
        <LiidIcon name="plus" size={11} color={liidTokens.paper} />
        Add accounts
      </LiidBtn>
    </div>
  );
}

// ── PICKER: choose from all available accounts ────────────────────────
function SendingAccountsPicker({ accent }) {
  const all = LIID_SENDING_DATA.sendingAccounts;
  return (
    <LiidShell accent={accent} active="accounts">
      <PageHead
        kicker="Sending · Accounts · Add"
        title={<>Pick inboxes for this <em style={{ fontStyle: 'italic', color: accent }}>campaign</em>.</>}
        sub="Each inbox respects its global daily quota. Disconnected accounts are unselectable."
        right={
          <>
            <LiidBtn small>Cancel</LiidBtn>
            <LiidBtn primary small mono>
              <LiidIcon name="check" size={11} color={liidTokens.paper} />
              Save selection
            </LiidBtn>
          </>
        }
      />

      <div style={{ flex: 1, overflow: 'auto', padding: '24px 36px 60px' }} className="liid-scroll">
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          marginBottom: 12,
          fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
        }}>
          <span>
            <span style={{ color: liidTokens.ink, fontWeight: 600 }}>
              {all.filter((a) => a.selectedForCampaign).length}
            </span> selected · {all.length} available
          </span>
          <span>
            <button style={ghostMono}>select all</button>
            <span style={{ color: liidTokens.ink20, margin: '0 6px' }}>·</span>
            <button style={ghostMono}>clear</button>
          </span>
        </div>

        <div style={{
          display: 'grid', gridTemplateColumns: '36px 1fr 100px 90px 90px 140px',
          gap: 0,
          border: `1px solid ${liidTokens.rule}`,
          borderRadius: 2,
        }}>
          <SHCell />
          <SHCell label="Account" />
          <SHCell label="Campaigns" right />
          <SHCell label="Reply" right />
          <SHCell label="Bounce" right />
          <SHCell label="Status" />

          {all.map((a, i) => (
            <PickerRow key={a.addr} a={a} accent={accent} last={i === all.length - 1} />
          ))}
        </div>

        <div style={{
          marginTop: 16, padding: '12px 16px',
          background: liidTokens.paperAlt,
          border: `1px solid ${liidTokens.rule}`, borderRadius: 2,
          fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <LiidIcon name="spark" size={11} color={liidTokens.ink55} />
          Don't see the inbox you want? <button style={{ ...ghostMono, color: accent }}>Connect a new one in Email accounts →</button>
        </div>
      </div>
    </LiidShell>
  );
}

function PickerRow({ a, accent, last }) {
  const bd = last ? 'none' : `1px solid ${liidTokens.rule}`;
  const isDisconnected = a.status === 'disconnected';
  const selectable = !isDisconnected;
  const selected = a.selectedForCampaign && selectable;
  const rowBg = selected ? `${accent}06` : 'transparent';

  const statusMap = {
    active:       { label: 'active',       col: accent,           bg: `${accent}14`,         border: `${accent}55` },
    paused:       { label: 'paused',       col: liidTokens.ink55, bg: liidTokens.ink10,      border: liidTokens.ink20 },
    disconnected: { label: 'disconnected', col: liidTokens.fail,  bg: `${liidTokens.fail}14`,border: `${liidTokens.fail}55` },
  };
  const s = statusMap[a.status];

  return (
    <>
      <div style={{ padding: '13px 0 13px 14px', borderBottom: bd, background: rowBg, display: 'flex', alignItems: 'center' }}>
        <span style={{
          width: 14, height: 14, borderRadius: 2,
          border: `1px solid ${selected ? accent : (selectable ? liidTokens.ink40 : liidTokens.ink20)}`,
          background: selected ? accent : 'transparent',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          opacity: selectable ? 1 : 0.5,
        }}>
          {selected && <LiidIcon name="check" size={10} color={liidTokens.paper} />}
        </span>
      </div>
      <div style={{ padding: '12px 14px', borderBottom: bd, background: rowBg, opacity: selectable ? 1 : 0.6 }}>
        <div style={{ fontFamily: liidTokens.mono, fontSize: 13, color: liidTokens.ink, fontWeight: 500 }}>
          {a.addr}
        </div>
        {!selectable && (
          <div style={{ fontSize: 11, color: liidTokens.fail, marginTop: 3 }}>
            disconnected — re-auth in Email accounts first
          </div>
        )}
      </div>
      <NCell value={a.campaigns.toString()} bd={bd} bg={rowBg} muted={!selectable} dim />
      <NCell value={`${a.replyRate}%`} bd={bd} bg={rowBg} muted={!selectable} dim />
      <NCell value={`${a.bounceRate}%`} bd={bd} bg={rowBg} muted={!selectable}
        color={a.bounceRate >= 3 ? liidTokens.fail : liidTokens.ink70} />
      <div style={{ padding: '13px 14px', borderBottom: bd, background: rowBg, display: 'flex', alignItems: 'center' }}>
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
    </>
  );
}

// ── Shared cells ──────────────────────────────────────────────────────
function SHCell({ label, right }) {
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

function NCell({ value, bd, bg, muted, color, dim }) {
  return (
    <div style={{
      padding: '13px 14px', borderBottom: bd, background: bg || 'transparent',
      display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
      opacity: muted ? 0.5 : 1,
    }}>
      <span style={{
        fontFamily: liidTokens.mono, fontSize: 12,
        color: color || (dim ? liidTokens.ink70 : liidTokens.ink),
        fontVariantNumeric: 'tabular-nums',
      }}>{value}</span>
    </div>
  );
}

function CapacityTile({ label, big, sub, accent }) {
  return (
    <div style={{ padding: '18px 22px', background: liidTokens.paper }}>
      <div style={{
        fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.14,
        textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 8,
      }}>{label}</div>
      <div style={{
        fontFamily: liidTokens.serif, fontSize: 42, fontWeight: 400,
        letterSpacing: -0.8, lineHeight: 1,
        color: accent || liidTokens.ink, fontVariantNumeric: 'tabular-nums',
      }}>{big}</div>
      <div style={{ marginTop: 8, fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04 }}>
        {sub}
      </div>
    </div>
  );
}

const ghostMono = {
  background: 'transparent', border: 'none',
  color: liidTokens.ink70, padding: 0,
  fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.06,
  cursor: 'pointer',
};

Object.assign(window, { ViewSendingAccounts });
