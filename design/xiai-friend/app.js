/* 喜爱 · 交友版 — 原型交互
   原型里的每个人、每条动态、每句对话都是演示数据，按真实量级写的，但没有一条来自真实账户。
   「阿澈」「林渡」是虚构的真人示例，「小满」是虚构的 AI 伙伴示例。 */

/* ── 六个喜爱（与 App 的 lib/topics 一致） ─────────────────── */
const CIRCLES = {
  fishing:{name:'喜爱钓鱼', note:'去哪儿、什么时辰、买什么竿', c:'fishing', mark:'钓'},
  coffee: {name:'喜爱咖啡', note:'豆单、参数、还在为哪支豆子较劲', c:'coffee', mark:'咖'},
  cat:    {name:'喜爱养猫', note:'猫粮、症状、猫为什么半夜叫', c:'cat', mark:'猫'},
  camping:{name:'喜爱露营', note:'营地、装备、能不能生火', c:'camping', mark:'营'},
  hanfu:  {name:'喜爱汉服', note:'形制、面料、第一次穿出门', c:'hanfu', mark:'汉'},
  money:  {name:'喜爱钱',   note:'看盘、看策略，也一起亏得起', c:'money', mark:'钱'},
};
const PICK_ORDER = ['fishing','coffee','cat','camping','hanfu','money'];

/* ── 今天的三位 ─────────────────────────────────────────────── */
const PEOPLE = {
  che:{
    ord:'01', name:'阿澈', kind:'real', c:'fishing', letter:'澈',
    meta:'31 · 杭州 · 钓鱼 6 年',
    quote:'周末基本在水边。钓不到也去。',
    interests:['fishing','camping'],
    why:'你们都在喜爱钓鱼；他这周在千岛湖记了两次渔获；你上个月也记过同一片水域。',
    recent:[['fishing','登记了一条渔获：翘嘴 42cm · 千岛湖支流','今天 09:12'],
            ['camping','问过一个问题：千岛湖哪个营地能生火、能洗澡','昨天']],
    ctx:'他上午 09:52 回过你。这里不显示在线状态。',
    log:[['day','昨天'],
         ['me','昨天看你记了千岛湖的翘嘴，那片水是走船道进去的吗？'],
         ['ta','对，北岸进去大概二十分钟。船道里水稳，早晚各一波。'],
         ['day','今天'],
         ['ta','看你记录里也写过那一片，是同一个湾吗？'],
         ['me','去过一次，没找到你说的那个湾，只钓到两条白条。'],
         ['ta','那大概是我下手重了。下次把点位发你，标在图上就行。']],
    ice:[['你那条 42cm 的翘嘴，是在船道里还是坝下钓的？','你们都在喜爱钓鱼，他刚登记了这条鱼'],
         ['我一直搞不定走水，你用多重的铅？','你上个月问过差不多一样的问题'],
         ['露营你一般都去哪？我想找个能生火的地方','你也标了喜爱露营']],
    reply:'那片水我熟。周末天气稳的话，我给你说个具体位置。',
    inbox:['下次把点位发你，标在图上就行。','09:52',0],
  },
  man:{
    ord:'02', name:'小满', kind:'ai', c:'coffee', letter:'满',
    meta:'27 · 上海 · 手冲第三年',
    quote:'手冲第三年，还在为同一支豆子较劲。',
    interests:['coffee','cat'],
    why:'你的豆单也在赏味期；她昨天问的问题和你上周问的一样：水温到底多少算高。',
    recent:[['coffee','记了豆单：哥伦比亚 惠兰 · 剩 3 天','今天 08:40'],
            ['cat','发了一张照片：猫蹲在称豆子的电子秤上','昨天']],
    idnote:'<b>她是 AI 伙伴</b>，由喜爱生成，不是真人。手冲三年、在上海、有一只猫 —— 这些是人设，'
         + '由喜爱的咖啡内容组维护。她记得你说过的话，回复有自己的节奏，不会秒回。'
         + '<span class="lk" data-act="sheet:who">怎么区分真人和 AI</span>',
    ctx:'AI 伙伴 · 由喜爱生成，不是真人。回复有自己的节奏。',
    log:[['day','今天'],
         ['me','惠兰你打算怎么救？我这边也快过赏味期了。'],
         ['ta','昨天试了 92℃、1:15，甜感回来一点，酸还是薄。今天想降到 90，再拉长一点。'],
         ['ta','你那个是手磨还是电磨？这个差别比我原先以为的大。']],
    ice:[['慧兰你是磨粗了还是水温高了？我这边也快过赏味期','她的豆单和你的在同一天进的赏味期'],
         ['你的猫站电子秤那张，是它自己上去的吗？','你也记过猫趴在奇奇怪怪的地方'],
         ['90℃ 那杯后来怎么样？我照你的参数试了一次','她刚改了参数，你们问的是同一件事']],
    reply:'试完了跟我说。同一支豆子两个人冲，差出来的那点挺有意思的。',
    inbox:['你那个是手磨还是电磨？这个差别比我原先以为的大。','08:58',2],
  },
  du:{
    ord:'03', name:'林渡', kind:'real', c:'cat', letter:'渡',
    meta:'29 · 南京 · 家里三只猫',
    quote:'家里三只猫，衣柜里两件宋制。',
    interests:['cat','hanfu'],
    why:'你们都在喜爱养猫；她的猫和你的有过同一类肠胃记录；她也标了喜爱汉服。',
    recent:[['cat','记了猫粮：剩 6 天，准备换回去年那款','今天 07:20'],
            ['hanfu','晒了一套：宋制褙子，春天在玄武湖拍的','上周']],
    ctx:'她还没回你。这里不显示在线状态。',
    log:[['day','今天'],
         ['me','你家猫换粮的时候肠胃闹过吗？我在两袋之间犹豫。']],
    ice:[['你家换粮那阵子，是怎么过渡的？','她的猫和你的有过同一类肠胃记录'],
         ['三只猫里哪只最难伺候？我在考虑第二只','她也记过三只猫的相处问题'],
         ['宋制褙子你一般配什么？第一次穿出门我有点怵','你们都在喜爱汉服']],
    reply:'过渡期我是七天换完的，前三天只换四分之一。慢一点，猫反而少遭罪。',
    inbox:['你家猫换粮的时候肠胃闹过吗？我在两袋之间犹豫。','昨天',0],
  },
};
const TODAY = ['che','man','du'];

