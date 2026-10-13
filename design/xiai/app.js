/* 喜爱 · 兴趣圈 — 原型交互
   数据全部是演示数据；真实实现里这些来自后端档案与公开数据源。 */

const C = {
  fishing:{
    id:'fishing', name:'喜爱钓鱼', mark:'钓', color:'#1F6A7A', deep:'#154C58',
    soft:'#DCEBEE', paper:'#EEF2F0', ink3:'#646A67', lv:'Lv.12',
    sub:'Lv.12 · 今天适合出钓',
    ask:'问问 AI：这周末适合出钓吗？',
    index:{ v:'72', verdict:'适合出钓',
      rail:[[13,'half'],[10,'half'],[6,''],[6,''],[26,'on'],[28,'on'],[14,'half'],[9,'half']],
      now:'58%', legend:['06:00','现在 15:20','22:00'],
      why:'<b>今天 15:00–18:00 最好：</b>东北风 2 级、水温 21℃，鱼口在傍晚回深水；十一后禁渔期已过，东明湖可下竿。',
      ticket:'凭你 9 月在东明湖的 3 次记录 + 今夜东北风降温' },
    jobs:[
      ['i-gear','装备推荐','给我预算和场景，我出配置方案，不推贵的','帮我配一套 2000 元钓鱼装备'],
      ['i-clock','出钓建议','结合天气、季节与你的历史时段，说清该几点去','这周末适合出钓吗？'],
      ['i-camera','鱼种识别','拍照识鱼，给习性与烹饪建议（拍照功能已下线）','我拍了一条鱼，怎么认？'],
      ['i-pin','钓点推荐','按位置与目标鱼种挑附近水域，标出禁渔与收费','附近哪里适合钓鲫鱼？'],
      ['i-spark','新手教程','按你的进度推下一步学什么，不塞一百篇教程','我该学什么？']
    ],
    last:{ q:'关于 4.5 米竿配多重铅', when:'昨天 21:04',
      a:'<b>你这支 4.5 米二八调，配 2.0g 铅最顺</b>，风大再加到 2.5g；线组别超过 1.2 号，否则回鱼慢。' },
    feed:[
      { who:'老周', lv:'Lv.19', when:'3 小时前', role:'同好',
        body:'东明湖北岸，风起来之后口反而好了。玉米香打底，两个小时三条。',
        facts:[['鱼种','鲫 1.2kg'],['水域','东明湖 北岸 2.5m'],['天气','东北风 2 级'],['时间','18:40']],
        tags:['鱼种·鲫','水域·东明湖','装备·夜光漂'],
        asks:['这个饵什么配方？','北岸哪个位置？'],
        reply:{ who:'王师傅', badge:'达人', text:'玉米香打底没错。北岸返鱼是因为水温回升到 21℃ 上下，鱼从 4 米往 2–3 米挪。你要去就赶 17 点前打完窝。' } },
      { who:'小林', lv:'Lv.6', when:'昨天', role:'同好',
        body:'4.5 米的竿，配多重的铅合适？我老是抛不准。',
        facts:[['装备','4.5m 二八调']], tags:['装备·竿','问题·线组'],
        asks:['我也想问'],
        ai:'抛不准多半不是铅的事：<b>先看主线是否超号</b>。4.5 米二八调配 2.0g 铅、1.0 号主线最顺；风大再上 2.5g。',
        paid:'转人工付费咨询 · 98 喜点' }
    ],
    archive:{
      stats:[['23','条渔获'],['31','次出钓'],['2.6kg','最重一尾']],
      level:{ pct:68, note:'距离 Lv.13 还差 2 次出钓 · 解锁「夜间时段胜率」' },
      groups:[
        { title:'装备库', note:'4 件在役',
          rows:[
            ['竿 · 浪尖 4.5m 二八调','2022-08 购入 · 出钓 28 次','¥480'],
            ['线组 · 0.8 / 1.2 主线','2022-09 购入 · 三年未换','¥48',1],
            ['浮漂 · 芦苇长脚 3 支','2023-04 购入 · 常用','¥180'],
            ['抄网 · 2.1m 碳素','2023-04 购入','¥180']
          ]},
        { title:'战绩', note:'最近 3 次',
          rows:[
            ['9 月 27 日 · 东明湖','12:30–16:00 · 无渔获 · 南风 3 级','—'],
            ['9 月 20 日 · 东明湖','17:10–20:30 · 鲫 0.8kg','—'],
            ['9 月 6 日 · 东明湖','18:40–22:00 · 鲫 1.2kg','—']
          ]}
      ],
      spend:{ total:'¥3,280', parts:[['竿 42%',42],['饵料 26%',26],['线组 18%',18],['其它 14%',14]],
        note:'今年累计。线组三年没换，弹性已经衰减，这是最便宜的一次升级。' },
      cta:'让 AI 读我的档案，给一条升级建议'
    },
    shop:{
      why:'依据来自你的档案：线组 2022-09 购入至今未换；近 3 次出钓都在东明湖，以鲫为主。',
      offers:[
        { name:'主线线组 0.8 / 1.0 / 1.2 各两副',
          sub:'三年未换的那副，换掉它比换竿更划算',
          price:'¥48', was:'¥68', shop:'三店同价',
          reviews:['「结节强度够，0.8 号拉 2 斤鲫没问题」<em>· 商品页 216 条</em>',
                   '「副线比主线软，回鱼快」<em>· 同好 老周</em>'],
          why:'你的线组已用 3 年 · 出钓 28 次' },
        { name:'浪尖 4.5m 二八调（你在看的那支）',
          sub:'和你现在这支同调性，备用或升级都合适',
          price:'¥480', was:'¥520', shop:'最低价',
          reviews:['「轻，抛一天不累」<em>· 商品页 89 条</em>',
                   '「二八调腰力偏硬，钓小鱼偏钝」<em>· 同好 小林</em>'],
          why:'你收藏夹里躺了 12 天' }
      ],
      note:'每件商品都带一张小票，写清为什么推给你。排序不看你买没买，只看你的档案与实测。'
    }
  },

  coffee:{
    id:'coffee', name:'喜爱咖啡', mark:'咖', color:'#6F4A2A', deep:'#553616',
    soft:'#EDE3D6', paper:'#F2EFE9', ink3:'#6E665D', lv:'Lv.8',
    sub:'Lv.8 · 豆子还有 3 天赏味期',
    ask:'问问 AI：新买的豆子怎么冲才对味？',
    index:{ v:'3', verdict:'天赏味期',
      rail:[[22,'half'],[24,'half'],[27,'on'],[25,'on'],[14,'half'],[10,'half'],[6,''],[6,'']],
      now:'12%', legend:['今天','现在','第 7 天'],
      why:'<b>茉香日晒该喝了：</b>烘焙后第 12 天，还剩 3 天风味窗口。15g / 92℃ / 1:15，比你昨天那杯再快 5 秒。',
      ticket:'凭你记的烘焙日与 42 次冲煮参数' },
    jobs:[
      ['i-spark','风味匹配','说你想要的味道，我挑豆子，不挑贵的','我想要果酸明显一点的'],
      ['i-clock','冲煮参数','按你的豆子与器具算水温、粉水比、时间','茉香日晒怎么冲？'],
      ['i-gear','设备推荐','从你的喝法倒推设备，不推整套','要不要买磨豆机？'],
      ['i-bag','豆单管理','记下烘焙日，到期前提醒你喝掉','我的豆子还剩几天？']
    ],
    last:{ q:'关于手冲水温', when:'前天 08:12',
      a:'<b>你的茉香日晒用 92℃ 正好</b>，浅烘再低会发酸；水流别断，1:15 里最后 30g 收尾。' },
    feed:[
      { who:'阿May', lv:'Lv.11', when:'5 小时前', role:'同好',
        body:'同一支豆子，磨粗一档之后甜感出来了。参数不是玄学，是差 1 格。',
        facts:[['豆子','茉香日晒'],['参数','15g / 92℃ / 1:15'],['器具','V60 01']],
        tags:['风味·甜','器具·V60'],
        asks:['磨多粗算粗？'],
        reply:{ who:'陈师傅', badge:'达人', text:'磨粗一档、注水慢 10 秒，甜感会更明显。你用的是哪台磨？平刀和锥刀差得挺多。' } },
      { who:'大李', lv:'Lv.5', when:'昨天', role:'同好',
        body:'手磨和电磨，差价值不值？',
        facts:[['预算','¥600 以内']], tags:['装备·磨豆机'],
        asks:['我也纠结'],
        ai:'<b>先看你一天喝几杯。</b>一天一杯，¥600 的手磨够用；一天三杯以上，电磨省下的时间比均匀度更值钱。',
        paid:'转人工付费咨询 · 98 喜点' }
    ],
    archive:{
      stats:[['6','支在库'],['42','杯记录'],['日晒','最常喝']],
      level:{ pct:44, note:'距离 Lv.9 还差 8 杯 · 解锁「烘焙曲线对照」' },
      groups:[
        { title:'豆单', note:'2 支在赏味期',
          rows:[
            ['茉香日晒','烘焙 10-01 · 还剩 3 天','还剩 3 天',1],
            ['曼特宁深烘','烘焙 09-18 · 已过窗口','已过期'],
            ['耶加雪菲水洗','烘焙 09-08 · 已喝完','已喝完']
          ]},
        { title:'我的配方', note:'记住了 3 条',
          rows:[['茉香日晒 · 手冲','15g / 92℃ / 1:15 · 2:20','常用'],
                ['曼特宁 · 美式','18g / 93℃ / 1:2 → 兑水 120g','偶尔']]}
      ],
      spend:{ total:'¥1,860', parts:[['豆子 62%',62],['器具 28%',28],['其它 10%',10]],
      note:'今年累计。豆子占大头，器具只买过一次，这很健康。' },
      cta:'让 AI 读我的豆单，说下一支买什么'
    },
    shop:{
      why:'依据来自你的豆单：日晒喝得最多，浅烘偏好明显；上一支耶加已经喝完 6 天。',
      offers:[
        { name:'耶加雪菲 日晒 200g',
          sub:'和你最喜欢的茉香日晒同一产区，风味更甜',
          price:'¥88', was:'¥98', shop:'烘焙商直发',
          reviews:['「草莓、酒心巧克力，甜得很直白」<em>· 商品页 74 条</em>',
                   '「建议养 5 天再喝」<em>· 同好 阿May</em>'],
          why:'你的口味记录里 6 支有 5 支是日晒' }
      ],
      note:'咖啡圈不接竞价推广：豆子只按你的口味记录与烘焙日期排。'
    }
  },

  cat:{
    id:'cat', name:'喜爱养猫', mark:'猫', color:'#6E5A8C', deep:'#554470',
    soft:'#E7E3EE', paper:'#EFEBF2', ink3:'#6C6770', lv:'Lv.15',
    sub:'Lv.15 · 猫粮剩 6 天',
    ask:'问问 AI：它这周掉毛变多，正常吗？',
    index:{ v:'6', verdict:'天猫粮余量',
      rail:[[22,'half'],[24,'half'],[27,'on'],[22,'half'],[15,'half'],[10,'half'],[6,''],[6,'']],
      now:'12%', legend:['今天','现在','第 7 天'],
      why:'<b>该补猫砂了：</b>按你 8 月以来的记录，4.2kg 的布偶这周体重持平，掉毛量比上月多，先看是不是换季。',
      ticket:'凭你上传的 2 次体重记录与猫砂购买日' },
    jobs:[
      ['i-spark','症状判断','说清症状与持续天数，我给可能的方向与就医线','它这周掉毛变多，正常吗？'],
      ['i-bag','猫粮成分','按成分表与你的预算比，不按销量排','这两款猫粮哪个好？'],
      ['i-clock','行为解读','半夜跑酷、乱尿、不吃饭，先排除生理原因','它最近老躲床底'],
      ['i-gear','用品清单','按体重与年龄算用量，提醒该补什么','我还缺什么？']
    ],
    last:{ q:'关于换粮', when:'3 天前 22:40',
      a:'<b>换粮要 7 天过渡</b>：新粮比例 1/4 起，每两天加一档。直接换容易软便，你上次就是这么开始的那三天。' },
    feed:[
      { who:'豆豆妈', lv:'Lv.21', when:'2 小时前', role:'同好',
        body:'换季掉毛和病理性掉毛，看三个地方就够了：皮肤有没有红点、掉的是整根还是断毛、食欲有没有变。',
        facts:[['品种','布偶'],['年龄','8 个月'],['体重','4.2kg']],
        tags:['主题·换季','症状·掉毛'],
        asks:['整根和断毛怎么分？'],
        reply:{ who:'李医生', badge:'执业兽医', text:'补一句：局部成片掉毛加舔舐过度，优先考虑皮肤问题，别先换粮。掉毛均匀、皮肤正常，多半是换季。' } },
      { who:'小满', lv:'Lv.7', when:'昨天', role:'同好',
        body:'猫粮快没了，想换一款。现在吃的是幼猫粮，要不要换成猫粮？',
        facts:[['体重','4.2kg'],['月龄','8']], tags:['猫粮·换粮'],
        asks:['我也是'],
        ai:'<b>8 个月可以先不换。</b>布偶体型发育到 12 个月，继续幼猫粮到一岁再换更稳；真要换，按 7 天过渡来。',
        paid:'转人工付费咨询 · 98 喜点' }
    ],
    archive:{
      stats:[['8','个月记录'],['4.2kg','当前体重'],['2 次','疫苗']],
      level:{ pct:82, note:'距离 Lv.16 还差 1 次体检记录 · 解锁「体重曲线对比」' },
      groups:[
        { title:'身体记录', note:'2 条',
          rows:[['10 月 5 日 · 称重','4.2kg · 与上月持平','—'],
                ['08 月 12 日 · 称重','3.9kg · 稳定增长','—']]},
        { title:'用品库存', note:'按日耗推算',
          rows:[['主粮 · 幼猫粮 2kg 装','剩 6 天 · 按 4.2kg 成猫日耗推算','6 天',1],
                ['猫砂 · 豆腐砂','已用完','该补'],
                ['驱虫 · 体内外','下次 11-02','—']]}
      ],
      spend:{ total:'¥4,120', parts:[['猫粮 48%',48],['医疗 24%',24],['猫砂 16%',16],['玩具 12%',12]],
      note:'今年累计。医疗那 24% 里有一次是应激性软便，就是换粮太急那次。' },
      cta:'让 AI 读我的记录，说这个月该注意什么'
    },
    shop:{
      why:'依据来自你的记录：豆腐砂已用完；主粮剩 6 天，与你上次的购买间隔一致。',
      offers:[
        { name:'豆腐砂 6L × 4 包',
          sub:'你一直用的那款，这次是四包组合价',
          price:'¥89', was:'¥116', shop:'最低价',
          reviews:['「结团实，冲厕所不堵」<em>· 商品页 1.2 万条</em>',
                   '「粉尘比膨润土小很多」<em>· 同好 豆豆妈</em>'],
          why:'你上次买它是 7 月 28 日' }
      ],
      note:'猫粮与药品类推荐会标注「非处方」，有症状先看医生。'
    }
  },

  fitness:{
    id:'fitness', name:'喜爱健身', mark:'健', color:'#45536B', deep:'#333E51',
    soft:'#E2E6ED', paper:'#EDEFF2', ink3:'#686D75', lv:'Lv.4',
    sub:'Lv.4 · 今天建议轻量',
    ask:'问问 AI：今天该练还是该歇？',
    index:{ v:'58', verdict:'建议轻量',
      rail:[[10,'half'],[8,''],[12,'half'],[26,'on'],[24,'on'],[16,'half'],[9,''],[6,'']],
      now:'55%', legend:['06:00','现在','22:00'],
      why:'<b>今天别加重量：</b>昨天深蹲后股四头肌仍紧，恢复分 58。练上肢 + 20 分钟有氧，明天再上腿。',
      ticket:'凭你 12 次训练记录与昨天的深蹲组数' },
    jobs:[
      ['i-clock','今天练什么','按恢复分与昨天的部位给计划','今天该练什么？'],
      ['i-spark','动作纠正','描述的疼法不同，处理方式完全不同','深蹲膝盖内扣怎么改？'],
      ['i-gear','补剂与装备','只在你缺口明确时才推荐','要不要买腰带？']
    ],
    last:{ q:'关于训练频率', when:'周一 20:30',
      a:'<b>一周三练足够</b>，你现在的问题不是练得少，是两次腿挨得太近。中间隔 72 小时。' },
    feed:[
      { who:'阿凯', lv:'Lv.14', when:'6 小时前', role:'同好',
        body:'恢复分比重量表好用。连着两周加重量，这周直接掉到 45，睡一觉就回来了。',
        facts:[['部位','下肢'],['恢复分','45 → 71'],['睡眠','7.5h']], tags:['主题·恢复'],
        asks:['恢复分怎么算？'],
      reply:{ who:'Coach 林', badge:'认证教练', text:'心率变异、静息心率、睡眠时长加权，个体差异大，看自己的趋势，别和别人的数字比。' } }
    ],
    archive:{
      stats:[['12','次训练'],['58','今日恢复'],['3','周连续']],
      level:{ pct:31, note:'距离 Lv.5 还差 5 次训练 · 解锁「力量曲线」' },
      groups:[{ title:'训练记录', note:'最近 2 次',
        rows:[['10-12 · 下肢','深蹲 5×5 · 卧推未练','—'],
              ['10-10 · 上肢','卧推 4×8 · 划船 3×10','—']]}],
      spend:{ total:'¥0', parts:[['未记录任何装备支出',100]],
      note:'今年没有装备支出，这个圈的 AI 不会硬凑一条推荐给你。' },
      cta:'让 AI 排下周的训练'
    },
    shop:{ why:'你没有填过装备缺口，所以这里只有一条与安全相关的提醒。',
      offers:[{ name:'深蹲鞋 / 腰带（未推荐）',
        sub:'AI 判断你的训练量还没到需要腰带的阶段',
        price:'—', was:'', shop:'暂不推荐',
        reviews:['「先把动作练稳，装备解决不了膝盖内扣」<em>· Coach 林</em>'],
        why:'留白也是结论' }],
      note:'这个圈会明确写「暂时不用买」。' }
  },

  money:{
    id:'money', name:'喜爱钱', mark:'钱', color:'#9E6322', deep:'#7A4A16',
    soft:'#F1E6D3', paper:'#F3F0E8', ink3:'#7C746A', lv:'Lv.3',
    sub:'Lv.3 · 今天没有要说的',
    ask:'问问 AI：我那套策略到底能不能做？',
    index:{ v:'—', verdict:'今天没有要说的', dim:true,
      rail:[[6,''],[6,''],[6,''],[6,''],[6,''],[6,''],[6,''],[6,'']],
      now:'92%', legend:['开盘','收盘 15:00','盘后'],
      why:'<b>没到该说话的时候：</b>你写的「缩量假突破」今天没过样本闸门，21 笔、不足 200 笔，记「样本不足」，不算淘汰。',
      ticket:'凭证伪档案的闸门规则与你那 21 笔记录' },
    jobs:[
      ['i-flag','证伪检查','先问「能不能做」，再谈绩效','帮我验一下我那套策略'],
      ['i-spark','结论解读','把结论句翻成人话，不美化','样本不足到底什么意思？'],
      ['i-clock','收盘后复盘','每天收盘给你一条判断，允许是零','今天盘面说明什么？']
    ],
    last:{ q:'关于成本尺', when:'上周五 15:40',
      a:'<b>1 分钟周期做不了。</b>往返成本吃掉这根 K 线平均振幅的一半以上，超过 40% 就是淘汰，换什么参数都一样。' },
    feed:[{ who:'证伪台', lv:'官方', when:'今天 15:10', role:'档案',
      body:'本周新增 6 条证伪记录：5 条淘汰、1 条仍在验证，0 条可交易。',
      facts:[['新增','6 条'],['可交易','0'],['样本不足','2']], tags:['证伪','周报'],
      asks:['为什么一条都没通过？'],
      ai:'<b>因为可交易只能人工给。</b>自动流程只负责判死：先过样本闸门，再看成本占比，最后才谈分年与回撤。' }],
    archive:{
      stats:[['21','笔样本'],['3','条证伪结论'],['0','条可交易']],
      level:{ pct:20, note:'距离 Lv.4 还差 5 次证伪 · 解锁「跨品种对比」' },
      groups:[{ title:'我关注的策略', note:'3 条',
        rows:[['缩量假突破','样本不足 · 21 笔 / 不足 200','样本不足',1],
              ['1 分钟均线交叉','淘汰 · 成本占振幅 52%','淘汰'],
              ['周线动量','仍在验证 · 第 2/3 年','验证中']]}],
      spend:{ total:'¥0', parts:[['没有订阅任何策略',100]],
        note:'这个圈不收策略订阅费。证伪结论本身就是免费内容。' },
      cta:'跑一次证伪（10 喜点）'
    },
    shop:{ why:'证伪档案没有商品。',
      offers:[{ name:'这里没有商城',
      sub:'结论免费、跑证伪按次计费，不靠卖东西活着',
        price:'—', was:'', shop:'—',
        reviews:['「先把不行的说清楚，比推荐一个能赚钱的实在」<em>· 产品原则</em>'],
        why:'留白也是结论' }],
      note:'策略相关内容先回答「能不能做」，再谈绩效。' }
  }
};

