// View — /campaigns/:id/sending-funnel
// 5-tile stats strip · bucket strip · split-pane (list + thread)
// Bounce rate: red ≥3% (text), banner ≥5% (top-of-page warning).
//
// CALL-OUT: brief says "bucket strip below" but doesn't specify the
// behaviour when a bucket is selected. I'm assuming click filters the
// contact list. "Call ready" + "Replied · interested" are highlighted
// with the accent because those are the actionable buckets.

function ViewSendingFunnel({ accent, density, bounceState = 'normal' }) {
  // bounceState: 'normal' (<3%), 'warn' (3-5%, red text), 'banner' (≥5%, top banner)
  const S = LIID_SENDING_DATA.stats;
  const bouncePct = bounceState === 'normal' ? 1.8 : (bounceState === 'warn' ? 3.4 : 6.2);

  return (
    <LiidShell accent={accent} active="sf">
      {bounceState === 'banner' && <BounceBanner pct={bouncePct} />}
      <PageHead
        kicker="Sending · Funnel"
        title={<>Where the <em style={{ fontStyle: 'italic', color: accent }}>conversation</em> is going.</>}
        right={
          <LiidBtn small mono>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: accent, animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
            live · refreshing
          </LiidBtn>
        }
      />

      <div style={{ padding: '20px 28px 18px', borderBottom: `1px solid ${liidTokens.rule}` }}>
        <BucketStrip accent={accent} bounceState={bounceState} bouncePct={bouncePct} />
      </div>

      {/* Split pane */}
      <div style={{
        flex: 1, minHeight: 0,
        display: 'grid', gridTemplateColumns: '380px 1fr',
        overflow: 'hidden',
      }}>
        <ContactList accent={accent} />
        <ThreadPane accent={accent} contact={LIID_SENDING_DATA.focusContact} embedded />
      </div>
    </LiidShell>
  );
}

function BounceBanner({ pct }) {
  return (
    <div style={{
      background: liidTokens.fail, color: liidTokens.paper,
      padding: '10px 24px',
      display: 'flex', alignItems: 'center', gap: 16,
      fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.06,
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 999, background: liidTokens.paper,
        animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
      <span style={{ textTransform: 'uppercase', fontWeight: 600, letterSpacing: 0.12 }}>Sending paused</span>
      <span style={{ opacity: 0.85 }}>Bounce rate {pct}% · above the 5% threshold.</span>
    </div>
  );
}

function BucketStrip({ accent, bounceState, bouncePct }) {
  const S = LIID_SENDING_DATA.stats;
  const B = Object.fromEntries(LIID_SENDING_DATA.buckets.map((b) => [b.k, b.n]));
  const sending = B.pending + B.step1 + B.step2 + B.step3;
  const notInterested = B['replied-n'] + B['replied-o'] + B.noreply;

  const tiles = [
    { k: 'sending',       label: 'Sending',        big: sending,             unit: 'contacts',
      sub: `${S.totalSent.toLocaleString()} emails sent`, pulse: true },
    { k: 'callready',     label: 'Call ready',     big: B.callready,         unit: 'contacts',
      sub: 'awaiting follow-up', tone: 'accent' },
    { k: 'interested',    label: 'Interested',     big: B['replied-y'],      unit: 'contacts',
      sub: `${S.interestRate}% interest rate`, tone: 'accent', active: true },
    { k: 'notinterested', label: 'Not interested', big: notInterested,       unit: 'contacts',
      sub: `${S.replyRate}% reply rate · healthy` },
    { k: 'failed',        label: 'Failed',         big: B.failed,            unit: 'contacts',
      sub: 'retry available', tone: 'fail' },
    { k: 'bounced',       label: 'Bounced',        big: bouncePct,           unit: '%',
      sub: `${B.bounced} contacts · ${bounceState === 'normal' ? 'healthy' : (bounceState === 'warn' ? 'watch closely' : 'paused')}`,
      tone: bounceState === 'normal' ? 'default' : (bounceState === 'warn' ? 'warn' : 'fail') },
  ];

  return (
    <div style={{
      display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)',
      border: `1px solid ${liidTokens.rule}`, borderRadius: 2,
      background: liidTokens.paper,
    }}>
      {tiles.map((t, i) => (
        <BucketTile key={t.k} tile={t} accent={accent} last={i === tiles.length - 1} />
      ))}
    </div>
  );
}

function BucketTile({ tile, accent, last }) {
  const t = tile;
  const toneColor =
    t.tone === 'accent' ? accent :
    t.tone === 'fail'   ? liidTokens.fail :
    t.tone === 'warn'   ? liidTokens.warn :
    liidTokens.ink;

  return (
    <button style={{
      padding: '14px 18px',
      borderRight: last ? 'none' : `1px solid ${liidTokens.rule}`,
      background: t.active ? liidTokens.paperAlt : 'transparent',
      border: 'none',
      cursor: 'pointer',
      textAlign: 'left',
      position: 'relative',
      fontFamily: liidTokens.sans,
      transition: 'background .12s',
    }}>
      {t.active && (
        <span style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 2, background: accent }} />
      )}
      {/* Label row */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
          textTransform: 'uppercase',
          color: liidTokens.ink55,
        }}>
          {t.pulse && (
            <span style={{ width: 5, height: 5, borderRadius: 999, background: toneColor,
              animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
          )}
          {t.label}
        </span>
      </div>
      {/* Big number + unit */}
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
        <span style={{
          fontFamily: liidTokens.serif, fontSize: 36, fontWeight: 400,
          letterSpacing: -0.6, lineHeight: 1, color: toneColor,
          fontVariantNumeric: 'tabular-nums',
        }}>{t.big}</span>
        <span style={{
          fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
        }}>{t.unit}</span>
      </div>
      {/* Subtext */}
      <div style={{
        marginTop: 10, paddingTop: 8,
        borderTop: `1px solid ${liidTokens.rule}`,
        fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink55, letterSpacing: 0.04,
      }}>
        {t.sub}
      </div>
    </button>
  );
}

