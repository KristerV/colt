// View 0 — New campaign (name)
// View 1 — ICP + target job title
// View 2 — Market picker

function View0NewCampaign({ accent, density }) {
  return (
    <LiidScreen accent={accent} density={density} step={0}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', maxWidth: 760 }}>
        <LiidH kicker="01 / Campaign" title={<>What are we calling this <em style={{ fontStyle: 'italic', color: accent }}>hunt</em>?</>}
          sub="Every search is saved as a campaign. Name it after the persona, market, or quarter — anything you'll recognise in three weeks." />
        <div style={{ marginTop: 56, position: 'relative' }}>
          <input readOnly value="Nordic CTOs Q2"
            style={{
              width: '100%', maxWidth: 560,
              fontFamily: liidTokens.serif, fontSize: 44, fontWeight: 400,
              letterSpacing: -0.8, color: liidTokens.ink,
              padding: '12px 0 14px', border: 'none', outline: 'none',
              borderBottom: `1px solid ${liidTokens.ink}`, background: 'transparent',
            }} />
          <div style={{
            position: 'absolute', right: 'calc(100% - 560px + 8px)', top: 22,
            fontFamily: liidTokens.mono, fontSize: 11, color: accent,
            animation: 'liid-blink 1s steps(1) infinite',
            display: 'none',
          }}>|</div>
          <div style={{
            marginTop: 12, fontFamily: liidTokens.mono, fontSize: 11,
            color: liidTokens.ink55, letterSpacing: 0.04,
          }}>
            <span style={{ color: accent }}>●</span> draft · auto-saved 0s ago
          </div>
        </div>

        <div style={{
          marginTop: 64, display: 'flex', alignItems: 'center', gap: 16,
        }}>
          <LiidBtn primary mono>
            Continue
            <LiidIcon name="arrow" size={13} color={liidTokens.paper} />
          </LiidBtn>
          <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink40 }}>
            ⏎ to continue
          </span>
        </div>

        {/* Recent campaigns sidebar — small */}
        <div style={{
          position: 'absolute', right: 56, top: 120, width: 240,
          borderLeft: `1px solid ${liidTokens.rule}`,
          paddingLeft: 24,
        }}>
          <div style={{
            fontFamily: liidTokens.mono, fontSize: 10, letterSpacing: 0.12,
            textTransform: 'uppercase', color: liidTokens.ink40, marginBottom: 16,
          }}>Recent</div>
          {[
            ['Helsinki SaaS heads',   '847 / 1,000', '2d ago'],
            ['EE manufacturers >50',  '412 / 600',   '6d ago'],
            ['FI fintech CFOs',       '203 / 250',   '12d ago'],
            ['Tartu agencies',        '88 / 100',    '3w ago'],
          ].map(([n, ratio, when]) => (
            <div key={n} style={{
              padding: '10px 0', borderBottom: `1px solid ${liidTokens.rule}`,
            }}>
              <div style={{ fontSize: 13, color: liidTokens.ink, marginBottom: 3 }}>{n}</div>
              <div style={{ display: 'flex', justifyContent: 'space-between',
                fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40, letterSpacing: 0.04 }}>
                <span>{ratio}</span><span>{when}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </LiidScreen>
  );
}

function View1ICP({ accent, density }) {
  const icpText = "B2B software companies headquartered in Estonia or Finland with 50–500 employees, ideally engineering-led, that have shipped a public product in the last 18 months. We're selling developer tooling — observability, build infra, internal platform glue. Avoid pure outsourcing shops, marketing agencies, or anyone whose core business is custom client work.";
  const titles = ['CTO', 'VP Engineering', 'Head of Engineering', 'Director of Engineering', 'Engineering Manager', 'Head of Platform'];
  return (
    <LiidScreen accent={accent} density={density} step={1}>
      <div style={{ display: 'flex', gap: 64, flex: 1, minHeight: 0 }}>
        <div style={{ flex: '0 0 320px' }}>
          <LiidH kicker="02 / ICP" title={<>Describe the <em style={{ fontStyle: 'italic', color: accent }}>customer</em> you want.</>}
            sub="Plain English. The model reads this against every company's website to decide if it's a fit. Be specific about what disqualifies." />
        </div>

        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 36, maxWidth: 640 }}>
          {/* ICP textarea */}
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
              <label style={{ fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.08, textTransform: 'uppercase', color: liidTokens.ink70 }}>
                Ideal customer profile
              </label>
              <span style={{ fontFamily: liidTokens.mono, fontSize: 10, color: liidTokens.ink40 }}>
                {icpText.length} / 2000
              </span>
            </div>
            <div style={{
              padding: '20px 22px',
              border: `1px solid ${liidTokens.ink20}`,
              background: liidTokens.paperAlt,
              fontSize: 15, lineHeight: 1.55, color: liidTokens.ink,
              minHeight: 200,
              borderRadius: 2,
              position: 'relative',
            }}>
              {icpText}
              <span style={{
                display: 'inline-block', width: 7, height: 16, background: accent,
                marginLeft: 2, transform: 'translateY(3px)',
                animation: 'liid-blink 1s steps(1) infinite',
              }} />
            </div>
          </div>

          {/* Job title chips */}
          <div>
            <div style={{ marginBottom: 12 }}>
              <label style={{ fontFamily: liidTokens.mono, fontSize: 11, letterSpacing: 0.08, textTransform: 'uppercase', color: liidTokens.ink70 }}>
                Target job titles
              </label>
              <div style={{ fontSize: 12, color: liidTokens.ink40, marginTop: 4 }}>
                The contact we'll try to extract per company.
              </div>
            </div>
            <div style={{
              padding: '12px 14px', minHeight: 50,
              border: `1px solid ${liidTokens.ink20}`,
              background: liidTokens.paperAlt,
              borderRadius: 2,
              display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center',
            }}>
              {titles.map((t, i) => (
                <span key={t} style={{
                  display: 'inline-flex', alignItems: 'center', gap: 6,
                  padding: '5px 8px 5px 10px',
                  background: i === 0 ? accent : liidTokens.paper,
                  color: i === 0 ? liidTokens.paper : liidTokens.ink,
                  border: `1px solid ${i === 0 ? accent : liidTokens.ink20}`,
                  fontSize: 12, borderRadius: 2,
                  fontFamily: liidTokens.sans,
                }}>
                  {t}
                  <LiidIcon name="x" size={10} color={i === 0 ? liidTokens.paper : liidTokens.ink55} />
                </span>
              ))}
              <span style={{
                fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink40,
                padding: '4px 6px',
              }}>
                + add
                <span style={{
                  display: 'inline-block', width: 6, height: 12, background: accent,
                  marginLeft: 4, transform: 'translateY(2px)',
                  animation: 'liid-blink 1s steps(1) infinite',
                }} />
              </span>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginTop: 8 }}>
            <LiidBtn small style={{ padding: '10px 16px' }}>
              <LiidIcon name="chevL" size={11} />
              Back
            </LiidBtn>
            <LiidBtn primary mono>
              Continue → market
              <LiidIcon name="arrow" size={13} color={liidTokens.paper} />
            </LiidBtn>
          </div>
        </div>
      </div>
    </LiidScreen>
  );
}