const CIRCLE_ORDER = ['money','fishing','coffee','cat','fitness'];
const PALETTE = { money:['#9E6322','#7A4A16','#F1E6D3','#F3F0E8','#7C746A'],
  fishing:['#1F6A7A','#154C58','#DCEBEE','#EEF2F0','#646A67'],
  coffee:['#6F4A2A','#553616','#EDE3D6','#F2EFE9','#6E665D'],
  cat:['#6E5A8C','#554470','#E7E3EE','#EFEBF2','#6C6770'],
  fitness:['#45536B','#333E51','#E2E6ED','#EDEFF2','#686D75'] };

const SCREENS = {
  home:    { palette:'money',   ask:true,  tabs:true,  tab:'home' },
  circles: { palette:'money',   ask:true,  tabs:true,  tab:'circles' },
  me:      { palette:'money',   ask:true,  tabs:true,  tab:'me' },
  quiz:    { palette:'money',   ask:false, tabs:false },
  empty:   { palette:'money',   ask:false, tabs:false },
  circle:  { palette:'circle',  ask:true,  tabs:true,  tab:'home' },
  chat:    { palette:'circle',  ask:false, tabs:false, composer:true }
};

let circle = 'fishing';
let current = 'home';
let history = [];

const $  = (s,r=document) => r.querySelector(s);
const $$ = (s,r=document) => [...r.querySelectorAll(s)];
const dev = $('#device');

