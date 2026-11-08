const { chromium } = require('C:/Users/Lenovo/bday-kardes/node_modules/playwright');
const path = require('path');

const URL = process.argv[2] || 'http://127.0.0.1:8790/index.html';

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 810 } });

  const errors = [];
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()); });

  const resp = await page.goto(URL, { waitUntil: 'networkidle' });
  console.log('HTTP', resp.status(), '|', URL);
  await page.waitForTimeout(1500);

  const results = [];
  const check = (n, c, e = '') => results.push(`${c ? 'PASS' : 'FAIL'}  ${n}${e ? ' -> ' + e : ''}`);

  // --- 1) Prologue ---
  let d = await page.evaluate(() => window.__dbg());
  check('Prologue ekraninda', d.state === 'pro', d.state);
  const sms = await page.evaluate(() => document.getElementById('sms').textContent);
  check('SMS Derin adi iceriyor', /Derin/.test(sms), sms.slice(0, 60));
  const cfg = await page.evaluate(() => document.getElementById('tMsg').textContent);
  check('Derin adi HUD/mesajda', /DERİN/.test(cfg) || /Derin/.test(cfg), cfg.slice(0, 50));

  // --- 2) Oyuna basla ---
  await page.click('#pStart');
  await page.waitForTimeout(900);
  d = await page.evaluate(() => window.__dbg());
  check('Oyun basladi (play)', d.state === 'play', d.state);
  check('Bölüm 1 ofis', d.stage === 0, 'stage=' + d.stage);
  check('Süre 20 dakika', Math.abs(d.timeLeft - 1200) < 5, 'timeLeft=' + d.timeLeft);
  check('3 can var', d.lives === 3, 'lives=' + d.lives);
  check('Hediye tasiniyor', d.hasGift === true, String(d.hasGift));

  // --- 3) Kosma ---
  const x0 = d.x;
  await page.keyboard.down('KeyD');
  await page.waitForTimeout(1500);
  const mid = await page.evaluate(() => window.__dbg());
  await page.keyboard.up('KeyD');
  d = mid;
  // NOT: headless test ortaminda FPS dusuk (yazilim rasterizasyonu) -> simule
  // edilen sure gercek zamandan az olur. Bu yuzden HIZ ve GROUNDED kontrol
  // edilir; konum ilerlemesi oyuncunun PC'sinde dogrulanir.
  check('Kosma hizi dogru', d.speed > 8, `hiz=${d.speed}`);
  check('Oyuncu zeminde', d.grounded === true, 'grounded=' + d.grounded);
  check('Konum ilerledi', d.x > x0 + 1, `x ${x0} -> ${d.x}`);
  // Ardisik 2 saniye boyunca tus basili kalinca konum surekli artmali.
  const simT = await page.evaluate(async () => {
    window.__key('KeyD', true);
    const x0 = window.__dbg().x;
    await new Promise(r => setTimeout(r, 2000));
    const d = window.__dbg().x - x0;
    window.__key('KeyD', false);
    return d;
  });
  check('2snde belirgin ilerleme', simT > 8, simT.toFixed(2) + ' birim');

  // --- 4) DENGE MEKANIGI: fare hareketi dengeyi degistirmeli ---
  const b0 = d.balance;
  await page.mouse.move(1200, 405);
  await page.waitForTimeout(700);
  d = await page.evaluate(() => window.__dbg());
  check('Fare hareketi dengeyi degistiriyor', Math.abs(d.balance - b0) > 0.08, `balance ${b0} -> ${d.balance}`);

  // --- 5) Denge kazasi (pasta dusmesi) ---
  await page.evaluate(() => window.__crash());
  await page.waitForTimeout(900);
  d = await page.evaluate(() => window.__dbg());
  check('Pasta kazasi -> over ekrani', d.state === 'over', d.state);
  const verdict = await page.evaluate(() => document.getElementById('verdict').textContent);
  check('Kazanma yazisi PASTA KAZASI', /PASTA KAZASI/.test(verdict), verdict);

  // --- 6) Yeniden basla ---
  await page.click('#oBtn');
  await page.waitForTimeout(700);
  d = await page.evaluate(() => window.__dbg());
  check('Tekrar deneyince oyun resetlendi',
    d.state === 'play' && d.lives === 3 && d.slip < 0.05 && Math.abs(d.x - 6) < 1,
    `${d.state} lives=${d.lives} slip=${d.slip} x=${d.x}`);

  // --- 7) Bölüm gecisleri ---
  for (let i = 1; i < 5; i++) {
    await page.evaluate(s => window.__stage(s), i);
    await page.waitForTimeout(400);
    d = await page.evaluate(() => window.__dbg());
    check(`Bölüm ${i + 1} kuruldu`, d.stage === i, `stage=${d.stage} solids=${d.solids}`);
  }

  // --- 8) Final: kapıya ulasma ---
  await page.evaluate(() => window.__stage(4));
  await page.waitForTimeout(400);
  d = await page.evaluate(() => window.__dbg());
  check('Finalde kapı (goal) var', d.goalX > 0, 'goalX=' + d.goalX);
  // oyuncuyu final bolumunde guvenli sekilde tasi (dusmemek icin y=0.02)
  await page.evaluate(g => window.__teleportSafe(g, 0.02, 0), d.goalX);
  await page.waitForTimeout(1200);
  d = await page.evaluate(() => window.__dbg());
  check('Kapıya ulasma -> win ekrani', d.state === 'win', `state=${d.state} x=${d.x} slip=${d.slip}`);

  // --- 9) Aile tablosu ---
  const fam = await page.evaluate(() => document.querySelectorAll('#famRow .fam').length);
  check('Aile tablosunda 4 kişi', fam === 4, 'count=' + fam);
  const names = await page.evaluate(() => [...document.querySelectorAll('#famRow .nm')].map(n => n.textContent).join(','));
  check('Aile tablosunda Derin var', /DERİN/i.test(names), names);

  // --- 10) Fotoğraflar yuklendi mi ---
  const imgs = await page.evaluate(() => {
    const list = [...document.querySelectorAll('#famRow img')];
    return list.map(i => ({ src: i.src.split('/').pop(), ok: i.naturalWidth > 0 }));
  });
  check('Finalde 4 fotoğraf yuklendi', imgs.length === 4 && imgs.every(i => i.ok), JSON.stringify(imgs));

  // --- 11) Performans ---
  // Not: headless test ortaminda FPS olcumu guvenilir degil (yazilim rasterizasyonu).
  // Bu yuzden gercek FPS'i oyuncunun PC'sinde oynarken olcecegiz.
  // Burada sadece render dongusunun canli oldugunu dogruluyoruz.
  const fpsAlive = await page.evaluate(async () => {
    let n = 0;
    await new Promise(res => {
      const tick = () => { n++; if (n < 5) requestAnimationFrame(tick); else res(); };
      requestAnimationFrame(tick);
    });
    return n;
  });
  check('Render dongusu calisiyor', fpsAlive >= 5, fpsAlive + ' frame');
  const drawCalls = await page.evaluate(() => {
    const c = document.querySelector('canvas');
    return c ? c.width + 'x' + c.height : 'yok';
  });
  check('Canvas olculu', /\d+x\d+/.test(drawCalls), drawCalls);

  // --- 12) Screenshot ---
  await page.evaluate(() => window.__reset());
  await page.waitForTimeout(1200);
  await page.screenshot({ path: path.join(__dirname, 'shot-3d.png') });

  console.log('\n=== TEST SONUCU ===');
  results.forEach(r => console.log(r));
  console.log('\nJS HATALARI:', errors.length ? errors.join('\n') : 'YOK');
  const failed = results.filter(r => r.startsWith('FAIL')).length;
  console.log(`\n${results.length - failed}/${results.length} test gecti`);
  await browser.close();
  process.exit(failed || errors.length ? 1 : 0);
})();
