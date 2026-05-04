// Mock company data, used across views.

const INDUSTRIES_EE = [
  'SaaS', 'Manufacturing', 'Logistics', 'FinTech', 'Construction',
  'E-commerce', 'Wood & Forestry', 'Food & Bev', 'Mar­itime', 'Energy',
  'AgTech', 'Real Estate', 'Healthcare', 'Education', 'Cleantech',
];

const COMPANY_SEEDS = [
  { name: 'Bolt Technology OÜ',     industry: 'Mobility',         size: 4200, growth: '10x',     city: 'Tallinn',  reg: '12417834' },
  { name: 'Pipedrive AS',           industry: 'SaaS',             size: 920,  growth: '2x',      city: 'Tallinn',  reg: '11958539' },
  { name: 'Veriff OÜ',              industry: 'Identity / SaaS',  size: 540,  growth: 'slow',    city: 'Tallinn',  reg: '12932944' },
  { name: 'Skeleton Technologies',  industry: 'Energy storage',   size: 310,  growth: '2x',      city: 'Tartu',    reg: '11525282' },
  { name: 'Starship OÜ',            industry: 'Robotics',         size: 280,  growth: 'slow',    city: 'Tallinn',  reg: '12631220' },
  { name: 'Glia Technologies OÜ',   industry: 'CX / SaaS',        size: 460,  growth: 'slow',    city: 'Tallinn',  reg: '12397014' },
  { name: 'Wise Estonia OÜ',        industry: 'FinTech',          size: 760,  growth: 'slow',    city: 'Tallinn',  reg: '14123456' },
  { name: 'Funderbeam OÜ',          industry: 'FinTech',          size: 48,   growth: 'stagnant',city: 'Tallinn',  reg: '12421760' },
  { name: 'Nortal AS',              industry: 'IT Services',      size: 1900, growth: 'slow',    city: 'Tallinn',  reg: '10391131' },
  { name: 'Helmes AS',              industry: 'IT Services',      size: 1100, growth: 'stagnant',city: 'Tallinn',  reg: '10325834' },
  { name: 'Cleveron AS',            industry: 'Robotics',         size: 320,  growth: 'slow',    city: 'Viljandi', reg: '11470141' },
  { name: 'Milrem Robotics OÜ',     industry: 'Defense',          size: 220,  growth: '2x',      city: 'Tallinn',  reg: '12734467' },
  { name: 'Tuum OÜ',                industry: 'FinTech',          size: 110,  growth: '2x',      city: 'Tallinn',  reg: '12972820' },
  { name: 'Salv Technologies',      industry: 'AML / FinTech',    size: 64,   growth: 'slow',    city: 'Tallinn',  reg: '14523221' },
  { name: 'Klaus IO OÜ',            industry: 'SaaS',             size: 88,   growth: 'slow',    city: 'Tallinn',  reg: '14108984' },
  { name: 'Cachet OÜ',              industry: 'Insurance / SaaS', size: 38,   growth: '2x',      city: 'Tallinn',  reg: '14868100' },
  { name: 'Modular OÜ',             industry: 'Construction',     size: 220,  growth: 'stagnant',city: 'Pärnu',    reg: '11290442' },
  { name: 'Combimill Reopalu',      industry: 'Wood & Forestry',  size: 145,  growth: 'slow',    city: 'Tartu',    reg: '10828833' },
  { name: 'Estanc AS',              industry: 'Manufacturing',    size: 380,  growth: 'slow',    city: 'Maardu',   reg: '10168930' },
  { name: 'Krimelte OÜ',            industry: 'Manufacturing',    size: 720,  growth: 'slow',    city: 'Tallinn',  reg: '10058212' },
  { name: 'Tallink Grupp AS',       industry: 'Maritime',         size: 7100, growth: 'stagnant',city: 'Tallinn',  reg: '10238429' },
  { name: 'Ericsson Eesti AS',      industry: 'Telecom',          size: 1500, growth: 'slow',    city: 'Tallinn',  reg: '10184017' },
  { name: 'Magnetic MRO AS',        industry: 'Aviation MRO',     size: 940,  growth: '2x',      city: 'Tallinn',  reg: '10577780' },
  { name: 'Datel AS',               industry: 'IT Services',      size: 290,  growth: 'stagnant',city: 'Tallinn',  reg: '10094386' },
  { name: 'Mooncascade OÜ',         industry: 'IT Services',      size: 110,  growth: 'slow',    city: 'Tartu',    reg: '11888098' },
  { name: 'Webmedia (Nortal)',      industry: 'IT Services',      size: 540,  growth: 'slow',    city: 'Tallinn',  reg: '10391131' },
  { name: 'Fortumo OÜ',             industry: 'Payments',         size: 76,   growth: 'stagnant',city: 'Tallinn',  reg: '11378805' },
  { name: 'Single.Earth OÜ',        industry: 'Cleantech',        size: 42,   growth: '2x',      city: 'Tallinn',  reg: '14869773' },
  { name: 'Comodule OÜ',            industry: 'IoT',              size: 88,   growth: 'slow',    city: 'Tallinn',  reg: '12508293' },
  { name: 'Yaga OÜ',                industry: 'E-commerce',       size: 26,   growth: 'slow',    city: 'Tallinn',  reg: '12687754' },
];