/* ── 渲染 ─────────────────────────────────────────────────── */
function railHTML(idx){
  return `<div class="rail">` + idx.rail.map(([h,k],i)=>
      `<div class="cell ${k}" style="height:${h}px;--d:${i*60}ms"></div>`).join('') +
    `<div class="now" style="left:${idx.now}"></div></div>` +
    `<div class="rail-legend"><span>${idx.legend[0]}</span>` +
    `<span class="n">${idx.legend[1]}</span><span>${idx.legend[2]}</span></div>`;
}

function renderCircle(){
  const c = C[circle];
  $('#circle-mark').textContent = c.mark;
  $('#circle-mark').style.background = c.color;
  $('#circle-name').textContent = c.name;
  $('#circle-sub').textContent = c.sub;
  $('#chat-mark').textContent = c.mark;
  $('#chat-mark').style.background = c.color;
  $('#chat-sub').textContent = `${c.name} · 余额 12 喜点`;
  $('#ctx-text').textContent = `当前在「${c.name}」`;
  $('#ask-ph').textContent = c.ask;

  $('#circle-index').innerHTML = `
    <div class="who"><span class="mark" style="background:${c.color}">${c.mark}</span>
      <span class="nm">${c.name}</span><span class="lv">${c.lv}</span></div>
    <div class="reading"><span class="big num">${c.index.v}</span>
      <span class="verdict ${c.index.dim?'dim':''}">${c.index.verdict}</span></div>
    ${railHTML(c.index)}
    <div class="why">${c.index.why}</div>
    <div class="ticket" data-sheet="ticket"><svg><use href="#i-ticket"/></svg>
      <span>${c.index.ticket}</span><span class="go">看小票</span></div>`;

  $('#circle-jobs').innerHTML = c.jobs.map(([ic,t,n,q])=>`
    <div class="line" data-ask="${q}">
      <svg class="glyph"><use href="#${ic}"/></svg>
      <div class="stack"><div class="lead">${t}</div><div class="note">${n}</div></div>
      <svg class="chev"><use href="#i-chev"/></svg>
    </div>`).join('');

  $('#circle-last').innerHTML = `
    <div style="display:flex;align-items:baseline;gap:10px">
      <div style="font-size:13px;color:var(--ink-3);flex:1">上次问 · ${c.last.q}</div>
      <div class="mono">${c.last.when}</div></div>
    <div style="margin-top:11px;padding-top:11px;border-top:1px solid var(--hair);
      font-size:15px;line-height:1.7">${c.last.a}</div>
    <div style="margin-top:12px;display:flex;gap:8px">
      <button class="thinbtn" data-ask="继续上一个问题">继续追问</button>
      <button class="thinbtn" data-ask="把这条结论存进我的档案">存进档案</button></div>`;

  $('#feed-list').innerHTML = c.feed.map(p=>`
    <article class="post">
      <div class="head">
        <span class="avatar">${p.who.slice(0,1)}</span>
        <span class="who">${p.who}</span>
        <span class="lv">${p.lv}</span>
        <span class="when">${p.when}</span>
      </div>
      <p class="body">${p.body}</p>
      <div class="facts">${p.facts.map(([k,v])=>`<span><i>${k}</i>${v}</span>`).join('')}</div>
      <div style="margin-top:10px;display:flex;gap:6px;flex-wrap:wrap">
        ${p.tags.map(t=>`<span class="tag plain">AI 标注 · ${t}</span>`).join('')}</div>
      <div class="foot">
        ${p.asks.map(a=>`<button class="thinbtn" data-ask="${a}">${a}</button>`).join('')}
        ${p.paid?`<button class="thinbtn" data-sheet="upgrade">${p.paid}</button>`:''}
        <button class="thinbtn" style="margin-left:auto">收藏</button>
      </div>
      ${p.reply?`<div class="reply"><div class="who">${p.reply.who}
          <span class="tag">${p.reply.badge}</span></div>
        <p>${p.reply.text}</p></div>`:''}
      ${p.ai?`<div class="reply"><div class="who">喜爱 AI 先答
          <span class="tag plain">AI 兜底</span></div>
        <p>${p.ai}</p>
        <div style="margin-top:9px;display:flex;gap:8px">
          <button class="thinbtn" data-ask="展开这个回答">展开</button>
          <button class="thinbtn" data-ask="这条回答的依据是什么？">看依据</button></div></div>`:''}
    </article>`).join('');

  const a = c.archive;
  $('#archive-body').innerHTML = `
    <div class="stat">${a.stats.map(([v,k])=>`<div><div class="v">${v}</div><div class="k">${k}</div></div>`).join('')}</div>
    <div class="level">
      <div style="display:flex;align-items:baseline;gap:8px">
        <span style="font-size:15px;font-weight:600">${c.lv}</span>
        <span style="font-size:12px;color:var(--ink-3);margin-left:auto">${c.name}段位</span></div>
      <div class="track"><i style="width:${a.level.pct}%"></i></div>
      <p style="margin-top:9px;font-size:12px;color:var(--ink-2);line-height:1.6">${a.level.note}</p>
    </div>
    ${a.groups.map(g=>`
      <div class="sect"><h2>${g.title}</h2><span>${g.note}</span></div>
      <div class="card">${g.rows.map(([t,n,v,flag])=>`
        <div class="gear">
          <div><div class="nm">${t}</div><div class="meta">${n}</div></div>
          <div class="price">${v}</div></div>${flag?'':''}`).join('')}
      </div>`).join('')}
    <div class="sect"><h2>消费统计</h2><span>今年</span></div>
    <div class="card pad">
      <div style="display:flex;align-items:baseline;gap:8px">
        <span class="num" style="font-size:26px">${a.spend.total}</span>
        <span style="font-size:12px;color:var(--ink-3);margin-left:auto">${a.spend.parts.length} 类</span></div>
      <div class="bar-split">${a.spend.parts.map(([l,p],i)=>
        `<i style="width:${p}%;background:${c.color};opacity:${RAMP[i%RAMP.length]}"></i>`).join('')}</div>
      <div class="bar-keys">${a.spend.parts.map(([l,p],i)=>
        `<span><b style="background:${c.color};opacity:${RAMP[i%RAMP.length]}"></b>${l}</span>`).join('')}</div>
      <p style="margin-top:12px;padding-top:12px;border-top:1px solid var(--hair);
        font-size:12px;color:var(--ink-2);line-height:1.7">${a.spend.note}</p>
    </div>
    <div style="margin-top:16px">
      <button class="primary" data-ask="${a.cta}">${a.cta}</button>
      <p class="footnote">你的档案只在这个圈里可见。</p>
    </div>`;

  const s = c.shop;
  $('#shop-body').innerHTML = `
    <div class="sect" style="margin-top:4px"><h2>该升级什么了</h2><span>按你的档案排</span></div>
    <p class="lede" style="margin-bottom:14px">${s.why}</p>
    ${s.offers.map(o=>`
      <div class="offer">
        <span class="tag">为什么推给你 · ${o.why}</span>
        <div class="nm">${o.name}</div>
        <div class="sub">${o.sub}</div>
        <div class="price-row">
          <span class="now">${o.price}</span>
          ${o.was?`<span class="was">${o.was}</span>`:''}
          <span class="shop">${o.shop}</span></div>
        <div class="reviews">${o.reviews.map(r=>`<div>${r}</div>`).join('')}</div>
        <div style="margin-top:13px;display:flex;gap:8px">
          <button class="thinbtn solid" data-ask="这件东西和我的档案哪里对得上？">看小票</button>
          <button class="thinbtn" data-ask="有没有更便宜的替代？">比价</button></div>
      </div>`).join('')}
    <p class="footnote" style="text-align:left">${s.note}</p>`;
}

