// View 4 — Companies list with per-row enrichment progress (HERO)
// Has 3 viz styles for the enrichment row: 'pills', 'bar', 'log'
// Also includes Export modal as a tweak.

function View4Funnel({ accent, density, viz = 'pills', expanded = null, showExport = false }) {
  const D = window.LIID_DATA;
  const compact = density === 'compact';

  return (
    <LiidScreen accent={accent} density={density} step={4}>
      <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0, gap: 18 }}>
        {/* Header row: title + counts + actions */}
        <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: 24 }}>
          <div>
            <div style={{
              fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.12,
              textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 6,
            }}>05 / Funnel · Nordic CTOs Q2</div>
            <h1 style={{
              fontFamily: liidTokens.serif, fontWeight: 400,
              fontSize: 44, lineHeight: 1, letterSpacing: -0.8, margin: 0,
            }}>Enriching <span style={{ color: accent }}>847</span> companies.</h1>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <LiidBtn small><LiidIcon name="filter" size={11} />Filter</LiidBtn>
            <LiidBtn small><LiidIcon name="grid" size={11} />Columns</LiidBtn>
            <LiidBtn small primary mono><LiidIcon name="download" size={11} color={liidTokens.paper} />Export</LiidBtn>
          </div>
        </div>

        {/* Stats strip */}
        <StatsStrip accent={accent} />

        {/* Pipeline meta */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 24,
          fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
          padding: '8px 0',
        }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: accent,
              animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
            running · 14 workers · 4.2/s
          </span>
          <span>queue: 422</span>
          <span>elapsed: 00:18:42</span>
          <span>eta: 00:34:11</span>
          <span style={{ marginLeft: 'auto' }}>
            sort: <span style={{ color: liidTokens.ink }}>status ↓</span> · 28 of 847 visible
          </span>
        </div>

        {/* Table */}
        <div style={{
          flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column',
          border: `1px solid ${liidTokens.rule}`,
          borderRadius: 2,
        }}>
          <FunnelHeader compact={compact} viz={viz} />
          <div style={{ flex: 1, overflow: 'auto' }} className="liid-scroll">
            {D.VISIBLE_ROWS.map((row, i) => (
              <FunnelRow key={row.reg + i} row={row} accent={accent} compact={compact} viz={viz}
                expanded={expanded === i} idx={i} />
            ))}
          </div>
        </div>
      </div>

      {showExport && <ExportModal accent={accent} />}
    </LiidScreen>
  );
}