/* ── 工具 ───────────────────────────────────────────────────── */
const $  = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
let current = 'splash';
let history = [];
let person  = 'che';
let iceIndex = 0;

const tagHTML = list => list.map(k => {
  const c = CIRCLES[k];
  return `<span class="tag" data-c="${c.c}">${c.name}</span>`;
}).join('');

const pillHTML = id => {
  const p = PEOPLE[id];
  return p.kind === 'ai'
    ? '<span class="pill ai">AI 伙伴</span>'
    : '<span class="pill real">已实名</span>';
};

function toast(msg){
  const t = $('#toast');
  t.textContent = msg;
  t.classList.add('on');
  clearTimeout(t._t);
  t._t = setTimeout(() => t.classList.remove('on'), 2200);
}

/* ── 开屏星点（固定种子，截图稳定） ─────────────────────────── */
function renderStars(){
  let seed = 20261015;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const box = $('#stars');
  let out = '';
  for (let i = 0; i < 40; i++){
    const band = rnd();
    let y = band < .5 ? rnd() * 34 : 62 + rnd() * 36;
    let x = rnd() * 100;
    if (band >= .5 && band < .58){ x = rnd() < .5 ? rnd() * 16 : 84 + rnd() * 16; }
    const size = rnd() < .18 ? 3 : 2;
    out += `<i style="left:${x.toFixed(1)}%;top:${y.toFixed(1)}%;width:${size}px;height:${size}px;`
         + `--d:${(rnd() * 3.4).toFixed(2)}s"></i>`;
  }
  box.innerHTML = out;
}

/* ── 先说喜爱什么 ───────────────────────────────────────────── */
let picked = new Set(['fishing','coffee']);

function renderPicker(){
  $('#pick-rows').innerHTML = PICK_ORDER.map(k => {
    const c = CIRCLES[k];
    const on = picked.has(k);
    return `<div class="line" data-pick="${k}" data-c="${c.c}">
      <span class="mark" data-c="${c.c}">${c.mark}</span>
      <div class="stack"><div class="lead">${c.name}</div><div class="sub">${c.note}</div></div>
      <span class="val" data-check="${k}" style="${on ? '' : 'visibility:hidden'}">
        <svg width="16" height="16" style="color:#7A4A16"><use href="#i-check"/></svg>
      </span>
    </div>`;
  }).join('');
}

/* ── 今天 ───────────────────────────────────────────────────── */
function cardHTML(id){
  const p = PEOPLE[id];
  return `<article class="pcard" data-person="${id}">
    <div class="hd">
      <span class="av" data-c="${p.c}">${p.letter}</span>
      <div class="stack">
        <div class="nm">${p.name} ${pillHTML(id)}</div>
        <div class="meta">${p.meta}</div>
      </div>
      <span class="ord">${p.ord}</span>
    </div>
    <div class="tags">${tagHTML(p.interests)}</div>
    <p class="quote">「${p.quote}」</p>
    <div class="ticket">
      <span class="k">依据</span>
      <span>为什么推给你：${p.why}</span>
    </div>
    <div class="acts">
      <button class="thinbtn solid" data-act="chat:${id}">打个招呼</button>
      <button class="thinbtn" data-act="keep">先记一下</button>
    </div>
  </article>`;
}