/* ── 对话 ─────────────────────────────────────────────────── */
const CHAT = {
  fishing:[[
    { me:'帮我配一套 2000 元钓鱼装备，主要钓鲫鱼，偶尔去水库' },
    { ai:'answer', claim:'2000 元配鲫鱼装备：竿和线组先花 528，剩下的留给灯和箱。',
      p:'你现在这支 4.5 米竿能用，<b>但线组是 2022 年 9 月的，必须先换</b>。' +
        '近 3 次出钓都在东明湖、以鲫为主，还都在傍晚以后，所以夜钓灯我留了 380 元。',
      plan:[['竿','浪尖 4.5m 二八调','鲫鱼主力，兼顾 3 斤以内鲤','¥480'],
            ['线组','0.8 / 1.2 各两副','原来那副用了三年，先换','¥48'],
            ['漂','芦苇长脚两套','一深一浅，够用','¥180'],
            ['饵','玉米香 + 红虫粉','东明湖鲫鱼认这个味','¥210'],
            ['箱','36L 钓箱','坐得稳，能装','¥320'],
            ['网','2.1m 抄网','','¥180'],
            ['灯','蓝光两档夜钓灯','你三次记录都在傍晚以后','¥380'],
            ['小件','铅皮、挡针、失手绳','','¥202']],
      bar:[[24], [2], [9], [11], [16], [9], [19], [10]],
      ticket:'依据：你的档案（竿 3 年、线组 3 年未换；近 3 次出钓都在东明湖且均为傍晚）+ 东明湖水域公开资料',
      follow:['这套能钓鲤鱼吗？','换成 1500 元怎么配？','存进我的档案'] }
  ]],
  coffee:[[
    { me:'茉香日晒怎么冲？我一直冲不出你说的甜味' },
    { ai:'answer', claim:'把水温降到 92℃、磨粗半格，甜味就出来了。',
      p:'这支是浅烘日晒，<b>你之前用 94℃ 是把甜味推过去了</b>。按你 42 次记录里的平均参数调一档就够。',
      plan:[['粉量','15g','你惯用的量','—'],
            ['水温','92℃','比你现在低 2℃','—'],
            ['粉水比','1:15','最后 30g 收尾','—'],
            ['时间','2:20','比昨天快 5 秒','—']],
      bar:[[36],[18],[22],[24]],
      ticket:'依据：你记的 42 次冲煮参数 + 这支豆子的烘焙度（浅烘，烘焙后第 12 天）',
      follow:['磨粗半格是多粗？','明天喝还来得及吗？','存进我的配方'] }
  ]],
  cat:[[
    { me:'它这周掉毛变多，正常吗？' },
    { ai:'answer', claim:'先别换粮：掉毛均匀且皮肤正常，多半是换季。',
      p:'8 个月、4.2kg、体重持平，这三条排掉了大部分病理性掉毛。<b>要看的是三件事：皮肤有没有红点、掉的是整根还是断毛、食欲有没有变。</b>' +
        '如果出现成片掉毛或过度舔舐，优先看皮肤，不要先动猫粮。',
      plan:[['皮肤','有红点 / 结痂？','有的话先看医生，别换粮','—'],
            ['毛发','整根脱落 vs 断毛','整根多为换季','—'],
            ['食欲','与上周比','下降超过两天请就医','—']],
      bar:[[40],[30],[30]],
      ticket:'依据：你的 2 次体重记录（3.9kg → 4.2kg）+ 换季掉毛的公开兽医资料；本答案不构成诊断',
      follow:['成片掉毛怎么办？','该换猫粮吗？','记下今天的状况'] }
  ]],
  fitness:[[
    { me:'今天该练还是该歇？' },
    { ai:'answer', claim:'今天练上肢 + 20 分钟有氧，别上腿。',
      p:'恢复分 58，处在「可以练但不该加量」的区间。<b>昨天深蹲 5×5，股四头肌现在还是紧的</b>，两次腿之间隔 72 小时更稳。',
      plan:[['今日','上肢推 + 拉','卧推 4×8、划船 3×10','—'],
            ['有氧','20 分钟','心率 130 上下','—'],
            ['不做','深蹲 / 硬拉','明天再上','—']],
      bar:[[45],[30],[25]],
      ticket:'依据：你 12 次训练记录（含昨天深蹲 5×5）+ 今日恢复分 58',
      follow:['恢复分怎么算的？','明天能上重量吗？','存进档案'] }
  ]],
  money:[[
    { me:'我那套缩量假突破，到底能不能做？' },
    { ai:'answer', claim:'不能做。现在还谈不上「能不能」，它只是样本不够。',
      p:'你记录了 21 笔，<b>样本闸门要求 ≥ 200 笔且有交易的年份 ≥ 3</b>，所以记「样本不足」，不算淘汰。' +
        '真要往前走，先把样本补到 200 笔，再看成本占振幅的比例。那是第二道闸门，也是最容易死人的一道。',
      plan:[['样本','21 笔','需要 ≥ 200 笔','未过'],
            ['年份','1 年','需要 ≥ 3 年','未过'],
            ['成本占比','—','样本不足，暂不计算','待定']],
      bar:[[33],[33],[34]],
      ticket:'依据：证伪档案的闸门规则（样本 ≥ 200 笔、年份 ≥ 3）+ 你的 21 笔记录；结论可以是零',
      follow:['那成本占比怎么算？','样本不足算淘汰吗？','跑一次证伪'] }
  ]]
};

