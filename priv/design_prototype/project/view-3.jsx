// View 3 — Filters with realtime counter + live preview list

function View3Filters({ accent, density }) {
  const D = window.LIID_DATA;
  const matched = 847;
  const total = 142180;
  const pct = (matched / 1000) * 100;

  // Active filters
  const industries = ['SaaS', 'FinTech', 'IT Services', 'Robotics'];
  const sizeRange = [50, 500];

  // Growth pills
  const growthOpts = [
    { k: 'shrinking', label: 'Shrinking', n: 12 },
    { k: 'stagnant',  label: 'Stagnant',  n: 84 },
    { k: 'slow',      label: 'Growing · slow',  n: 412, on: true },
    { k: '2x',        label: 'Growing · 2×',    n: 286, on: true },
    { k: '10x',       label: 'Growing · 10×',   n: 53,  on: true },
  ];

  return (
    <LiidScreen accent={accent} density={density} step={3}>
      <div style={{ display: 'flex', gap: 48, flex: 1, minHeight: 0 }}>
        {/* LEFT: filter panel */}
        <div style={{ flex: '0 0 360px', display: 'flex', flexDirection: 'column', gap: 28, minHeight: 0 }}>
          <LiidH kicker="04 / Filters" title={<>Narrow the <em style={{ fontStyle: 'italic', color: accent }}>funnel</em>.</>} />

          <div style={{ display: 'flex', flexDirection: 'column', gap: 24, overflow: 'auto' }} className="liid-scroll">
            {/* Industry */}
            <Fset label="Industry" hint={`${industries.length} selected`}>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                {['SaaS','FinTech','IT Services','Robotics','Manufacturing','Logistics','E-commerce','Construction','Maritime','Cleantech','+ 32 more'].map((t, i) => {
                  const on = industries.includes(t);
                  const more = t.startsWith('+');
                  return (
                    <span key={t} style={{
                      padding: '5px 10px', fontSize: 12,
                      border: `1px solid ${on ? accent : liidTokens.ink20}`,
                      background: on ? accent : 'transparent',
                      color: on ? liidTokens.paper : (more ? liidTokens.ink55 : liidTokens.ink),
                      fontFamily: more ? liidTokens.mono : liidTokens.sans,
                      fontSize: more ? 11 : 12,
                      borderRadius: 2, cursor: 'pointer',
                    }}>{t}</span>
                  );
                })}
              </div>
            </Fset>

            {/* Employee count slider */}
            <Fset label="Employees" hint={`${sizeRange[0]} – ${sizeRange[1]}`}>
              <div style={{ position: 'relative', height: 28, marginTop: 4 }}>
                <div style={{ position: 'absolute', left: 0, right: 0, top: 12, height: 1, background: liidTokens.ink20 }} />
                <div style={{ position: 'absolute', left: '5%', right: '50%', top: 11, height: 3, background: accent }} />
                <div style={{ position: 'absolute', left: 'calc(5% - 6px)', top: 6, width: 12, height: 12, borderRadius: 999, background: liidTokens.paper, border: `1.5px solid ${accent}` }} />
                <div style={{ position: 'absolute', left: 'calc(50% - 6px)', top: 6, width: 12, height: 12, borderRadius: 999, background: liidTokens.paper, border: `1.5px solid ${accent}` }} />
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, marginTop: 4 }}>
                <span>1</span><span>10</span><span>50</span><span>500</span><span>5k+</span>
              </div>
            </Fset>

            {/* Growth */}
            <Fset label="Trajectory" hint="3 selected">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {growthOpts.map((g) => (
                  <label key={g.k} style={{
                    display: 'flex', alignItems: 'center', gap: 10,
                    padding: '8px 10px', cursor: 'pointer',
                    background: g.on ? `${accent}11` : 'transparent',
                    borderLeft: `2px solid ${g.on ? accent : 'transparent'}`,
                  }}>
                    <span style={{
                      width: 12, height: 12, border: `1px solid ${g.on ? accent : liidTokens.ink40}`,
                      background: g.on ? accent : 'transparent',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      borderRadius: 2,
                    }}>
                      {g.on && <LiidIcon name="check" size={9} color={liidTokens.paper} />}
                    </span>
                    <span style={{ fontSize: 13, color: liidTokens.ink, flex: 1 }}>{g.label}</span>
                    <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink40 }}>{g.n}</span>
                  </label>
                ))}
              </div>
              <div style={{ fontSize: 11, color: liidTokens.ink40, marginTop: 6, fontFamily: liidTokens.mono, letterSpacing: 0.04 }}>
                growth = revenue Δ over 3 fiscal years
              </div>
            </Fset>

            {/* Region */}
            <Fset label="Region">
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                {['Tallinn','Tartu','Pärnu','Narva','Viljandi','elsewhere'].map((c, i) => (
                  <span key={c} style={{
                    padding: '5px 10px', fontSize: 12,
                    border: `1px solid ${i < 2 ? accent : liidTokens.ink20}`,
                    background: i < 2 ? accent : 'transparent',
                    color: i < 2 ? liidTokens.paper : liidTokens.ink,
                    borderRadius: 2,
                  }}>{c}</span>
                ))}
              </div>
            </Fset>

            {/* Founded year */}
            <Fset label="Founded" hint="2014 — 2024">
              <div style={{ display: 'flex', gap: 8 }}>
                <div style={{ flex: 1, padding: '8px 10px', border: `1px solid ${liidTokens.ink20}`, fontFamily: liidTokens.mono, fontSize: 12, borderRadius: 2 }}>2014</div>
                <span style={{ alignSelf: 'center', color: liidTokens.ink40 }}>—</span>
                <div style={{ flex: 1, padding: '8px 10px', border: `1px solid ${liidTokens.ink20}`, fontFamily: liidTokens.mono, fontSize: 12, borderRadius: 2 }}>2024</div>
              </div>
            </Fset>

            {/* Has website registered */}
            <Fset label="Signals">
              {['Has registered website','VAT registered','Filed annual report 2024'].map((s, i) => (
                <label key={s} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 0', cursor: 'pointer' }}>
                  <span style={{
                    width: 12, height: 12, border: `1px solid ${i < 2 ? accent : liidTokens.ink40}`,
                    background: i < 2 ? accent : 'transparent',
                    display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 2,
                  }}>
                    {i < 2 && <LiidIcon name="check" size={9} color={liidTokens.paper} />}
                  </span>
                  <span style={{ fontSize: 13, color: liidTokens.ink }}>{s}</span>
                </label>
              ))}
            </Fset>
          </div>
        </div>

        {/* RIGHT: counter + live preview */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0, gap: 20 }}>
          {/* Counter */}
          <div style={{
            border: `1px solid ${liidTokens.ink20}`,
            background: liidTokens.paperAlt,
            padding: '24px 28px',
            position: 'relative',
            borderRadius: 2,
          }}>
            <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
              <div>
                <div style={{
                  fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
                  textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 8,
                }}>Companies match</div>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
                  <div style={{
                    fontFamily: liidTokens.serif, fontSize: 76, fontWeight: 400,
                    letterSpacing: -2, lineHeight: 0.9, color: liidTokens.ink,
                    fontVariantNumeric: 'tabular-nums',
                  }}>847</div>
                  <div style={{ fontFamily: liidTokens.mono, fontSize: 12, color: liidTokens.ink55, paddingBottom: 8 }}>
                    of 142,180
                  </div>
                </div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12, textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 8 }}>
                  Funnel cap
                </div>
                <div style={{ fontFamily: liidTokens.serif, fontSize: 28, color: liidTokens.ink, letterSpacing: -0.4 }}>
                  1,000
                </div>
              </div>
            </div>
            {/* Capacity bar */}
            <div style={{ marginTop: 22, position: 'relative', height: 6, background: liidTokens.ink10, borderRadius: 1 }}>
              <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${pct}%`, background: accent }} />
              {/* tick marks */}
              {[0.25, 0.5, 0.75].map((t) => (
                <div key={t} style={{ position: 'absolute', left: `${t*100}%`, top: -3, bottom: -3, width: 1, background: liidTokens.ink20 }} />
              ))}
            </div>
            <div style={{ marginTop: 10, display: 'flex', justifyContent: 'space-between',
              fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04 }}>
              <span>{Math.round(pct)}% of cap</span>
              <span>153 slots remaining</span>
            </div>

            {/* "live" indicator */}
            <div style={{
              position: 'absolute', top: 24, right: 28,
              display: 'flex', alignItems: 'center', gap: 6,
              fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.08,
              color: accent, textTransform: 'uppercase',
              display: 'none',
            }}>
              <span style={{ width: 6, height: 6, borderRadius: 999, background: accent,
                animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
              live
            </div>
          </div>

          {/* Active chips */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center' }}>
            <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, letterSpacing: 0.12, textTransform: 'uppercase', marginRight: 4 }}>active</span>
            {['Industry · 4','Employees · 50–500','Trajectory · growing','Region · Tallinn, Tartu','Has website','VAT registered'].map((t) => (
              <span key={t} style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                padding: '4px 8px', fontSize: 11,
                background: liidTokens.paperAlt, border: `1px solid ${liidTokens.ink20}`,
                borderRadius: 2,
              }}>
                {t}
                <LiidIcon name="x" size={9} color={liidTokens.ink55} />
              </span>
            ))}
          </div>

          {/* Live preview list */}
          <div style={{
            flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column',
            border: `1px solid ${liidTokens.rule}`,
            borderRadius: 2,
            position: 'relative',
          }}>
            <div style={{
              padding: '12px 16px',
              borderBottom: `1px solid ${liidTokens.rule}`,
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.04, color: liidTokens.ink55,
            }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ width: 6, height: 6, borderRadius: 999, background: accent,
                  animation: 'liid-pulse 1.4s ease-in-out infinite' }} />
                preview · updated 0.2s ago
              </span>
              <span>showing 12 of 847</span>
            </div>
            <div style={{ flex: 1, overflow: 'auto' }} className="liid-scroll">
              {D.COMPANY_SEEDS.slice(0, 14).map((c, i) => (
                <div key={c.reg} style={{
                  display: 'grid',
                  gridTemplateColumns: '1fr 140px 80px 60px',
                  alignItems: 'center', gap: 16,
                  padding: '11px 16px',
                  borderBottom: i < 13 ? `1px solid ${liidTokens.rule}` : 'none',
                  fontSize: 13,
                  ...(i === 1 ? { background: `${accent}08` } : {}),
                }}>
                  <span style={{ color: liidTokens.ink, fontWeight: 500 }}>{c.name}</span>
                  <span style={{ color: liidTokens.ink55, fontSize: 12 }}>{c.industry}</span>
                  <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, textAlign: 'right' }}>{c.size}</span>
                  <GrowthGlyph g={c.growth} accent={accent} />
                </div>
              ))}
            </div>
            {/* fade */}
            <div style={{
              position: 'absolute', bottom: 0, left: 0, right: 0, height: 60,
              background: `linear-gradient(180deg, transparent, ${liidTokens.paper})`,
              pointerEvents: 'none',
            }} />
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <LiidBtn small><LiidIcon name="chevL" size={11} />Back</LiidBtn>
            <LiidBtn primary mono>
              Run enrichment on 847
              <LiidIcon name="spark" size={13} color={liidTokens.paper} />
            </LiidBtn>
            <span style={{ flex: 1 }} />
            <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink40 }}>
              ~ €0.18 / company · est. €152.46
            </span>
          </div>
        </div>
      </div>
    </LiidScreen>
  );
}

function Fset({ label, hint, children }) {
  return (
    <div>
      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
        marginBottom: 10, paddingBottom: 8,
        borderBottom: `1px solid ${liidTokens.rule}`,
      }}>
        <span style={{
          fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.08,
          textTransform: 'uppercase', color: liidTokens.ink70,
        }}>{label}</span>
        {hint && (
          <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40 }}>{hint}</span>
        )}
      </div>
      {children}
    </div>
  );
}

function GrowthGlyph({ g, accent }) {
  const map = {
    '10x':      { bars: 4, color: accent, label: '10×' },
    '2x':       { bars: 3, color: accent, label: '2×' },
    'slow':     { bars: 2, color: liidTokens.ink55, label: '↗' },
    'stagnant': { bars: 1, color: liidTokens.ink40, label: '→' },
    'shrinking':{ bars: 0, color: liidTokens.warn, label: '↘' },
  };
  const m = map[g] || map.slow;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4, justifyContent: 'flex-end' }}>
      <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: m.color, letterSpacing: 0.04, minWidth: 18, textAlign: 'right' }}>
        {m.label}
      </span>
    </div>
  );
}

Object.assign(window, { View3Filters });