function StatsStrip({ accent }) {
  const stats = [
    { k: 'queued',   n: 422, label: 'Queued',     pct: 49.8, color: liidTokens.ink40 },
    { k: 'working',  n: 113, label: 'Working',    pct: 13.3, color: accent, pulse: true },
    { k: 'done',     n: 268, label: 'Enriched',   pct: 31.6, color: accent },
    { k: 'rejected', n: 31,  label: 'ICP miss',   pct: 3.7,  color: liidTokens.ink40 },
    { k: 'failed',   n: 13,  label: 'Failed',     pct: 1.5,  color: liidTokens.fail },
  ];
  return (
    <div style={{ display: 'flex', border: `1px solid ${liidTokens.rule}`, borderRadius: 2 }}>
      {stats.map((s, i) => (
        <div key={s.k} style={{
          flex: 1, padding: '14px 18px',
          borderRight: i < stats.length - 1 ? `1px solid ${liidTokens.rule}` : 'none',
          position: 'relative',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
            <span style={{ fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
              textTransform: 'uppercase', color: liidTokens.ink55,
              display: 'flex', alignItems: 'center', gap: 6 }}>
              {s.pulse && <span style={{ width: 5, height: 5, borderRadius: 999, background: s.color,
                animation: 'liid-pulse 1.4s ease-in-out infinite' }} />}
              {s.label}
            </span>
            <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40 }}>{s.pct}%</span>
          </div>
          <div style={{
            fontFamily: liidTokens.serif, fontSize: 36, fontWeight: 400, lineHeight: 1,
            letterSpacing: -0.6, color: liidTokens.ink, fontVariantNumeric: 'tabular-nums',
          }}>{s.n}</div>
          <div style={{ marginTop: 12, height: 2, background: liidTokens.ink10, position: 'relative' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${s.pct * 2}%`, background: s.color, maxWidth: '100%' }} />
          </div>
        </div>
      ))}
    </div>
  );
}

function FunnelHeader({ compact, viz }) {
  const cell = {
    fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
    textTransform: 'uppercase', color: liidTokens.ink55, padding: '11px 0',
  };
  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: compact
        ? '24px 1.5fr 1fr 70px 60px 2fr 100px 1fr'
        : '28px 1.6fr 1.1fr 80px 70px 2.2fr 110px 1.1fr',
      alignItems: 'center', gap: 12,
      padding: '0 16px',
      borderBottom: `1px solid ${liidTokens.rule}`,
      background: liidTokens.paperAlt,
    }}>
      <span style={cell}>
        <span style={{ width: 12, height: 12, border: `1px solid ${liidTokens.ink40}`, display: 'inline-block', borderRadius: 2 }} />
      </span>
      <span style={cell}>Company</span>
      <span style={cell}>Industry</span>
      <span style={{ ...cell, textAlign: 'right' }}>Size</span>
      <span style={{ ...cell, textAlign: 'center' }}>Growth</span>
      <span style={cell}>Enrichment</span>
      <span style={cell}>Contact</span>
      <span style={{ ...cell, textAlign: 'right' }}>Status</span>
    </div>
  );
}

function FunnelRow({ row, accent, compact, viz, expanded, idx }) {
  return (
    <div style={{ borderBottom: `1px solid ${liidTokens.rule}` }}>
      <div style={{
        display: 'grid',
        gridTemplateColumns: compact
          ? '24px 1.5fr 1fr 70px 60px 2fr 100px 1fr'
          : '28px 1.6fr 1.1fr 80px 70px 2.2fr 110px 1.1fr',
        alignItems: 'center', gap: 12,
        padding: compact ? '8px 16px' : '12px 16px',
        background: row.state === 'working' ? `${accent}06` : 'transparent',
        ...(expanded ? { background: liidTokens.paperAlt } : {}),
      }}>
        <span style={{
          width: 12, height: 12, border: `1px solid ${liidTokens.ink40}`,
          display: 'inline-block', borderRadius: 2,
        }} />
        <div>
          <div style={{ fontSize: 13, color: liidTokens.ink, fontWeight: 500 }}>{row.name}</div>
          <div style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, marginTop: 2, letterSpacing: 0.04 }}>
            {row.domain || <span style={{ fontStyle: 'italic' }}>resolving...</span>} · {row.reg}
          </div>
        </div>
        <span style={{ fontSize: 12, color: liidTokens.ink55 }}>{row.industry}</span>
        <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>
          {row.size.toLocaleString()}
        </span>
        <span style={{ display: 'flex', justifyContent: 'center' }}>
          <GrowthGlyphLg g={row.growth} accent={accent} />
        </span>
        <EnrichmentViz row={row} accent={accent} viz={viz} />
        <ContactCell row={row} accent={accent} />
        <StatusCell row={row} accent={accent} />
      </div>
      {expanded && <ExpandedDetail row={row} accent={accent} />}
    </div>
  );
}

function GrowthGlyphLg({ g, accent }) {
  const heights = { shrinking: [4,3,2,1], stagnant: [3,3,3,3], slow: [2,3,4,5], '2x': [2,4,6,8], '10x': [2,5,8,11] };
  const colors = { shrinking: liidTokens.warn, stagnant: liidTokens.ink40, slow: liidTokens.ink70, '2x': accent, '10x': accent };
  const h = heights[g] || heights.slow;
  const c = colors[g] || colors.slow;
  return (
    <span style={{ display: 'flex', alignItems: 'flex-end', gap: 1.5, height: 12 }}>
      {h.map((v, i) => (
        <span key={i} style={{
          width: 3, height: v, background: c,
          opacity: g === '10x' && i === 3 ? 1 : (g === '2x' && i >= 2 ? 1 : 0.85),
        }} />
      ))}
    </span>
  );
}

function EnrichmentViz({ row, accent, viz }) {
  if (viz === 'log')  return <LogViz row={row} accent={accent} />;
  if (viz === 'bar')  return <BarViz row={row} accent={accent} />;
  return <PillsViz row={row} accent={accent} />;
}

// Style A: Step pills with status dots (default)
function PillsViz({ row, accent }) {
  const D = window.LIID_DATA;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      {D.STAGE_KEYS.map((k, i) => {
        const st = row.progress[k];
        return (
          <React.Fragment key={k}>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              padding: '3px 7px',
              fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.04,
              border: `1px solid ${st === 'work' ? accent : (st === 'fail' ? liidTokens.fail : (st === 'fall' ? liidTokens.warn : liidTokens.ink20))}`,
              background: st === 'done' ? `${accent}14` : (st === 'work' ? `${accent}1f` : 'transparent'),
              color: st === 'idle' ? liidTokens.ink40 : (st === 'fail' ? liidTokens.fail : (st === 'fall' ? liidTokens.warn : liidTokens.ink)),
              borderRadius: 2,
              opacity: st === 'idle' ? 0.55 : 1,
            }}>
              <StatusDot state={st} accent={accent} size={6} />
              {D.STAGE_LABEL[k]}
            </span>
            {i < D.STAGE_KEYS.length - 1 && (
              <span style={{ width: 4, height: 1, background: liidTokens.ink20 }} />
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
}

// Style B: Segmented progress bar
function BarViz({ row, accent }) {
  const D = window.LIID_DATA;
  return (
    <div>
      <div style={{ display: 'flex', gap: 2, height: 6 }}>
        {D.STAGE_KEYS.map((k) => {
          const st = row.progress[k];
          const map = {
            idle: liidTokens.ink10,
            work: accent,
            done: accent,
            skip: liidTokens.ink20,
            fall: liidTokens.warn,
            fail: liidTokens.fail,
          };
          return (
            <span key={k} style={{
              flex: 1,
              background: map[st],
              opacity: st === 'work' ? 1 : (st === 'idle' ? 1 : 0.9),
              animation: st === 'work' ? 'liid-pulse 1.4s ease-in-out infinite' : 'none',
            }} />
          );
        })}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6,
        fontFamily: liidTokens.mono, fontSize: 9, color: liidTokens.ink40, letterSpacing: 0.04 }}>
        {D.STAGE_KEYS.map((k) => {
          const st = row.progress[k];
          return (
            <span key={k} style={{
              flex: 1, textAlign: 'center',
              color: st === 'work' ? accent : (st === 'done' ? liidTokens.ink70 : liidTokens.ink40),
            }}>{D.STAGE_LABEL[k].slice(0, 4).toLowerCase()}</span>
          );
        })}
      </div>
    </div>
  );
}

// Style C: Live log line
function LogViz({ row, accent }) {
  const lines = {
    'queued':     { txt: 'queued · waiting for worker', col: liidTokens.ink40 },
    'working':    { txt: getWorkingMsg(row), col: accent, live: true },
    'done':       { txt: `✓ enriched · ${row.contacts} contact${row.contacts===1?'':'s'} · ${row.pagesFound}p`, col: liidTokens.ink70 },
    'skip-icp':   { txt: 'skipped · doesn\'t match ICP', col: liidTokens.ink40 },
    'fallback':   { txt: 'gov website 404 · googling…', col: liidTokens.warn, live: true },
    'no-contact': { txt: '✗ no verifiable contact (LLM hallucinated email)', col: liidTokens.fail },
    'failed':     { txt: '✗ wallaby blocked by cloudflare on /careers', col: liidTokens.fail },
  };
  const line = lines[row.state] || lines.queued;
  return (
    <div style={{
      fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.02,
      color: line.col, display: 'flex', alignItems: 'center', gap: 8,
      whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
    }}>
      {line.live && <span style={{ width: 5, height: 5, borderRadius: 999, background: line.col, animation: 'liid-pulse 1.4s ease-in-out infinite', flexShrink: 0 }} />}
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{line.txt}</span>
    </div>
  );
}

function getWorkingMsg(row) {
  const p = row.progress;
  if (p.scrape === 'work') return `scraping /careers /team /about · ${row.pagesFound}p found`;
  if (p.parse === 'work')  return 'minimising html → markdown · 14kb → 2.1kb';
  if (p.icp === 'work')    return 'asking gpt-4o · "does this match ICP?"';
  if (p.contact === 'work') return 'searching for CTO contact · 3 candidate pages';
  if (p.verify === 'work') return 'verifying email exists in markdown…';
  return 'fetching landing page…';
}

function ContactCell({ row, accent }) {
  if (row.state === 'done') {
    return (
      <div style={{ minWidth: 0 }}>
        <div style={{ fontSize: 12, color: liidTokens.ink, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{row.person}</div>
        <div style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {row.title}
        </div>
      </div>
    );
  }
  if (row.state === 'no-contact') {
    return <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.fail }}>hallucinated</span>;
  }
  if (row.state === 'skip-icp') {
    return <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink40 }}>—</span>;
  }
  return (
    <span style={{
      display: 'inline-block', height: 8, width: '70%',
      background: liidTokens.ink10, borderRadius: 1,
    }} className="liid-shimmer" />
  );
}

function StatusCell({ row, accent }) {
  const map = {
    queued:      { label: 'queued',     col: liidTokens.ink40, dot: liidTokens.ink40 },
    working:     { label: 'working',    col: accent,           dot: accent, pulse: true },
    done:        { label: 'enriched',   col: accent,           dot: accent },
    'skip-icp':  { label: 'icp miss',   col: liidTokens.ink40, dot: liidTokens.ink40 },
    fallback:    { label: 'searching',  col: liidTokens.warn,  dot: liidTokens.warn, pulse: true },
    'no-contact':{ label: 'no contact', col: liidTokens.fail,  dot: liidTokens.fail },
    failed:      { label: 'failed',     col: liidTokens.fail,  dot: liidTokens.fail },
  };
  const s = map[row.state] || map.queued;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'flex-end',
      fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.04, color: s.col }}>
      <span style={{
        width: 6, height: 6, borderRadius: 999, background: s.dot,
        animation: s.pulse ? 'liid-pulse 1.4s ease-in-out infinite' : 'none',
      }} />
      {s.label}
    </div>
  );
}

function ExpandedDetail({ row, accent }) {
  return (
    <div style={{
      padding: '20px 24px 24px 56px',
      background: liidTokens.paperAlt,
      borderTop: `1px solid ${liidTokens.rule}`,
      display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 32,
    }}>
      {/* Pipeline log */}
      <div>
        <div style={{ fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
          textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 12 }}>
          Pipeline
        </div>
        <div style={{ fontFamily: liidTokens.mono, fontSize: 11, lineHeight: 1.7, color: liidTokens.ink70 }}>
          {[
            ['18:42:01', '✓', 'rik.ee returned domain ' + (row.domain || 'pipedrive.com')],
            ['18:42:02', '✓', 'GET https://' + (row.domain || 'pipedrive.com') + ' → 200'],
            ['18:42:03', '✓', 'extracted 8 nav paths · /pricing /docs /careers /team /about /blog /security /contact'],
            ['18:42:04', '✓', 'regex hit · hello@' + (row.domain || 'pipedrive.com') + ' (generic)'],
            ['18:42:06', '✓', 'minified 84kb → 2.4kb md'],
            ['18:42:08', '✓', 'gpt-4o summary saved'],
            ['18:42:11', '✓', 'icp match: 0.86 · "B2B saas, EU-based, eng-led"'],
            ['18:42:13', '✓', 'candidate pages for CTO contact: /team, /careers, /about'],
            ['18:42:18', '✓', 'gpt-4o → ' + (row.email || 'm.tamm@example.com')],
            ['18:42:18', '✓', 'verified · email present in /team markdown'],
            ['18:42:18', '✓', 'saved to people · belongs_to ' + row.name.split(' ')[0].toLowerCase()],
          ].map(([t, s, m], i) => (
            <div key={i} style={{ display: 'grid', gridTemplateColumns: '70px 14px 1fr', gap: 8 }}>
              <span style={{ color: liidTokens.ink40 }}>{t}</span>
              <span style={{ color: accent }}>{s}</span>
              <span>{m}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Result card */}
      <div>
        <div style={{ fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
          textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 12 }}>
          Extracted contact
        </div>
        <div style={{ padding: '18px 20px', background: liidTokens.paper, border: `1px solid ${liidTokens.ink20}`, borderRadius: 2 }}>
          <div style={{ fontFamily: liidTokens.serif, fontSize: 24, letterSpacing: -0.4, marginBottom: 4 }}>
            {row.person || 'Mart Tamm'}
          </div>
          <div style={{ fontSize: 13, color: liidTokens.ink55, marginBottom: 16 }}>
            {row.title || 'CTO'} · {row.name}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, fontFamily: liidTokens.mono, fontSize: 11 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <LiidIcon name="mail" size={11} color={liidTokens.ink55} />
              <span style={{ color: liidTokens.ink }}>{row.email || 'm.tamm@pipedrive.com'}</span>
              <span style={{ marginLeft: 'auto', color: accent, fontSize: 10 }}>verified</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <LiidIcon name="link" size={11} color={liidTokens.ink55} />
              <span style={{ color: liidTokens.ink }}>{(row.domain || 'pipedrive.com') + '/team#m-tamm'}</span>
            </div>
          </div>
          <div style={{ marginTop: 16, paddingTop: 14, borderTop: `1px solid ${liidTokens.rule}`,
            fontSize: 12, color: liidTokens.ink70, lineHeight: 1.5 }}>
            "{row.name.split(' ')[0]} builds CRM software for B2B sales teams.
            ~920 employees, HQ Tallinn, primary market US/EU mid-market."
          </div>
        </div>
      </div>
    </div>
  );
}

function ExportModal({ accent }) {
  const formats = [
    { f: 'CSV',     d: 'Flat sheet · companies + primary contact', s: '847 rows' },
    { f: 'JSON',    d: 'Nested · companies → people → pages',     s: '2.4 MB' },
    { f: 'HubSpot', d: 'Push directly · de-dupe by domain',        s: 'requires auth' },
    { f: 'Pipedrive',d: 'Push directly · org + person + deal',     s: 'requires auth' },
    { f: 'Apollo',  d: 'Add to sequence',                          s: 'requires auth' },
    { f: 'Webhook', d: 'POST to your URL',                          s: 'paste url' },
  ];
  return (
    <div style={{
      position: 'absolute', inset: 0, background: 'rgba(20,18,14,0.45)',
      backdropFilter: 'blur(2px)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 10,
    }}>
      <div style={{
        width: 640, background: liidTokens.paper,
        border: `1px solid ${liidTokens.ink20}`, borderRadius: 2,
        boxShadow: '0 24px 80px rgba(0,0,0,0.18)',
        padding: '32px 36px 28px',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
          <div>
            <div style={{ fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
              textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 6 }}>
              Export · Nordic CTOs Q2
            </div>
            <h2 style={{ fontFamily: liidTokens.serif, fontWeight: 400, fontSize: 32,
              letterSpacing: -0.6, lineHeight: 1, margin: 0 }}>
              Take 312 enriched companies somewhere.
            </h2>
          </div>
          <span style={{ width: 24, height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
            <LiidIcon name="x" size={14} color={liidTokens.ink55} />
          </span>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 8 }}>
          {formats.map((x, i) => (
            <div key={x.f} style={{
              padding: '14px 16px',
              border: `1px solid ${i === 0 ? accent : liidTokens.ink20}`,
              background: i === 0 ? `${accent}08` : 'transparent',
              borderRadius: 2, cursor: 'pointer',
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontSize: 14, fontWeight: 600, color: liidTokens.ink }}>{x.f}</span>
                <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40 }}>{x.s}</span>
              </div>
              <div style={{ fontSize: 12, color: liidTokens.ink55, marginTop: 4 }}>{x.d}</div>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 20, padding: '14px 16px', background: liidTokens.paperAlt, borderRadius: 2,
          fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, lineHeight: 1.6 }}>
          <div style={{ color: liidTokens.ink70, marginBottom: 4 }}>nordic-ctos-q2.csv · preview</div>
          name,domain,industry,size,growth,person,title,email,verified<br/>
          Bolt Technology OÜ,bolt.eu,Mobility,4200,10x,Mart Tamm,CTO,m.tamm@bolt.eu,true<br/>
          Pipedrive AS,pipedrive.com,SaaS,920,2x,Liis Saar,VP Eng,l.saar@pipe…
        </div>

        <div style={{ display: 'flex', gap: 12, marginTop: 24 }}>
          <LiidBtn small>Cancel</LiidBtn>
          <span style={{ flex: 1 }} />
          <LiidBtn primary mono>
            <LiidIcon name="download" size={11} color={liidTokens.paper} />
            Download CSV
          </LiidBtn>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { View4Funnel, ExportModal });