/* 哪些问法可以直接落到这个圈已经写好的一版结论上 */
const FIRST_KEY = {
  fishing:/2000|配一套|装备|预算/,
  coffee:/怎么冲|冲煮|甜|参数|水温/,
  cat:/掉毛|正常吗|换粮|猫粮/,
  fitness:/练|歇|恢复|今天该/,
  money:/策略|能不能|证伪|样本/
};

function bubble(cls, html){ const d=document.createElement('div'); d.className='bubble '+cls; d.innerHTML=html; return d; }

/* 浓淡档：同一个品牌色靠透明度分层，换圈时整条数据条跟着换色 */
const RAMP = [0.95,0.8,0.66,0.54,0.42,0.32,0.22,0.14];

function renderAnswer(a){
  const box = document.createElement('div');
  box.className = 'answer';
  box.innerHTML = `
    <div class="claim">${a.claim}</div>
    <p>${a.p}</p>
    <div class="plan">${a.plan.map(([k,n,note,price])=>`
      <div class="pr"><span class="k">${k}</span>
        <span class="nm">${n}${note?`<em>${note}</em>`:''}</span>
        <span class="price">${price}</span></div>`).join('')}</div>
    <div class="bar">${a.bar.map(([p],i)=>
      `<i style="width:${p}%;background:var(--brand);opacity:${RAMP[i%RAMP.length]}"></i>`).join('')}</div>
    <div class="bar-keys">${a.plan.slice(0,4).map(([k,,,price],i)=>
      `<span><b style="background:var(--brand);opacity:${RAMP[i%RAMP.length]}"></b>${k} ${price}</span>`).join('')}
      <span>其余 ${a.plan.length-4} 项</span></div>
    <div class="ticket" style="margin-top:14px"><svg><use href="#i-ticket"/></svg>
      <span>${a.ticket}</span></div>
    <div class="followups">${a.follow.map(f=>
      `<button class="thinbtn" data-ask="${f}">${f}</button>`).join('')}</div>`;
  return box;
}