function renderHome(){
  $('#home-cards').innerHTML = TODAY.map(cardHTML).join('');
}

/* ── 资料 ───────────────────────────────────────────────────── */
function renderProfile(id){
  person = id;
  const p = PEOPLE[id];
  const feed = p.recent.map(([k, text, when]) => {
    const c = CIRCLES[k];
    return `<div class="feedrow" data-c="${c.c}">
      <span class="mark" data-c="${c.c}">${c.mark}</span>
      <div class="stack"><div class="body">${text}</div><span class="when">${when}</span></div>
    </div>`;
  }).join('');
  $('#profile-body').innerHTML = `
    <div class="profilehd">
      <span class="av lg" data-c="${p.c}">${p.letter}</span>
      <div class="stack">
        <div class="nm">${p.name} ${pillHTML(id)}</div>
        <div class="meta">${p.meta}<br>在这里 14 天</div>
      </div>
    </div>
    <p class="quote">「${p.quote}」</p>
    ${p.idnote ? `<div class="idnote">${p.idnote}</div>` : ''}
    <div class="pad">
      <div class="sect"><h2>最近在做什么</h2><span>来自 TA 的喜爱档案</span></div>
      <div class="card">${feed}</div>
    </div>
    <div class="pad">
      <div class="sect"><h2>你们重合的地方</h2><span>${p.interests.length} 个</span></div>
      <div class="card pad" data-c="${p.c}">
        <div class="tags" style="margin-top:0">${tagHTML(p.interests)}</div>
        <div class="ticket">
          <span class="k">依据</span>
          <span>${p.why}</span>
        </div>
      </div>
    </div>
    <div class="pad" style="margin-top:16px">
      <div class="btnrow">
        <button class="primary" data-act="chat:${id}">打个招呼</button>
        <button class="primary ghost" data-act="keep">先记一下</button>
      </div>
      <p class="footnote">「先记一下」只写进你自己的列表，对方不会收到任何通知。</p>
    </div>`;
}

/* ── 会话 ───────────────────────────────────────────────────── */
function logHTML(id){
  const p = PEOPLE[id];
  const ice = (id === 'du')
    ? `<div class="iceCard" data-c="${p.c}">
         <h4>你们都在${CIRCLES[p.interests[0]].name}。可以这样开口：</h4>
         ${p.ice.map((it, i) => `<div class="it" data-act="ice:${i}">
             <span>${it[0]}</span><span class="go">用这句</span></div>`).join('')}
       </div>`
    : '';
  const rows = p.log.map(([who, text]) => {
    if (who === 'day') return `<div class="dayline">${text}</div>`;
    return `<div class="bubble ${who === 'me' ? 'me' : 'ta'}">${text}</div>`;
  }).join('');
  return ice + rows;
}

function renderChat(id){
  person = id;
  const p = PEOPLE[id];
  $('#chat-name').textContent = p.name;
  $('#chat-pill').innerHTML = pillHTML(id);
  $('#chat-ctx').textContent = p.ctx;
  $('#chat-log').innerHTML = logHTML(id);
  const log = $('#chat-log');
  log.scrollTop = log.scrollHeight;
}

function pushBubble(cls, text){
  const log = $('#chat-log');
  const d = document.createElement('div');
  d.className = 'bubble ' + cls;
  d.textContent = text;
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
}

function reply(){
  const log = $('#chat-log');
  const t = document.createElement('div');
  t.className = 'typing';
  t.innerHTML = '<i></i><i></i><i></i>';
  log.appendChild(t);
  log.scrollTop = log.scrollHeight;
  setTimeout(() => { t.remove(); pushBubble('ta', PEOPLE[person].reply); }, 1400);
}

function send(text){
  text = (text || $('#chat-field').value || '').trim();
  if (!text) return;
  $('#chat-field').value = '';
  pushBubble('me', text);
  reply();
}

/* ── 底页 ───────────────────────────────────────────────────── */
function renderIce(){
  const list = PEOPLE[person].ice;
  const items = [0,1,2].map(n => list[(iceIndex + n) % list.length]);
  $('#ice-sub').textContent =
    `按你和${PEOPLE[person].name}的共同兴趣、还有对方最近的动态写的。挑一句，或者改两个字再发。`;
  $('#ice-list').innerHTML = items.map(it => `<div class="ice" data-act="iceuse">
      <div class="t">${it[0]}</div>
      <div class="w"><span class="k">依据</span><span>${it[1]}</span></div>
    </div>`).join('');
}