// Per-step status. order: web → pages → email → md → summary → icp → contacts
const STAGE_KEYS = ['web', 'scrape', 'parse', 'icp', 'contact', 'verify'];
const STAGE_LABEL = {
  web:     'Website',
  scrape:  'Pages',
  parse:   'Parse',
  icp:     'ICP fit',
  contact: 'Contacts',
  verify:  'Verified',
};

// Sample row states across the spectrum so the list looks alive.
const ROW_STATES = [
  // queued
  { state: 'queued',    progress: { web: 'idle', scrape: 'idle', parse: 'idle', icp: 'idle', contact: 'idle', verify: 'idle' } },
  // working — variants
  { state: 'working',   progress: { web: 'done', scrape: 'work', parse: 'idle', icp: 'idle', contact: 'idle', verify: 'idle' } },
  { state: 'working',   progress: { web: 'done', scrape: 'done', parse: 'work', icp: 'idle', contact: 'idle', verify: 'idle' } },
  { state: 'working',   progress: { web: 'done', scrape: 'done', parse: 'done', icp: 'work', contact: 'idle', verify: 'idle' } },
  { state: 'working',   progress: { web: 'done', scrape: 'done', parse: 'done', icp: 'done', contact: 'work', verify: 'idle' } },
  { state: 'working',   progress: { web: 'done', scrape: 'done', parse: 'done', icp: 'done', contact: 'done', verify: 'work' } },
  // success
  { state: 'done',      progress: { web: 'done', scrape: 'done', parse: 'done', icp: 'done', contact: 'done', verify: 'done' } },
  // ICP rejected
  { state: 'skip-icp',  progress: { web: 'done', scrape: 'done', parse: 'done', icp: 'skip', contact: 'idle', verify: 'idle' } },
  // website not found, fallback search ongoing
  { state: 'fallback',  progress: { web: 'fall', scrape: 'idle', parse: 'idle', icp: 'idle', contact: 'idle', verify: 'idle' } },
  // contact hallucinated
  { state: 'no-contact',progress: { web: 'done', scrape: 'done', parse: 'done', icp: 'done', contact: 'done', verify: 'fail' } },
  // hard fail
  { state: 'failed',    progress: { web: 'done', scrape: 'fail', parse: 'idle', icp: 'idle', contact: 'idle', verify: 'idle' } },
];

// Compose 30 visible rows that loop through interesting states.
const VISIBLE_ROWS = COMPANY_SEEDS.slice(0, 28).map((c, i) => {
  const s = ROW_STATES[i % ROW_STATES.length];
  // attach plausible enrichment results
  const slug = c.name.split(/\s+/)[0].toLowerCase().replace(/[^a-z]/g, '');
  return {
    ...c,
    ...s,
    domain: s.progress.web === 'fall' ? null : `${slug}.${c.city === 'Tartu' ? 'ee' : 'com'}`,
    pagesFound: s.progress.scrape === 'done' ? (8 + (i % 14)) : (s.progress.scrape === 'work' ? (1 + (i % 5)) : 0),
    contacts: s.state === 'done' ? (1 + (i % 3)) : (s.state === 'no-contact' ? 0 : 0),
    title: ['CTO','Head of Engineering','VP Engineering','Director of Engineering','CTO','Engineering Manager'][i % 6],
    person: ['Mart Tamm','Liis Saar','Kristjan Mets','Anna Karu','Hendrik Lepp','Tõnis Vahtra','Kaisa Õun','Rasmus Kask','Mari Ilves','Jaan Sepp'][i % 10],
    email: s.state === 'done' ? `${['m.tamm','l.saar','k.mets','a.karu','h.lepp','t.vahtra','k.oun','r.kask','m.ilves','j.sepp'][i%10]}@${slug}.${c.city === 'Tartu' ? 'ee' : 'com'}` : null,
  };
});

// counts
const TOTAL_VISIBLE = VISIBLE_ROWS.length;
const TOTAL_IN_FUNNEL = 847;
const TOTAL_DONE = 312;

window.LIID_DATA = {
  COMPANY_SEEDS, VISIBLE_ROWS, INDUSTRIES_EE,
  STAGE_KEYS, STAGE_LABEL,
  TOTAL_VISIBLE, TOTAL_IN_FUNNEL, TOTAL_DONE,
};