function renderChat(){
  const log = $('#chat-log');
  log.innerHTML = '';
  CHAT[circle][0].forEach(m=>{
    if (m.me) log.appendChild(bubble('me', m.me));
    else log.appendChild(renderAnswer(m));
  });
  scrollChat();
}

function scrollChat(){ const l=$('#chat-log'); l.scrollIntoView(false);
  const s=$('#s-chat'); s.scrollTop = s.scrollHeight; }

function ask(text){
  go('chat', true);
  const log = $('#chat-log');
  log.appendChild(bubble('me', text));
  const dots = document.createElement('div');
  dots.className='typing';
  dots.innerHTML='<i></i><i></i><i></i><span>正在按你的档案算…</span>';
  log.appendChild(dots); scrollChat();
  setTimeout(()=>{
    dots.remove();
    const c = C[circle];
    const scripted = CHAT[circle][0].filter(m=>m.ai)[0];
    let reply;
    if (/依据|凭什么|小票|展开/.test(text)) reply = { claim:'这条结论有三层依据，从最硬到最软。',
      p:'<b>最硬的是你自己的记录</b>：9 月 3 次东明湖，两次渔获都在 17:00 之后。' +
        '<b>其次是公开数据</b>：今夜东北风 2 级、气温降 4℃，水温按近三年同期插值 21℃。' +
        '<b>最软的是模型</b>：指数权重里「你的历史时段胜率」只占 15%，权重最小。',
      plan:[['你的记录','9 月 3 次出钓','两次渔获在 17:00 后','最硬'],
            ['公开数据','Open-Meteo','风、气温、气压','中等'],
            ['模型权重','时段胜率 15%','权重最小的一项','最软']],
      bar:[[45],[35],[20]],
      ticket:'依据分层：你的档案 → 公开数据 → 模型假设。任何一层都可以单独展开或删掉。',
      follow:['模型权重怎么定的？','把我的记录删掉会怎样？','存进我的档案'] };
    else if (scripted && FIRST_KEY[circle] && FIRST_KEY[circle].test(text)) reply = scripted;
    else if (/鲤/.test(text)) reply = { claim:'能钓，但三斤以上就别指望它。',
      p:'二八调的 4.5 米竿腰力偏硬，<b>一斤多的鲤没问题，超过三斤容易切线</b>。真要去水库守大鲤，把主线加到 1.5 号，子线 1.0，钩换 5 号伊势尼。',
      plan:[['主线','1.5 号','比现在粗一号','¥26'],['子线','1.0 号','','¥18'],['钩','5 号伊势尼','','¥12']],
      bar:[[46],[32],[22]],
      ticket:'依据：你这支竿的调性与线组规格 + 东明湖近三年鲤鱼的常见个体记录',
      follow:['切线了怎么办？','水库用多长的竿？','存进我的档案'] };
    else if (/1500|便宜|省/.test(text)) reply = { claim:'1500 元：砍掉夜钓灯，竿换成 3.6 米。',
      p:'<b>短竿更适合你现在的钓点</b>，北岸 2–3 米水深处 3.6 米更好控。夜钓先用手电凑，灯等下次再加。',
      plan:[['竿','3.6m 二八调','北岸近岸足够','¥360'],['线组','0.8 / 1.2 各两副','','¥48'],
            ['漂','芦苇长脚两支','','¥120'],['饵','玉米香 + 红虫粉','','¥210'],
            ['箱','钓箱 36L','','¥320'],['抄网','2.1m','','¥180'],['小件','铅皮、挡针','','¥262']],
      bar:[[24],[3],[8],[14],[21],[12],[18]],
      ticket:'依据：你的档案（近 3 次出钓都在东明湖北岸）+ 该水域水深公开资料',
      follow:['那灯什么时候买？','这样够用吗？','存进我的档案'] };
    else reply = { claim:'先说结论，再给依据。',
      p:`我按「${c.name}」里你的档案回答。现在手上有的记录是：${c.archive.stats.map(([v,k])=>`${k} ${v}`).join('、')}。` +
        '<b>缺哪一块我就直接说缺。</b>',
      plan:[['你的档案','已读取','只读这个圈的记录','—'],
            ['公开数据','已连接','天气 / 水域 / 商品页','—'],
            ['不确定的部分','会明确写','不猜','—']],
      bar:[[40],[35],[25]],
      ticket:'依据：这个圈的档案摘要。可以随时在「我的 → 清空某个圈的档案」里删掉。',
      follow:['这条依据能展开吗？','换个问法','存进档案'] };
    log.appendChild(renderAnswer(reply)); scrollChat();
  }, 900);
}

