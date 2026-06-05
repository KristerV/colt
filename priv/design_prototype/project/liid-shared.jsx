// Liid — shared design tokens, atoms, and screen chrome.
// Minimal Scandi: warm paper, ink, generous whitespace, serif accents.

// ── Tokens ─────────────────────────────────────────────────────────────
const liidTokens = {
  paper:    'oklch(98% 0.005 80)',
  paperAlt: 'oklch(96% 0.006 80)',
  ink:      'oklch(20% 0.012 250)',
  ink70:    'oklch(20% 0.012 250 / 0.70)',
  ink55:    'oklch(20% 0.012 250 / 0.55)',
  ink40:    'oklch(20% 0.012 250 / 0.40)',
  ink20:    'oklch(20% 0.012 250 / 0.20)',
  ink10:    'oklch(20% 0.012 250 / 0.10)',
  rule:     'oklch(20% 0.012 250 / 0.12)',
  // accent will be overridden by tweaks
  accent:   'oklch(55% 0.13 145)',
  accentSoft: 'oklch(94% 0.04 145)',
  warn:     'oklch(60% 0.13 60)',
  fail:     'oklch(58% 0.18 28)',
  ok:       'oklch(55% 0.12 145)',
  sans:     '"Inter Tight", "Inter", -apple-system, system-ui, sans-serif',
  serif:    '"Instrument Serif", "Times New Roman", Georgia, serif',
  mono:     '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
};

// ── Status pill ────────────────────────────────────────────────────────
function StatusDot({ state, accent, size = 8 }) {
  const colorMap = {
    idle: liidTokens.ink20,
    work: accent,
    done: accent,
    skip: liidTokens.ink40,
    fall: liidTokens.warn,
    fail: liidTokens.fail,
  };
  const filled = state !== 'idle';
  const isWork = state === 'work';
  return (
    <span style={{
      display: 'inline-block', width: size, height: size, borderRadius: 999,
      background: filled ? colorMap[state] : 'transparent',
      border: `1px solid ${state === 'idle' ? liidTokens.ink20 : colorMap[state]}`,
      boxShadow: isWork ? `0 0 0 3px ${accent}22` : 'none',
      animation: isWork ? 'liid-pulse 1.4s ease-in-out infinite' : 'none',
      flexShrink: 0,
    }} />
  );
}

// ── Small inline icon (hairline stroke) ─────────────────────────────────
function LiidIcon({ name, size = 14, color = 'currentColor' }) {
  const paths = {
    arrow:  'M3 8h10M9 4l4 4-4 4',
    logout: 'M10 3H4v10h6M8 8h6M11 5l3 3-3 3',
    chev:   'M5 6l3 3 3-3',
    chevR:  'M6 4l4 4-4 4',
    chevL:  'M10 4L6 8l4 4',
    plus:   'M8 3v10M3 8h10',
    x:      'M4 4l8 8M12 4l-8 8',
    check:  'M3 8.5l3 3 7-7',
    search: 'M7 12.5a5.5 5.5 0 1 0 0-11 5.5 5.5 0 0 0 0 11zm4-1.5l3 3',
    globe:  'M8 1.5v13M1.5 8h13M8 1.5a8 8 0 0 1 0 13M8 1.5a8 8 0 0 0 0 13',
    spark:  'M8 2v4M8 10v4M2 8h4M10 8h4',
    download: 'M8 2v9M4 7l4 4 4-4M3 14h10',
    file:   'M4 2h6l2 2v10H4V2zM10 2v2h2',
    user:   'M8 8.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5zM3 14c.5-2.5 2.6-4 5-4s4.5 1.5 5 4',
    mail:   'M2 4h12v8H2V4zM2 4l6 5 6-5',
    link:   'M7 9l2-2M6 10a2.5 2.5 0 0 1 0-3.5l2-2a2.5 2.5 0 0 1 3.5 3.5l-1 1M10 6a2.5 2.5 0 0 1 0 3.5l-2 2A2.5 2.5 0 0 1 4.5 8l1-1',
    code:   'M5 5L2 8l3 3M11 5l3 3-3 3M9 3l-2 10',
    filter: 'M2 3h12l-4.5 6v5L7 12V9L2 3z',
    grid:   'M2 2h5v5H2zM9 2h5v5H9zM2 9h5v5H2zM9 9h5v5H9z',
  };
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none"
      stroke={color} strokeWidth="1.25" strokeLinecap="round" strokeLinejoin="round">
      <path d={paths[name]} />
    </svg>
  );
}

// ── Screen chrome shared by every artboard ─────────────────────────────
function LiidScreen({ children, accent, density = 'comfy', step = 0 }) {
  const padX = density === 'compact' ? 32 : 56;
  const padY = density === 'compact' ? 28 : 40;
  return (
    <div style={{
      width: '100%', height: '100%',
      background: liidTokens.paper,
      color: liidTokens.ink,
      fontFamily: liidTokens.sans,
      display: 'flex', flexDirection: 'column',
      ['--accent']: accent,
      ['--ink']: liidTokens.ink,
    }}>
      <LiidTopBar accent={accent} step={step} />
      <div style={{
        flex: 1, padding: `${padY}px ${padX}px`,
        display: 'flex', flexDirection: 'column',
        minHeight: 0,
      }}>
        {children}
      </div>
    </div>
  );
}