function ContactList({ accent }) {
  const D = window.LIID_DATA;
  const rows = D.VISIBLE_ROWS.slice(0, 14);
  return (
    <div style={{
      borderRight: `1px solid ${liidTokens.rule}`,
      overflow: 'auto',
      background: liidTokens.paper,
    }} className="liid-scroll">
      <div style={{
        padding: '10px 16px',
        borderBottom: `1px solid ${liidTokens.rule}`,
        display: 'flex', alignItems: 'center', gap: 10,
        fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink55, letterSpacing: 0.04,
      }}>
        <LiidIcon name="search" size={11} color={liidTokens.ink55} />
        <span>search contacts…</span>
        <span style={{ flex: 1 }} />
        <span>430</span>
      </div>
      {rows.map((c, i) => {
        const isActive = i === 1;
        const states = [
          { label: 'step 2 sent', col: liidTokens.ink70 },
          { label: 'interested',  col: accent },
          { label: 'step 1 sent', col: liidTokens.ink70 },
          { label: 'replied · OOO', col: liidTokens.ink55 },
          { label: 'no reply',    col: liidTokens.ink40 },
          { label: 'pending',     col: liidTokens.ink55 },
          { label: 'bounced',     col: liidTokens.warn },
          { label: 'call ready',  col: accent },
          { label: 'step 3 sent', col: liidTokens.ink70 },
          { label: 'not interested', col: liidTokens.ink55 },
          { label: 'no reply',    col: liidTokens.ink40 },
          { label: 'step 2 sent', col: liidTokens.ink70 },
          { label: 'failed',      col: liidTokens.fail },
          { label: 'step 1 sent', col: liidTokens.ink70 },
        ];
        const s = states[i];
        return (
          <div key={i} style={{
            padding: '11px 16px',
            borderBottom: `1px solid ${liidTokens.rule}`,
            background: isActive ? liidTokens.paperAlt : 'transparent',
            position: 'relative',
            cursor: 'pointer',
          }}>
            {isActive && <span style={{ position: 'absolute', left: 0, top: 4, bottom: 4, width: 2, background: accent }} />}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 3 }}>
              <span style={{ fontSize: 13, color: liidTokens.ink, fontWeight: isActive ? 600 : 500 }}>
                {c.person || 'Mart Tamm'}
              </span>
              <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: s.col, letterSpacing: 0.04 }}>
                {s.label}
              </span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: liidTokens.ink55 }}>
              <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {c.title} · {c.name}
              </span>
              <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, flexShrink: 0, marginLeft: 8 }}>
                {['2d','17h','4d','6d','12d','—','3d','19h','7d','5d','11d','3d','—','9h'][i]}
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

Object.assign(window, { ViewSendingFunnel });
