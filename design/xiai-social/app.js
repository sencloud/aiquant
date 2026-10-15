/* 喜爱 · 新社交 — 原型交互
   原型里的圈、事、人、回声都是演示数据，按真实量级写的，但没有一条来自真实账户。
   「阿澈」「林渡」是虚构的真人示例，「小满」「老周」是虚构的 AI 居民示例。 */

const $  = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
let current = 'splash';
let history = [];

function toast(msg){
  const t = $('#toast');
  t.textContent = msg;
  t.classList.add('on');
  clearTimeout(t._t);
  t._t = setTimeout(() => t.classList.remove('on'), 2400);
}

/* ── 开屏星点（固定种子，截图稳定） ─────────────────────────── */
function renderStars(){
  let seed = 20261016;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  let out = '';
  for (let i = 0; i < 40; i++){
    const band = rnd();
    const y = band < .5 ? rnd() * 34 : 62 + rnd() * 36;
    let x = rnd() * 100;
    if (band >= .5 && band < .58) x = rnd() < .5 ? rnd() * 16 : 84 + rnd() * 16;
    const size = rnd() < .18 ? 3 : 2;
    out += `<i style="left:${x.toFixed(1)}%;top:${y.toFixed(1)}%;width:${size}px;height:${size}px;`
         + `--d:${(rnd() * 3.4).toFixed(2)}s"></i>`;
  }
  $('#stars').innerHTML = out;
}

/* ── 圈里的水位线：14 天，每天登记几条 ─────────────────────── */
function renderRail(){
  const days = [0,1,2,0,3,1,0,0,2,4,1,0,2,3];
  const max = Math.max(...days);
  const box = $('#rail');
  box.innerHTML = days.map((n, i) => {
    const h = 5 + Math.round((n / max) * 29);
    const cls = n === 0 ? '' : n >= 3 ? 'on' : 'half';
    return `<div class="cell ${cls}" style="height:${n === 0 ? 4 : h}px;--d:${i * 40}ms"></div>`;
  }).join('');
}

/* ── 导航 ───────────────────────────────────────────────────── */
const TAB_SCREENS = ['today','circle','mail','me'];

function go(id, remember = true){
  if (remember && current !== id) history.push(current);
  current = id;
  $$('.screen').forEach(s => {
    const on = s.id === 's-' + id;
    s.hidden = !on;
    s.classList.toggle('enter', on && id !== 'splash');
  });
  $('#device').classList.toggle('night', id === 'splash');
  $('#tabsbar').hidden = !TAB_SCREENS.includes(id);
  $$('#tabs a').forEach(a => a.classList.toggle('on', a.dataset.go === id));
}

function back(){
  const prev = history.pop() || 'today';
  go(prev, false);
}

function sheet(name, on){
  $$('.sheet').forEach(s => s.classList.toggle('on', on && s.id === 'sh-' + name));
  $('#scrim').classList.toggle('on', !!on);
}

/* ── 交互 ───────────────────────────────────────────────────── */
document.addEventListener('click', e => {
  const sw = e.target.closest('.sw');
  if (sw){
    sw.classList.toggle('on');
    toast(sw.classList.contains('on')
      ? '今晚没有人能给你新的话。已经在路上的，明天到。'
      : '今晚照常。');
    return;
  }

  // 由头：单选（「没有由头」那张点了只解释，不选中）
  const po = e.target.closest('.posture');
  if (po){
    if (po.classList.contains('off')){
      toast('没有由头的话，先投一条回声给以后。');
      return;
    }
    $$('.posture').forEach(p => {
      p.classList.toggle('on', p === po);
      const tick = p.querySelector('svg[id^="pk"]');
      if (tick) tick.style.visibility = p === po ? 'visible' : 'hidden';
    });
    return;
  }

  // 什么时候递给他：单选
  const chip = e.target.closest('#when-chips .chip');
  if (chip){
    $$('#when-chips .chip').forEach(c => c.classList.toggle('on', c === chip));
    return;
  }
  const otherChip = e.target.closest('.chip');
  if (otherChip){ otherChip.classList.toggle('on'); return; }

  // 见面礼：单选
  const g = e.target.closest('.pick .g');
  if (g){ $$('.pick .g').forEach(x => x.classList.toggle('on', x === g)); return; }

  const act = e.target.closest('[data-act]');
  if (act){
    e.stopPropagation();
    const [verb, arg] = act.dataset.act.split(':');
    if (verb === 'revoke')  toast('已收回。他还不知道有这条。');
    if (verb === 'accept')  toast('收下了。你们现在有一件事是共同的。');
    if (verb === 'decline') toast('谢过了。他只会知道你不收，不会知道为什么。');
    if (verb === 'sheet')   sheet(arg, true);
    if (verb === 'go')      go(arg);
    return;
  }

  const sh = e.target.closest('[data-sheet]');
  if (sh){ sheet(sh.dataset.sheet, true); return; }
  if (e.target.closest('[data-back]')){ back(); return; }
  const goto = e.target.closest('[data-go]');
  if (goto){ go(goto.dataset.go); return; }
  if (e.target.closest('#scrim')) sheet(null, false);

  const rbtn = e.target.closest('.rbtn');
  if (rbtn){
    const [verb, arg] = rbtn.dataset.act.split(':');
    $$('.rbtn').forEach(b => { if (b.dataset.act.split(':')[0] === verb) b.classList.remove('on'); });
    rbtn.classList.add('on');
    if (verb === 'go')    go(arg);
    if (verb === 'sheet') sheet(arg, true);
  }
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') sheet(null, false);
});

$('#speak-send').addEventListener('click', () => {
  const when = $('#when-chips .chip.on');
  toast(when && when.dataset.when !== '0'
    ? `投出去了。${when.textContent} 递给他 —— 在那之前你都能收回。`
    : '投出去了。谁在看那件事，谁就能看见你。');
  go('today');
});
$('#gift-send').addEventListener('click', () => {
  toast('送出去了。他收下之前，你都能收回。');
  go('mail');
});

/* 键盘可达 */
function makeFocusable(root = document){
  $$('[data-go],[data-sheet],[data-back],[data-act],.thinbtn,.chip,.sw,.posture,.pick .g', root)
    .forEach(el => { if (!el.hasAttribute('tabindex')) el.tabIndex = 0; });
}

/* ── 初始化 ─────────────────────────────────────────────────── */
renderStars();
renderRail();
makeFocusable();
new MutationObserver(() => makeFocusable()).observe(document.body, { childList: true, subtree: true });
go('splash', false);
