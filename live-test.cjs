const { chromium } = require('C:/Users/Lenovo/bday-kardes/node_modules/playwright');

const URL = process.argv[2] || 'https://emiranka0813.github.io/son-dilim/';

(async () => {
  const b = await chromium.launch({ channel: 'chrome' });
  const p = await b.newPage({ viewport: { width: 1440, height: 810 } });
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR: ' + e.message));
  p.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE: ' + m.text()); });

  const resp = await p.goto(URL, { waitUntil: 'commit', timeout: 15000 });
  console.log('HTTP', resp.status(), '|', URL);
  await p.waitForTimeout(3000);

  const r = [];
  const ck = (n, c, e = '') => r.push(`${c ? 'PASS' : 'FAIL'}  ${n}${e ? ' -> ' + e : ''}`);

  let d = await p.evaluate(() => window.__dbg ? window.__dbg() : null);
  ck('Oyun yuklendi (modul)', !!d, d ? d.state : 'dbg yok');
  ck('Prologue ekraninda', d && d.state === 'pro', d && d.state);

  const title = await p.title();
  ck('Baslikta Derin var', /Derin/.test(title), title);

  const sms = await p.evaluate(() => document.getElementById('sms').textContent);
  ck('SMS Derin adi iceriyor', /Derin/.test(sms), sms.slice(0, 55));

  // oyuna basla
  await p.click('#pStart');
  await p.waitForTimeout(1200);
  d = await p.evaluate(() => window.__dbg());
  ck('Oyun basladi', d.state === 'play', d.state);
  ck('20 dakika suresi', Math.abs(d.timeLeft - 1200) < 5, String(d.timeLeft));
  ck('3 can', d.lives === 3, String(d.lives));

  // kosma
  const x0 = d.x;
  await p.evaluate(() => window.__key('KeyD', true));
  await p.waitForTimeout(2000);
  await p.evaluate(() => window.__key('KeyD', false));
  d = await p.evaluate(() => window.__dbg());
  ck('Kosma ilerletiyor', d.x - x0 > 8, `${x0} -> ${d.x}`);
  ck('Hiz dogru', d.speed > 8, String(d.speed));

  // denge
  const b0 = d.balance;
  await p.evaluate(() => window.__mouse(1));
  await p.waitForTimeout(700);
  d = await p.evaluate(() => window.__dbg());
  ck('Fare dengeyi degistiriyor', Math.abs(d.balance - b0) > 0.08, `${b0} -> ${d.balance}`);

  // kaza
  await p.evaluate(() => window.__crash());
  await p.waitForTimeout(900);
  d = await p.evaluate(() => window.__dbg());
  ck('Pasta kazasi -> over', d.state === 'over', d.state);

  // bolumler
  for (let i = 1; i < 5; i++) {
    await p.evaluate(s => window.__stage(s), i);
    await p.waitForTimeout(350);
    d = await p.evaluate(() => window.__dbg());
    ck(`Bolum ${i + 1} kuruldu`, d.stage === i, `stage=${d.stage}`);
  }

  // final
  d = await p.evaluate(() => window.__dbg());
  ck('Finalde kapi var', d.goalX > 0, String(d.goalX));
  await p.evaluate(x => window.__teleportSafe(x, 0.02, 0), d.goalX);
  await p.waitForTimeout(1400);
  d = await p.evaluate(() => window.__dbg());
  ck('Kapıya ulasma -> win', d.state === 'win', d.state);

  const fam = await p.evaluate(() => [...document.querySelectorAll('#famRow .nm')].map(n => n.textContent));
  ck('Aile tablosu 4 kisi', fam.length === 4, fam.join(','));
  ck('Aile tablosunda Derin', fam.some(n => /DERİN/i.test(n)), fam.join(','));

  const imgs = await p.evaluate(() => [...document.querySelectorAll('#famRow img')].map(i => i.naturalWidth > 0));
  ck('4 fotograf yuklendi', imgs.length === 4 && imgs.every(Boolean), JSON.stringify(imgs));

  console.log('\n=== CANLI TEST ===');
  r.forEach(x => console.log(x));
  console.log('\nJS HATALARI:', errs.length ? errs.join('\n') : 'YOK');
  const f = r.filter(x => x.startsWith('FAIL')).length;
  console.log(`\n${r.length - f}/${r.length} test gecti`);
  await b.close();
  process.exit(f || errs.length ? 1 : 0);
})().catch(e => console.log('HATA:', e.message.split('\n')[0]));