/* ── 屏幕与配色 ───────────────────────────────────────────── */
function go(id, keepScroll){
  if (!SCREENS[id]) return;
  if (id !== current) history.push(current);
  current = id;
  $$('.screen').forEach(s=>{ s.hidden = true; s.classList.remove('enter'); });
  const el = $('#s-'+id);
  el.hidden = false; el.classList.add('enter');
  if (!keepScroll) el.scrollTop = 0;

  const cfg = SCREENS[id];
  document.documentElement.dataset.circle = cfg.palette === 'circle' ? circle : 'money';
  $('#ask').hidden = !cfg.ask;
  $('#composer').hidden = !cfg.composer;
  $('#tabs').hidden = !cfg.tabs;
  $$('#tabs a').forEach(a=>a.classList.toggle('on', a.dataset.go === cfg.tab));
  $('#bottom').style.display = (cfg.ask||cfg.tabs||cfg.composer) ? '' : 'none';
  $$('.rbtn[data-go]').forEach(b=>{
    const t = b.dataset.enter || '';
    b.classList.toggle('on', b.dataset.go === id && (!t || t === circle));
  });
  if (id === 'chat') { renderChat(); }
  if (id === 'circle') { renderCircle(); }
  if (id === 'quiz') { quizReset(); }
  makeFocusable();
}

function setCircle(id, quiet){
  circle = id;
  document.documentElement.dataset.circle = (SCREENS[current].palette === 'circle') ? id : 'money';
  const p = PALETTE[id];
  $('#swatch').innerHTML = p.map(v=>`<b style="background:${v}"></b>`).join('');
  $$('.rbtn[data-circle]').forEach(b=>b.classList.toggle('on', b.dataset.circle === id));
  renderCircle();
  if (current === 'chat') renderChat();
}

/* 圈内页签切换（走查脚本也用它） */
function switchSeg(name){
  $$('.seg a').forEach(a=>a.classList.toggle('on', a.dataset.seg === name));
  $$('[data-panel]').forEach(p=>p.hidden = p.dataset.panel !== name);
  $$('.rbtn[data-seg]').forEach(b=>b.classList.toggle('on', b.dataset.seg === name));
  const s = $('#s-circle'); if (s) s.scrollTop = 0;
  makeFocusable();
}

/* ── 底页 ─────────────────────────────────────────────────── */
function sheet(name, on){
  $$('.sheet').forEach(s=>s.classList.toggle('on', on && s.id === 'sheet-'+name));
  $('#scrim').classList.toggle('on', !!on);
}