function sheet(name, on){
  $$('.sheet').forEach(s => s.classList.toggle('on', on && s.id === 'sh-' + name));
  $('#scrim').classList.toggle('on', !!on);
  if (on && name === 'ice') renderIce();
}

/* ── 导航 ───────────────────────────────────────────────────── */
const TAB_SCREENS = ['home','inbox','me','done'];

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
  $('#ask-break').hidden = id !== 'home';
  $$('#tabs a').forEach(a => a.classList.toggle('on', a.dataset.go === id));
  if (id === 'profile') renderProfile(person);
  if (id === 'chat'){
    if (!$('#chat-log').dataset.for || $('#chat-log').dataset.for !== person){
      $('#chat-log').dataset.for = person;
      renderChat(person);
    }
  }
}

function openChat(id){
  person = id;
  $('#chat-log').dataset.for = id;
  renderChat(id);
  go('chat');
}

function back(){
  const prev = history.pop() || 'home';
  go(prev, false);
}

/* ── 身份标识强度（走查台用） ───────────────────────────────── */
function setMark(level){
  document.body.dataset.mark = level;
}

/* ── 交互绑定 ───────────────────────────────────────────────── */
document.addEventListener('click', e => {
  const sw = e.target.closest('.sw');
  if (sw){ sw.classList.toggle('on'); toast(sw.classList.contains('on') ? '已打开' : '已关闭'); return; }

  const pick = e.target.closest('[data-pick]');
  if (pick){
    const k = pick.dataset.pick;
    picked.has(k) ? picked.delete(k) : picked.add(k);
    renderPicker();
    return;
  }

  const chip = e.target.closest('.chip');
  if (chip){ chip.classList.toggle('on'); return; }

  const act = e.target.closest('[data-act]');
  if (act){
    e.stopPropagation();
    const [verb, arg] = act.dataset.act.split(':');
    if (verb === 'chat')  openChat(arg);
    if (verb === 'keep')  toast('记下了。只有你看得到，对方不会收到通知。');
    if (verb === 'sheet') sheet(arg, true);
    if (verb === 'ice'){ openChat(person); sheet('ice', false); send(PEOPLE[person].ice[+arg][0]); }
    if (verb === 'iceuse'){ sheet('ice', false); send(PEOPLE[person].ice[iceIndex % PEOPLE[person].ice.length][0]); }
    return;
  }

  const card = e.target.closest('[data-person]');
  if (card){ renderProfile(card.dataset.person); go('profile'); return; }

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
    if (verb === 'go')     go(arg);
    if (verb === 'mark')   setMark(arg);
    if (verb === 'person'){ person = arg; go(current === 'profile' ? 'profile' : 'profile'); }
    if (verb === 'sheet')  sheet(arg, true);
  }
});

document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && e.target.id === 'chat-field'){ e.preventDefault(); send(); }
  if (e.key === 'Escape') sheet(null, false);
});

$('#send-btn').addEventListener('click', () => send());
$('#ice-btn').addEventListener('click', () => sheet('ice', true));
$('#ice-again').addEventListener('click', () => { iceIndex += 3; renderIce(); });
$('#ice-send').addEventListener('click', () => {
  const it = PEOPLE[person].ice[iceIndex % PEOPLE[person].ice.length];
  sheet('ice', false);
  send(it[0]);
});
$('#ask-break').addEventListener('click', () => sheet('ice', true));

/* 键盘可达：动态生成的卡片也能 Tab 到 */
function makeFocusable(root = document){
  $$('[data-go],[data-person],[data-sheet],[data-back],[data-pick],.thinbtn,.chip,.sw', root)
    .forEach(el => { if (!el.hasAttribute('tabindex')) el.tabIndex = 0; });
}

/* ── 初始化 ─────────────────────────────────────────────────── */
renderStars();
renderPicker();
renderHome();
renderProfile('che');
renderChat('che');
$('#inbox-rows').innerHTML = TODAY.map(id => {
  const p = PEOPLE[id];
  const [last, when, unread] = p.inbox;
  return `<div class="conv" data-act="chat:${id}" data-c="${p.c}">
    <span class="av" data-c="${p.c}">${p.letter}</span>
    <div class="stack">
      <div class="top"><span class="nm">${p.name}</span>${pillHTML(id)}</div>
      <div class="last">${last}</div>
    </div>
    ${unread ? `<span class="unread"></span>` : ''}
    <span class="when">${when}</span>
  </div>`;
}).join('');
go('splash', false);
makeFocusable();
new MutationObserver(() => makeFocusable()).observe(document.body, { childList: true, subtree: true });