function View2Market({ accent, density }) {
  const markets = [
    { code: 'EE', name: 'Estonia',  count: '142,180', api: 'rik.ee',          tax: 'KMKR',  flag: ['#0072CE','#000000','#FFFFFF'] },
    { code: 'FI', name: 'Finland',  count: '687,300', api: 'ytj.fi',          tax: 'Y-tunnus', flag: ['#FFFFFF','#003580','#FFFFFF'] },
    { code: 'LV', name: 'Latvia',   count: '198,420', api: 'ur.gov.lv',       tax: 'PVN',   disabled: true, flag: ['#9E1B32','#FFFFFF','#9E1B32'] },
    { code: 'LT', name: 'Lithuania',count: '156,090', api: 'registrucentras.lt', tax: 'PVM',disabled: true, flag: ['#FDB913','#006A44','#C1272D'] },
    { code: 'SE', name: 'Sweden',   count: '1.2M',    api: 'bolagsverket.se', tax: 'Org.nr',disabled: true, flag: ['#006AA7','#FECC02','#006AA7'] },
    { code: 'NO', name: 'Norway',   count: '624,500', api: 'brreg.no',        tax: 'Org.nr',disabled: true, flag: ['#BA0C2F','#FFFFFF','#00205B'] },
  ];
  return (
    <LiidScreen accent={accent} density={density} step={2}>
      <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0, gap: 40 }}>
        <LiidH kicker="03 / Market"
          title={<>Which <em style={{ fontStyle: 'italic', color: accent }}>register</em> do we pull from?</>}
          sub="One market per campaign. Liid hits the government registry and walks the resulting domain list. Greyed-out registries are scheduled for next quarter." />

        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14,
        }}>
          {markets.map((m, i) => {
            const selected = m.code === 'EE';
            const dis = m.disabled;
            return (
              <label key={m.code} style={{
                display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
                padding: '24px 24px 20px',
                border: `1px solid ${selected ? liidTokens.ink : liidTokens.ink20}`,
                background: selected ? liidTokens.paperAlt : liidTokens.paper,
                opacity: dis ? 0.45 : 1,
                cursor: dis ? 'not-allowed' : 'pointer',
                position: 'relative',
                minHeight: 200,
                borderRadius: 2,
              }}>
                <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    {/* radio */}
                    <span style={{
                      width: 14, height: 14, borderRadius: 999,
                      border: `1px solid ${selected ? accent : liidTokens.ink40}`,
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      flexShrink: 0,
                    }}>
                      {selected && <span style={{ width: 7, height: 7, borderRadius: 999, background: accent }} />}
                    </span>
                    <div style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.12 }}>
                      {m.code}
                    </div>
                  </div>
                  {dis && (
                    <span style={{
                      fontFamily: liidTokens.mono, fontSize: 9, letterSpacing: 0.12,
                      textTransform: 'uppercase', color: liidTokens.ink40,
                      border: `1px solid ${liidTokens.ink20}`, padding: '2px 6px', borderRadius: 2,
                    }}>Q3</span>
                  )}
                </div>

                <div style={{ marginTop: 20 }}>
                  <div style={{
                    fontFamily: liidTokens.serif, fontSize: 38, fontWeight: 400,
                    letterSpacing: -0.6, lineHeight: 1, color: liidTokens.ink,
                  }}>{m.name}</div>
                  <div style={{
                    marginTop: 14, display: 'flex', justifyContent: 'space-between',
                    fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink55, letterSpacing: 0.04,
                  }}>
                    <span>{m.api}</span>
                    <span style={{ color: liidTokens.ink70 }}>{m.count}</span>
                  </div>
                </div>
              </label>
            );
          })}
        </div>

        <div style={{ flex: 1 }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <LiidBtn small><LiidIcon name="chevL" size={11} />Back</LiidBtn>
          <LiidBtn primary mono>
            Continue → filters
            <LiidIcon name="arrow" size={13} color={liidTokens.paper} />
          </LiidBtn>
          <span style={{ fontFamily: liidTokens.mono, fontSize: 11, color: liidTokens.ink40, marginLeft: 'auto' }}>
            142,180 active companies in rik.ee · last sync 02:00 EET
          </span>
        </div>
      </div>
    </LiidScreen>
  );
}

Object.assign(window, { View0NewCampaign, View1ICP, View2Market });