/* ── 兴趣测试 ─────────────────────────────────────────────── */
let quizStep = 1, quizAns = {};
function showStep(n){
  $$('[data-step]').forEach(s=>{
    if (s.dataset.step === 'nav') s.hidden = (n === 'result');
    else s.hidden = s.dataset.step !== String(n);
  });
  $$('[data-step-dot]').forEach(d=>d.classList.toggle('on',
    n === 'result' || +d.dataset.stepDot <= n));
  const btn = $('#quiz-next');
  btn.textContent = (n === 3) ? '看看结果' : '下一步';
  if (typeof n === 'number') btn.disabled = !quizAns[n-1];
}
function quizReset(){ quizStep = 1; quizAns = {};
  $$('.opt').forEach(o=>o.classList.remove('sel')); showStep(1); }
function quizNext(){
  if (quizStep < 3){ quizStep++; showStep(quizStep); }
  else showStep('result');
}

/* ── 事件 ─────────────────────────────────────────────────── */
const FOCUSABLE = '[data-go],[data-ask],[data-seg],[data-sheet],[data-sheet-close],' +
  '[data-circle],[data-opt]';

/* 自定义可点元素补上按钮语义与焦点，键盘与读屏都能用 */
function makeFocusable(root=document){
  $$(FOCUSABLE, root).forEach(el=>{
    const t = el.tagName;
    if (t === 'BUTTON' || t === 'INPUT' || (t === 'A' && el.hasAttribute('href'))) return;
    if (!el.hasAttribute('tabindex')) el.tabIndex = 0;
    if (!el.hasAttribute('role')) el.setAttribute('role', 'button');
  });
}

document.addEventListener('keydown', e=>{
  if (e.key !== 'Enter' && e.key !== ' ') return;
  const el = document.activeElement;
  if (!el || el === document.body || el.tagName === 'INPUT') return;
  if (el.matches && el.matches(FOCUSABLE)){ e.preventDefault(); el.click(); }
});

document.addEventListener('click', e=>{
  const circleBtn = e.target.closest('[data-circle]');
  if (circleBtn){ setCircle(circleBtn.dataset.circle); return; }
  const seg = e.target.closest('[data-seg]');
  if (seg){
    switchSeg(seg.dataset.seg); return;
  }
  const sheetBtn = e.target.closest('[data-sheet]');
  if (sheetBtn){ sheet(sheetBtn.dataset.sheet, true); return; }
  if (e.target.closest('[data-sheet-close]')){ sheet(null,false); return; }
  if (e.target === $('#scrim')){ sheet(null,false); return; }
  const askBtn = e.target.closest('[data-ask]');
  if (askBtn){ sheet(null,false); ask(askBtn.dataset.ask); return; }
  const opt = e.target.closest('.opt');
  if (opt){
    const box = opt.parentElement;
    $$('.opt', box).forEach(o=>o.classList.remove('sel'));
    opt.classList.add('sel');
    quizAns[quizStep-1] = opt.dataset.opt;
    $('#quiz-next').disabled = false;
    return;
  }
  const rbtn = e.target.closest('.rbtn');
  if (rbtn){
    if (rbtn.dataset.state){
      if (rbtn.dataset.state === 'ask-loading') ask('这周末适合出钓吗？');
      if (rbtn.dataset.state === 'ticket') sheet('ticket', true);
      if (rbtn.dataset.state === 'upgrade') sheet('upgrade', true);
      return;
    }
    if (rbtn.dataset.seg){ go('circle'); $$('.seg a').forEach(a=>
      a.classList.toggle('on', a.dataset.seg === rbtn.dataset.seg));
      $$('[data-panel]').forEach(p=>p.hidden = p.dataset.panel !== rbtn.dataset.seg); return; }
    if (rbtn.dataset.go) go(rbtn.dataset.go);
    return;
  }
  const goBtn = e.target.closest('[data-go]');
  if (goBtn){
    const t = goBtn.dataset.go;
    if (t === 'back'){ go(history.pop() || 'home'); return; }
    if (t === 'add-circles'){
      toast('已加入 2 个圈 · 首页多出两行今天的判断');
      $('#home-count').textContent = '7 个圈 · 3 个今天有话说';
      go('home'); return;
    }
    if (t === 'chat-why'){ sheet(null,false); ask('这条依据能展开吗？'); return; }
    if (t === 'chat'){ ask($('#ask-ph').textContent.replace('问问 AI：','')); return; }
    if (t === 'empty'){ go('empty'); return; }
    if (goBtn.dataset.enter){ setCircle(goBtn.dataset.enter, true); go('circle'); return; }
    go(t); return;
  }
});

$('#quiz-next').addEventListener('click', quizNext);
$('#send').addEventListener('click', ()=>{ const v=$('#field').value.trim();
  if (!v) return; $('#field').value=''; ask(v); });
$('#field').addEventListener('keydown', e=>{ if (e.key === 'Enter'){ $('#send').click(); } });
$('#ask').addEventListener('click', ()=>{ if (current !== 'chat') ask($('#ask-ph').textContent.replace('问问 AI：','')); });

const ORDER = ['home','circle','chat','quiz','circles','me','empty'];
document.addEventListener('keydown', e=>{
  if (e.target.tagName === 'INPUT') return;
  if (e.key === 'ArrowRight') go(ORDER[Math.min(ORDER.indexOf(current)+1, ORDER.length-1)]);
  if (e.key === 'ArrowLeft')  go(ORDER[Math.max(ORDER.indexOf(current)-1, 0)]);
  if (e.key === ' '){
    if (e.target.closest && e.target.closest(FOCUSABLE)) return;
    e.preventDefault(); go('home');
  }
  if (e.key === 'Escape') sheet(null,false);
});

function toast(msg){
  const t = document.createElement('div');
  t.textContent = msg;
  t.style.cssText = 'position:absolute;left:16px;right:16px;top:64px;z-index:9;'+
    'background:var(--ink);color:#fff;font-size:13px;line-height:1.5;padding:11px 13px;'+
    'border-radius:12px;box-shadow:var(--shadow);opacity:0;transition:opacity .2s ease';
  dev.appendChild(t); requestAnimationFrame(()=>t.style.opacity='1');
  setTimeout(()=>{ t.style.opacity='0'; setTimeout(()=>t.remove(),260); }, 2600);
}

/* 初始化 */
setCircle('fishing', true);
go('home');
sheet(null,false);