function LiidTopBar({ accent, step = 0, campaignName = 'Nordic CTOs Q2' }) {
  const steps = ['Name', 'ICP', 'Market', 'Filters', 'Funnel'];
  return (
    <div style={{
      display: 'flex', alignItems: 'center',
      padding: '20px 32px',
      borderBottom: `1px solid ${liidTokens.rule}`,
      gap: 32,
    }}>
      {/* Wordmark */}
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
        <span style={{
          fontFamily: liidTokens.serif, fontSize: 26, lineHeight: 1,
          letterSpacing: -0.5, fontWeight: 400,
        }}>Liid</span>
        <span style={{
          width: 6, height: 6, borderRadius: 999, background: accent,
          display: 'inline-block', transform: 'translateY(-3px)',
        }} />
      </div>

      {/* Stepper */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 0,
        fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.04,
      }}>
        {steps.map((s, i) => {
          const isActive = i === step;
          const isDone = i < step;
          return (
            <React.Fragment key={s}>
              <div style={{
                display: 'flex', alignItems: 'center', gap: 8,
                padding: '6px 12px',
                color: isActive ? liidTokens.ink : (isDone ? liidTokens.ink55 : liidTokens.ink40),
              }}>
                <span style={{
                  fontFeatureSettings: '"tnum"',
                  color: isActive ? accent : 'inherit',
                  fontWeight: isActive ? 600 : 400,
                }}>{String(i).padStart(2, '0')}</span>
                <span style={{ textTransform: 'uppercase', letterSpacing: 0.08 }}>{s}</span>
              </div>
              {i < steps.length - 1 && (
                <span style={{ width: 14, height: 1, background: liidTokens.ink20 }} />
              )}
            </React.Fragment>
          );
        })}
      </div>

      <div style={{ flex: 1 }} />

      {/* Campaign name + user */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 14,
        fontSize: 12, color: liidTokens.ink55,
      }}>
        <span style={{ fontFamily: liidTokens.mono, letterSpacing: 0.04 }}>
          campaign: <span style={{ color: liidTokens.ink }}>{campaignName}</span>
        </span>
        <span style={{ width: 1, height: 14, background: liidTokens.ink20 }} />
        <div style={{
          width: 24, height: 24, borderRadius: 999, background: liidTokens.ink,
          color: liidTokens.paper, display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 11, fontWeight: 600, letterSpacing: 0,
        }}>K</div>
      </div>
    </div>
  );
}

// ── Buttons ────────────────────────────────────────────────────────────
function LiidBtn({ children, primary, accent, mono, small, onClick, style = {} }) {
  const base = {
    display: 'inline-flex', alignItems: 'center', gap: 8,
    padding: small ? '7px 12px' : '10px 18px',
    fontSize: small ? 12 : 13, fontWeight: 500,
    fontFamily: mono ? liidTokens.mono : liidTokens.sans,
    letterSpacing: mono ? 0.04 : 0,
    border: '1px solid',
    borderRadius: 2,
    cursor: 'pointer',
    transition: 'all .12s',
    ...style,
  };
  if (primary) {
    return <button onClick={onClick} style={{
      ...base,
      background: liidTokens.ink, borderColor: liidTokens.ink, color: liidTokens.paper,
    }}>{children}</button>;
  }
  return <button onClick={onClick} style={{
    ...base,
    background: 'transparent', borderColor: liidTokens.ink20, color: liidTokens.ink,
  }}>{children}</button>;
}

// ── Section header (display: serif) ─────────────────────────────────────
function LiidH({ kicker, title, sub, align = 'left' }) {
  return (
    <div style={{ textAlign: align, maxWidth: 640 }}>
      {kicker && (
        <div style={{
          fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.12,
          textTransform: 'uppercase', color: liidTokens.ink55, marginBottom: 14,
        }}>{kicker}</div>
      )}
      <h1 style={{
        fontFamily: liidTokens.serif, fontWeight: 400,
        fontSize: 64, lineHeight: 1.02, letterSpacing: -1.4,
        margin: 0,
        textWrap: 'pretty',
      }}>{title}</h1>
      {sub && (
        <div style={{
          marginTop: 20, fontSize: 15, lineHeight: 1.5, color: liidTokens.ink55,
          maxWidth: 520, textWrap: 'pretty',
        }}>{sub}</div>
      )}
    </div>
  );
}

// ── Global keyframes ────────────────────────────────────────────────────
if (typeof document !== 'undefined' && !document.getElementById('liid-keys')) {
  const s = document.createElement('style');
  s.id = 'liid-keys';
  s.textContent = `
    @keyframes liid-pulse {
      0%, 100% { opacity: .55; transform: scale(.85); }
      50%      { opacity: 1;  transform: scale(1); }
    }
    @keyframes liid-tick {
      0% { width: 0; }
      100% { width: var(--w, 100%); }
    }
    @keyframes liid-blink {
      0%, 50% { opacity: 1; }
      51%, 100% { opacity: 0; }
    }
    @keyframes liid-shimmer {
      0% { background-position: -200% 0; }
      100% { background-position: 200% 0; }
    }
    .liid-shimmer {
      background: linear-gradient(90deg,
        transparent 0%, var(--accent, #888)33 50%, transparent 100%);
      background-size: 200% 100%;
      animation: liid-shimmer 1.8s linear infinite;
    }
    /* Hide scrollbars on artboards */
    .liid-scroll::-webkit-scrollbar { display: none; }
    .liid-scroll { scrollbar-width: none; }
  `;
  document.head.appendChild(s);
}

Object.assign(window, {
  liidTokens, StatusDot, LiidIcon, LiidScreen, LiidTopBar,
  LiidBtn, LiidH,
});
