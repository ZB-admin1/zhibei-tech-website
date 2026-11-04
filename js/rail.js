/* =========================================================
   智北轨道科普 · 前端逻辑
   - 三层目录树（单元 → 部分 → 小结）
   - 视频播放器 + 文档预览
   - 付费墙（解锁单元/部分/小结）
   - admin 自动全解锁
   ========================================================= */

(function () {
  'use strict';

  // ---------- Config ----------
  var API = (window.__zbRuntime || '') + '/api';
  var TOKEN_KEY = 'zb_rail_token';

  // ---------- Global State ----------
  var state = {
    token: null,
    user: null,
    role: null,
    catalog: null,
    prog: null,
    view: 'home',          // 'home' | 'unit' | 'lesson'
    viewParam: null,       // unitNo | lessonId
    openParts: {}          // 记录哪些 part 已展开
  };

  // ============================================================
  //   Canvas 视频播放器引擎 v3.0  （打字机/数字雨/浮动Emoji/声波/TTS）
  //   BUILD: 2026-11-01-2000
  // ============================================================
  console.log('[RAIL] Canvas engine v3.0 loaded (build 2026-11-01)');
  var videoPlayers = {};

  // ---- Emoji Map for each unit theme ----
  var ZB_EMOJIS = {
    1: ['🚆','🛤️','🛣️','📡','⚙️','🔧','📚','🏗️'],
    2: ['🚇','🚉','🚈','🏙️','🚌','🌆','🚦','🏗️'],
    3: ['🚄','🚅','🚆','💨','⚡','🔋','🛤️','🏁'],
    4: ['🚋','🚃','🚈','🔩','⚙️','🔧','🛠️','🏭'],
    5: ['🚦','🚥','🚧','🔴','🟢','⚡','📡','🛰️'],
    6: ['🔋','⚡','🔌','💧','🔥','⚙️','🏭','♻️'],
    7: ['🚉','🛤️','🚇','🚄','🚅','🚆','🚋','🏙️'],
    8: ['🛤️','🔩','⚙️','🔧','📐','📏','🏗️','🧱'],
    9: ['🚧','🏗️','🔨','⚒️','🛠️','📏','📐','🏭'],
    10: ['🖥️','💻','📊','📈','📉','🔬','🧪','📐'],
    11: ['🛡️','🔒','🔐','⚠️','🚨','🛡️','🔧','⚙️'],
    12: ['⚡','🔋','🔌','💡','🪫','🔆','🔅','⚙️'],
    13: ['🌊','💧','🔄','♻️','🧊','🔥','💨','⚙️'],
    14: ['🪨','⛏️','💎','🔩','⚙️','🔧','🏭','🧪'],
    15: ['🏗️','🧱','🔨','⚒️','🛠️','📏','📐','🏙️'],
    16: ['🚦','🚥','🚧','🚨','⚠️','🛡️','🛤️','🚉'],
    17: ['🚅','🚄','💨','⚡','🏁','🏎️','🛤️','🌊'],
    18: ['🚇','🚉','🛤️','🚆','🚌','🏙️','🚦','🌆'],
    19: ['📊','📈','📉','💡','💻','🖥️','🔬','🧪'],
    20: ['🎓','📚','🏆','🥇','📋','✅','🚀','🌟']
  };

  function initCanvasPlayer(vid, meta) {
    var wrap = document.getElementById('rbvp_' + vid);
    if (!wrap) return;
    var canvas = wrap.querySelector('.rbvp-canvas');
    if (!canvas) return;

    var theme = meta.theme || {};
    var subLines = meta.subtitle_lines || [];
    var duration = meta.duration || 90;
    var subDuration = meta.subtitle_duration || Math.max(2, Math.floor(duration / Math.max(subLines.length, 1)));
    var staticMode = meta.video_mode === 'static';
    var points = meta.points || subLines || [];
    var icon = meta.icon || '🚆';
    var unitNo = meta.unit_no || 1;

    // ===== 粒子系统 =====
    var particles = [];
    var ripples = [];

    if (staticMode) {
      for (var i = 0; i < 15; i++) {
        particles.push({ type: 'dot',
          x: Math.random() * 854, y: Math.random() * 480,
          r: Math.random() * 1 + 0.3,
          vx: (Math.random() - 0.5) * 0.15,
          vy: (Math.random() - 0.5) * 0.15,
          a: Math.random() * 0.3 + 0.15 });
      }
    } else {
      // 小光点（40）
      for (var i = 0; i < 40; i++) {
        particles.push({ type: 'dot',
          x: Math.random() * 854, y: Math.random() * 480,
          r: Math.random() * 1.5 + 0.5,
          vx: (Math.random() - 0.5) * 0.4,
          vy: (Math.random() - 0.5) * 0.4,
          a: Math.random() * 0.6 + 0.3 });
      }
      // 亮星（8，有光晕+闪烁）
      for (var j = 0; j < 8; j++) {
        particles.push({ type: 'star',
          x: Math.random() * 854, y: Math.random() * 480,
          r: Math.random() * 2.5 + 1.5,
          vx: (Math.random() - 0.5) * 0.2,
          vy: (Math.random() - 0.5) * 0.2,
          a: Math.random() * 0.8 + 0.2,
          twinkle: Math.random() * Math.PI * 2 });
      }
      // 关键词漂浮（5）
      var kwSource = points.slice(0, 5);
      for (var k = 0; k < kwSource.length; k++) {
        var kw = (kwSource[k] || '').substring(0, 4);
        if (kw) {
          particles.push({ type: 'kw', text: kw,
            x: Math.random() * 854, y: Math.random() * 480,
            vx: (Math.random() - 0.5) * 0.1,
            vy: (Math.random() - 0.5) * 0.08,
            a: 0.12 + Math.random() * 0.08 });
        }
      }
      // 数字雨（下落的中文字，20 条雨柱）
      var rainTexts = points.slice(0, 8).join('');
      if (!rainTexts) rainTexts = '轨道交通轨交地铁高铁信号牵引制动车站';
      for (var dr = 0; dr < 20; dr++) {
        particles.push({ type: 'rain',
          x: Math.random() * 854, y: Math.random() * -480,
          r: 1, vx: 0, vy: 1.5 + Math.random() * 2.5,
          a: 0.08 + Math.random() * 0.12,
          char: rainTexts[Math.floor(Math.random() * rainTexts.length)],
          speed: 1.5 + Math.random() * 2.5 });
      }
      // 浮动 Emoji（从单元主题取 6 个）
      var emojiPool = ZB_EMOJIS[unitNo] || ['🚆','🛤️','⚙️','🔧','📚','🏗️'];
      for (var fe = 0; fe < 6; fe++) {
        particles.push({ type: 'emoji',
          x: 50 + Math.random() * 750, y: 60 + Math.random() * 320,
          r: 1,
          vx: (Math.random() - 0.5) * 0.3,
          vy: (Math.random() - 0.5) * 0.2,
          a: 0.12 + Math.random() * 0.1,
          emoji: emojiPool[fe % emojiPool.length],
          size: 20 + Math.random() * 16,
          spin: Math.random() * Math.PI * 2,
          spinSpeed: (Math.random() - 0.5) * 0.02 });
      }
      // 环形波纹（3）
      for (var r = 0; r < 3; r++) {
        ripples.push({ cx: 120 + r * 200, cy: 80 + r * 120,
          r: 0, maxR: 80 + r * 30, speed: 0.5 + r * 0.15,
          phase: r * 2 });
      }
    }

    var player = {
      vid: vid, meta: meta, canvas: canvas, ctx: canvas.getContext('2d'),
      duration: duration, subLines: subLines, subDuration: subDuration,
      theme: theme, staticMode: staticMode, points: points, icon: icon,
      unitNo: unitNo,
      currentTime: 0, playing: false, startTime: 0, lastFrame: 0,
      t: 0, frame: 0,
      activeIdx: 0,
      // 动画插值
      subSlideIn: 0,
      cardPopIn: 0,
      titleFade: 0,
      subtitleBounce: 0,
      // v3.0 新增动画状态
      typewriterIdx: 0,       // 打字机当前显示到第几个字
      typewriterTimer: 0,     // 打字机计时
      cursorBlink: 0,         // 光标闪烁
      lightBurst: 0,          // 中心光爆强度（字幕切换时）
      scanOffset: 0,          // 光线扫过位置
      audioBars: null,        // 模拟声波柱状图
      particles: particles,
      ripples: ripples,
      ttsOn: false,
      ttsUtter: null,
      nextTtsIdx: 0
    };

    // 初始化模拟声波（48 个柱子）
    if (!staticMode) {
      var bars = [];
      for (var b = 0; b < 48; b++) {
        bars.push({ h: Math.random() * 20 + 4, targetH: Math.random() * 30 + 4,
          hue: 0, phase: Math.random() * Math.PI * 2 });
      }
      player.audioBars = bars;
    }

    videoPlayers[vid] = player;
    window.__videoPlayers = videoPlayers;  // 暴露给调试
    window.__renderCanvas = renderCanvas;  // 暴露给调试
    window.__vpLoop = vpLoop;              // 暴露给调试
    console.log('[RAIL] Player created:', vid, 'v3.0 particles=', particles.length);

    // 暴露全局控制
    window.__vpToggle = function(v) { vpToggle(v); };
    window.__vpSeek = function(v, ev) { vpSeek(v, ev); };
    window.__vpReplay = function(v) { vpReplay(v); };
    window.__vpTtsToggle = function(v) { vpTtsToggle(v); };

    // 在控制条加 TTS 按钮（animated 模式）
    if (!staticMode && wrap) {
      var ctrlBar = wrap.querySelector('.rbvp-controls');
      if (ctrlBar && !wrap.querySelector('.rbvp-tts-btn')) {
        var ttsBtn = document.createElement('button');
        ttsBtn.className = 'rbvp-tts-btn';
        ttsBtn.textContent = '🔊';
        ttsBtn.title = '语音朗读';
        ttsBtn.style.cssText = 'width:28px;height:28px;border:none;background:rgba(255,255,255,.12);color:white;border-radius:4px;cursor:pointer;font-size:14px;';
        ttsBtn.onclick = function() { vpTtsToggle(vid); };
        ctrlBar.insertBefore(ttsBtn, ctrlBar.firstChild.nextSibling.nextSibling.nextSibling.nextSibling);
      }
    }

    // 启动播放：用 setInterval + rAF 双保险（后台标签页也能跑）
    player.playing = true;
    player.startTime = performance.now();
    player.lastFrame = player.startTime;
    player._rafRunning = false;
    player._fallbackTimer = setInterval(function() {
      if (!player.playing) return;
      // 如果 rAF 卡住了（_rafRunning=false），手动推进
      if (!player._rafRunning) {
        var fakeTs = performance.now();
        vpLoop(vid, fakeTs);
      }
    }, 50);  // 20fps 保底
    requestAnimationFrame(function(ts) { vpLoop(vid, ts); });
  }

  // ---- TTS 语音朗读 ----
  function vpTtsToggle(vid) {
    var p = videoPlayers[vid]; if (!p) return;
    if (!('speechSynthesis' in window)) { toast('浏览器不支持语音'); return; }
    var btn = document.querySelector('#rbvp_' + vid + ' .rbvp-tts-btn');
    if (p.ttsOn) {
      window.speechSynthesis.cancel();
      p.ttsOn = false;
      p.nextTtsIdx = p.activeIdx;
      if (btn) btn.textContent = '🔊';
    } else {
      p.ttsOn = true;
      p.nextTtsIdx = p.activeIdx;
      if (btn) btn.textContent = '🔇';
      speakSubtitle(p);
    }
  }
  function speakSubtitle(p) {
    if (!p.ttsOn || p.nextTtsIdx >= p.subLines.length) { p.ttsOn = false; return; }
    var text = p.subLines[p.nextTtsIdx];
    if (!text) { p.nextTtsIdx++; speakSubtitle(p); return; }
    try {
      var u = new SpeechSynthesisUtterance(text);
      u.lang = 'zh-CN'; u.rate = 0.95; u.pitch = 1.0;
      u.onend = function() { p.nextTtsIdx++; };
      u.onerror = function() {};
      window.speechSynthesis.speak(u);
      p.ttsUtter = u;
    } catch (e) { p.ttsOn = false; }
  }

  function vpToggle(vid) {
    var p = videoPlayers[vid]; if (!p) return;
    if (p.playing) {
      p.playing = false;
      p.elapsed = (performance.now() - p.startTime) / 1000;
      var btn = document.querySelector('#rbvp_' + vid + ' .rbvp-play');
      if (btn) btn.textContent = '▶';
    } else {
      p.playing = true;
      p.startTime = performance.now() - (p.elapsed || 0) * 1000;
      var btn2 = document.querySelector('#rbvp_' + vid + ' .rbvp-play');
      if (btn2) btn2.textContent = '⏸';
      requestAnimationFrame(function(ts) { vpLoop(vid, ts); });
    }
  }
  function vpSeek(vid, ev) {
    var p = videoPlayers[vid]; if (!p) return;
    var bar = ev.currentTarget;
    var rect = bar.getBoundingClientRect();
    var pct = Math.max(0, Math.min(1, (ev.clientX - rect.left) / rect.width));
    p.currentTime = pct * p.duration;
    p.activeIdx = Math.min(p.subLines.length - 1, Math.floor(p.currentTime / p.subDuration));
    p.subSlideIn = 0; p.cardPopIn = 0;
    p.typewriterIdx = 0; p.typewriterTimer = 0; p.lightBurst = 1.0;
    p.startTime = performance.now() - p.currentTime * 1000;
  }
  function vpReplay(vid) {
    var p = videoPlayers[vid]; if (!p) return;
    p.currentTime = 0; p.activeIdx = 0;
    p.subSlideIn = 0; p.cardPopIn = 0; p.titleFade = 0; p.subtitleBounce = 0;
    p.typewriterIdx = 0; p.typewriterTimer = 0; p.lightBurst = 1.0; p.scanOffset = 0;
    p.playing = true;
    p.startTime = performance.now();
    requestAnimationFrame(function(ts) { vpLoop(vid, ts); });
    var btn = document.querySelector('#rbvp_' + vid + ' .rbvp-play');
    if (btn) btn.textContent = '⏸';
  }

  function vpLoop(vid, ts) {
    var p = videoPlayers[vid]; if (!p) return;
    if (!p.playing) { p._rafRunning = false; return; }
    p._rafRunning = true;

    var elapsed = (ts - p.startTime) / 1000;
    if (elapsed >= p.duration) {
      p.playing = false;
      var btn = document.querySelector('#rbvp_' + vid + ' .rbvp-play');
      if (btn) btn.textContent = '▶';
      renderCanvas(p);
      return;
    }
    p.currentTime = elapsed;
    p.t += 0.03; p.frame++;

    // 字幕切换 → 触发光爆 + 打字机重置
    var newIdx = Math.min(p.subLines.length - 1, Math.floor(elapsed / p.subDuration));
    if (newIdx !== p.activeIdx) {
      p.activeIdx = newIdx;
      p.subSlideIn = 0; p.cardPopIn = 0;
      p.typewriterIdx = 0; p.typewriterTimer = 0;
      p.lightBurst = 1.0;
      // TTS 联动
      if (p.ttsOn) { p.nextTtsIdx = newIdx; speakSubtitle(p); }
    }

    // 基础动画插值
    p.subSlideIn = Math.min(1, p.subSlideIn + 0.06);
    p.cardPopIn = Math.min(1, p.cardPopIn + 0.04);
    p.titleFade = Math.min(1, p.titleFade + 0.015);
    p.subtitleBounce *= 0.85;
    p.cursorBlink = (p.cursorBlink + 0.06) % (Math.PI * 2);
    p.scanOffset = (p.scanOffset + 1.2) % 900;
    p.lightBurst *= 0.96;

    // 打字机：每 3 帧显示一个字
    if (p.subLines[p.activeIdx]) {
      p.typewriterTimer++;
      if (p.typewriterTimer >= 3) {
        p.typewriterTimer = 0;
        if (p.typewriterIdx < p.subLines[p.activeIdx].length) p.typewriterIdx++;
      }
    }

    // 粒子更新
    if (p.particles) {
      for (var i = 0; i < p.particles.length; i++) {
        var pt = p.particles[i];
        pt.x += pt.vx; pt.y += pt.vy;
        // 不同类型的边界处理
        if (pt.type === 'rain') {
          if (pt.y > 530) { pt.y = -20; pt.x = Math.random() * 854;
            pt.char = (p.points || [''])[Math.floor(Math.random() * Math.min(p.points.length, 8))] || '轨';
            pt.char = pt.char[Math.floor(Math.random() * pt.char.length)];
          }
        } else if (pt.type === 'emoji') {
          pt.spin += pt.spinSpeed;
          if (pt.x < -50) pt.x = 904; if (pt.x > 904) pt.x = -50;
          if (pt.y < -50) pt.y = 530; if (pt.y > 530) pt.y = -50;
        } else {
          if (pt.x < -50) pt.x = 904; if (pt.x > 904) pt.x = -50;
          if (pt.y < -50) pt.y = 530; if (pt.y > 530) pt.y = -50;
          if (pt.type === 'star') pt.twinkle += 0.05;
        }
      }
    }
    // 波纹更新
    if (p.ripples) {
      for (var r = 0; r < p.ripples.length; r++) {
        var rp = p.ripples[r];
        rp.r += rp.speed;
        if (rp.r > rp.maxR) rp.r = 0;
      }
    }
    // 声波柱状图更新（模拟）
    if (p.audioBars) {
      for (var ab = 0; ab < p.audioBars.length; ab++) {
        var b = p.audioBars[ab];
        b.phase += 0.1 + Math.random() * 0.05;
        b.targetH = 10 + Math.abs(Math.sin(b.phase + p.t)) * 40;
        b.h += (b.targetH - b.h) * 0.15;
      }
    }

    // UI 进度条
    var wrap = document.getElementById('rbvp_' + vid);
    if (wrap) {
      var bar = wrap.querySelector('.rbvp-bar');
      var cur = document.getElementById('rbvp_cur_' + vid);
      if (bar) bar.style.width = (elapsed / p.duration * 100).toFixed(1) + '%';
      if (cur) cur.textContent = fmtDur(Math.floor(elapsed));
    }

    renderCanvas(p);
    requestAnimationFrame(function(ts2) { vpLoop(vid, ts2); });
  }

  // ============================================================
  //   渲染主函数 v3.0 — 14 层叠加（打字机/数字雨/浮动Emoji/声波/光爆/网络图）
  // ============================================================
  function renderCanvas(p) {
    var ctx = p.ctx, W = 854, H = 480, t = p.t;
    var theme = p.theme;
    var accentHex = theme.accent || '#0f3460';
    ctx.clearRect(0, 0, W, H);

    // ============ L1：背景渐变 + 顶/底暗化 ============
    var bg = ctx.createLinearGradient(0, 0, W, H);
    bg.addColorStop(0, theme.bg_from || '#1a1a2e');
    bg.addColorStop(1, theme.bg_to || '#16213e');
    ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
    var bs = ctx.createLinearGradient(0, H - 150, 0, H);
    bs.addColorStop(0, 'rgba(0,0,0,0)'); bs.addColorStop(1, 'rgba(0,0,0,0.65)');
    ctx.fillStyle = bs; ctx.fillRect(0, H - 150, W, 150);
    var ts = ctx.createLinearGradient(0, 0, 0, 120);
    ts.addColorStop(0, 'rgba(0,0,0,0.55)'); ts.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = ts; ctx.fillRect(0, 0, W, 120);

    if (p.staticMode) {
      // ============ U1 static：简化版 L2-L10 ============
      ctx.save();
      ctx.strokeStyle = 'rgba(255,255,255,0.07)'; ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(W * 0.1, 30); ctx.lineTo(W * 0.1, H - 30);
      ctx.moveTo(W * 0.9, 30); ctx.lineTo(W * 0.9, H - 30);
      ctx.moveTo(30, H * 0.55); ctx.lineTo(W - 30, H * 0.55);
      ctx.moveTo(30, H * 0.85); ctx.lineTo(W - 30, H * 0.85);
      ctx.stroke();
      ctx.font = 'bold 220px sans-serif';
      ctx.fillStyle = 'rgba(255,255,255,0.04)';
      ctx.textAlign = 'left'; ctx.textBaseline = 'bottom';
      ctx.fillText((p.meta.unit_no || 1), 30, H - 40);
      ctx.restore();
      drawParticles(ctx, p, 1);
      drawTitle(ctx, p, 1);
      drawSubtitleCard(ctx, p, 1, accentHex);
      drawTimeline(ctx, p, 1, accentHex);
      drawBranding(ctx, p, 1);
      return;
    }

    // ============ L2：背景装饰（光晕 + 轨道线 + 波纹 + 同心圆） ============
    var gx = W / 2 + Math.sin(t * 0.5) * 60;
    var gy = H / 2 + Math.cos(t * 0.4) * 30;
    var halo = ctx.createRadialGradient(gx, gy, 0, gx, gy, 360);
    halo.addColorStop(0, accentHex + '66');
    halo.addColorStop(0.4, accentHex + '22');
    halo.addColorStop(1, 'transparent');
    ctx.fillStyle = halo; ctx.fillRect(0, 0, W, H);

    // 底部双轨道波纹
    ctx.save();
    ctx.strokeStyle = 'rgba(255,255,255,0.1)'; ctx.lineWidth = 2;
    for (var tr = 0; tr < 2; tr++) {
      ctx.beginPath();
      ctx.moveTo(-20, H - 30 + tr * 20);
      for (var x = -20; x <= W + 20; x += 4) {
        var yo = Math.sin((x + t * 20 + tr * 1.5) * 0.02) * 3;
        ctx.lineTo(x, H - 30 + tr * 20 + yo);
      }
      ctx.stroke();
    }
    ctx.restore();

    // 扩散波纹
    if (p.ripples) {
      for (var r = 0; r < p.ripples.length; r++) {
        var rp = p.ripples[r];
        var prog = rp.r / rp.maxR;
        var alpha = (1 - prog) * 0.25;
        ctx.save();
        ctx.strokeStyle = accentHex + Math.floor(alpha * 255).toString(16).padStart(2, '0');
        ctx.lineWidth = 2 * (1 - prog);
        ctx.beginPath();
        ctx.arc(rp.cx + Math.sin(t + rp.phase) * 10,
                rp.cy + Math.cos(t * 0.8 + rp.phase) * 8,
                rp.r, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      }
    }

    // 同心圆（旋转）
    ctx.save();
    ctx.translate(W / 2, H / 2);
    ctx.rotate(t * 0.15);
    ctx.strokeStyle = 'rgba(255,255,255,0.05)'; ctx.lineWidth = 1;
    for (var ring = 1; ring <= 4; ring++) {
      ctx.beginPath();
      for (var a = 0; a < Math.PI * 2; a += 0.15) {
        var rr = 100 + ring * 60 + Math.sin(a * 4 + t) * 8;
        var xx = Math.cos(a) * rr; var yy = Math.sin(a) * rr * 0.55;
        if (a === 0) ctx.moveTo(xx, yy); else ctx.lineTo(xx, yy);
      }
      ctx.stroke();
    }
    ctx.restore();

    // ============ L3：粒子系统（dot + star + kw + rain + emoji） ============
    drawParticles(ctx, p, 0);

    // ============ L4：声波波形柱（底部装饰，48 根柱子） ============
    if (p.audioBars) {
      var barTotal = p.audioBars.length;
      var bw = 4, bgap = 2, bStartX = (W - barTotal * (bw + bgap)) / 2;
      var baseY = H - 48;
      ctx.save();
      for (var bi = 0; bi < barTotal; bi++) {
        var bar = p.audioBars[bi];
        var bh = bar.h;
        var hue = (bi * 360 / barTotal + t * 30) % 360;
        ctx.fillStyle = 'hsla(' + hue + ', 80%, 65%, 0.35)';
        roundRect(ctx, bStartX + bi * (bw + bgap), baseY - bh / 2, bw, bh, 1);
        ctx.fill();
      }
      ctx.restore();
    }

    // ============ L5：顶部标题栏（霓虹发光效果） ============
    drawTitle(ctx, p, 0);

    // ============ L6：中央主字幕卡（打字机 + 闪烁光标 + 3D 阴影） ============
    drawSubtitleCard(ctx, p, 0, accentHex);

    // ============ L7：知识点组（3 张卡片 + 网络图连线 + emoji 徽章） ============
    drawKnowledgeGroup(ctx, p, accentHex);

    // ============ L8：底部时间轴 ============
    drawTimeline(ctx, p, 0, accentHex);

    // ============ L9：左下角时间 + Lesson ID ============
    ctx.save();
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.font = '10px monospace';
    ctx.textAlign = 'left'; ctx.textBaseline = 'bottom';
    ctx.fillText(p.vid.toUpperCase() + '  ·  ' + fmtDur(Math.floor(p.currentTime)) + ' / ' + fmtDur(p.duration), 22, H - 8);
    ctx.restore();

    // ============ L10：左上角品牌徽章（+ TTS 状态） ============
    drawBranding(ctx, p, 0);

    // ============ L11：光线扫过（横向光带） ============
    ctx.save();
    var sOffset = p.scanOffset;
    if (sOffset < W) {
      var sg = ctx.createLinearGradient(sOffset - 30, 0, sOffset + 30, 0);
      sg.addColorStop(0, 'transparent');
      sg.addColorStop(0.5, 'rgba(255,255,255,0.06)');
      sg.addColorStop(1, 'transparent');
      ctx.fillStyle = sg;
      ctx.fillRect(sOffset - 30, 0, 60, H);
    }
    ctx.restore();

    // ============ L12：扫描线（竖向） ============
    ctx.save();
    var scanY = (t * 80) % (H + 40) - 20;
    var scanGrad = ctx.createLinearGradient(0, scanY - 20, 0, scanY + 20);
    scanGrad.addColorStop(0, 'transparent');
    scanGrad.addColorStop(0.5, 'rgba(255,255,255,0.04)');
    scanGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = scanGrad;
    ctx.fillRect(0, scanY - 20, W, 40);
    ctx.restore();

    // ============ L13：中心光爆（字幕切换时） ============
    if (p.lightBurst > 0.02) {
      ctx.save();
      var burstGrad = ctx.createRadialGradient(W / 2, H * 0.42, 0, W / 2, H * 0.42, 280);
      burstGrad.addColorStop(0, 'rgba(255,255,255,' + (p.lightBurst * 0.25).toFixed(2) + ')');
      burstGrad.addColorStop(0.3, accentHex + Math.floor(p.lightBurst * 80).toString(16).padStart(2, '0'));
      burstGrad.addColorStop(1, 'transparent');
      ctx.fillStyle = burstGrad;
      ctx.fillRect(0, 0, W, H);
      ctx.restore();
    }

    // ============ L14：Vignette 暗角 ============
    ctx.save();
    var vg = ctx.createRadialGradient(W / 2, H / 2, W * 0.3, W / 2, H / 2, W * 0.75);
    vg.addColorStop(0, 'transparent');
    vg.addColorStop(1, 'rgba(0,0,0,0.45)');
    ctx.fillStyle = vg; ctx.fillRect(0, 0, W, H);
    ctx.restore();
  }

  // ===== 子绘制函数 =====

  function drawParticles(ctx, p, mode) {
    if (!p.particles) return;
    var W = 854, H = 480, theme = p.theme, t = p.t;
    for (var i = 0; i < p.particles.length; i++) {
      var pt = p.particles[i];
      if (pt.type === 'dot') {
        ctx.save(); ctx.globalAlpha = pt.a;
        ctx.fillStyle = '#ffffff';
        ctx.beginPath(); ctx.arc(pt.x, pt.y, pt.r, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
      } else if (pt.type === 'star') {
        var tw = 0.5 + 0.5 * Math.sin(pt.twinkle);
        ctx.save();
        var sg = ctx.createRadialGradient(pt.x, pt.y, 0, pt.x, pt.y, pt.r * 4);
        sg.addColorStop(0, 'rgba(255,255,255,' + (pt.a * tw).toFixed(2) + ')');
        sg.addColorStop(0.3, 'rgba(255,255,255,' + (pt.a * tw * 0.4).toFixed(2) + ')');
        sg.addColorStop(1, 'transparent');
        ctx.fillStyle = sg;
        ctx.fillRect(pt.x - pt.r * 4, pt.y - pt.r * 4, pt.r * 8, pt.r * 8);
        ctx.fillStyle = '#ffffff';
        ctx.beginPath();
        ctx.arc(pt.x, pt.y, pt.r * (0.7 + 0.3 * tw), 0, Math.PI * 2); ctx.fill();
        ctx.restore();
      } else if (pt.type === 'kw') {
        ctx.save(); ctx.globalAlpha = pt.a;
        ctx.fillStyle = theme.title || '#ffffff';
        ctx.font = 'bold 16px sans-serif';
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(pt.text, pt.x, pt.y);
        ctx.restore();
      } else if (pt.type === 'rain') {
        ctx.save();
        var hue2 = ((i * 30) + t * 20) % 360;
        ctx.fillStyle = 'hsla(' + hue2 + ', 70%, 65%, ' + pt.a.toFixed(2) + ')';
        ctx.font = '14px sans-serif';
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(pt.char, pt.x, pt.y);
        ctx.restore();
      } else if (pt.type === 'emoji') {
        ctx.save();
        ctx.globalAlpha = pt.a;
        ctx.translate(pt.x, pt.y);
        ctx.rotate(Math.sin(t + i) * 0.1 + pt.spin);
        ctx.font = pt.size + 'px sans-serif';
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(pt.emoji, 0, 0);
        ctx.restore();
      }
    }
  }

  function drawTitle(ctx, p, mode) {
    if (p.titleFade <= 0.01) return;
    var W = 854, H = 480, theme = p.theme;
    ctx.save();
    ctx.globalAlpha = p.titleFade;

    // 左侧竖排
    ctx.save(); ctx.translate(25, H / 2); ctx.rotate(-Math.PI / 2);
    ctx.fillStyle = 'rgba(255,255,255,0.15)';
    ctx.font = 'bold 11px sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText('UNIT ' + (p.meta.unit_no || 1) + ' · PART ' + (p.meta.part_no || 1), 0, 0);
    ctx.restore();

    // 右上角大 emoji（带发光）
    ctx.save();
    ctx.font = '48px sans-serif';
    ctx.textAlign = 'right'; ctx.textBaseline = 'top';
    ctx.globalAlpha = p.titleFade * 0.7;
    ctx.shadowColor = (theme.accent || '#e94560') + 'aa';
    ctx.shadowBlur = 16;
    ctx.fillText(p.icon || '🚆', W - 20, 18);
    ctx.restore();

    // 顶部单元名（霓虹发光 + 渐变描边）
    ctx.globalAlpha = p.titleFade;
    var unitTxt = '第 ' + (p.meta.unit_no || 1) + ' 单元 · ' + (p.meta.unit_name || '');
    ctx.font = 'bold 14px sans-serif';
    // 截断
    while (ctx.measureText(unitTxt + '…').width > W - 120 && unitTxt.length > 10) {
      unitTxt = unitTxt.substring(0, unitTxt.length - 1);
    }
    var tW = ctx.measureText(unitTxt).width;
    // 渐变描边（彩虹）
    if (mode === 0) {
      var grad = ctx.createLinearGradient(W / 2 - tW / 2, 0, W / 2 + tW / 2, 0);
      grad.addColorStop(0, '#ffd23f'); grad.addColorStop(0.5, theme.title || '#ffffff'); grad.addColorStop(1, '#ff6b6b');
      ctx.fillStyle = grad;
    } else {
      ctx.fillStyle = 'rgba(255,255,255,0.65)';
    }
    ctx.textAlign = 'center'; ctx.textBaseline = 'top';
    ctx.shadowColor = (theme.accent || '#e94560') + '88';
    ctx.shadowBlur = mode === 0 ? 10 : 0;
    ctx.fillText(unitTxt, W / 2, 12);
    ctx.shadowBlur = 0;

    // 部分名（小字）
    ctx.fillStyle = theme.subtitle || '#a8e6cf';
    ctx.font = '12px sans-serif';
    ctx.fillText('— ' + (p.meta.part_name || '') + ' —', W / 2, 32);

    ctx.restore();
  }

  function drawSubtitleCard(ctx, p, mode, accentHex) {
    if (p.subSlideIn <= 0.01 || !p.subLines[p.activeIdx]) return;
    var W = 854, H = 480, theme = p.theme;
    var text = (p.subLines[p.activeIdx] || '') + '';
    var ease = 1 - Math.pow(1 - p.subSlideIn, 3);
    var scale = 0.85 + ease * 0.15;
    var offsetY = (1 - ease) * 18;
    var fade = ease;
    var cardFontSize = mode === 0 ? 26 : 22;

    // 计算显示字数（打字机）
    var showIdx = p.typewriterIdx;
    if (showIdx < 1) showIdx = 1;
    var shownText = text.substring(0, Math.min(showIdx, text.length));
    var isTyping = showIdx < text.length;
    // 关键词高亮列表（前 3 个词）
    var keywords = (p.points || []).slice(0, 3);

    ctx.save();
    ctx.translate(W / 2, H * 0.42);
    ctx.scale(scale, scale);
    ctx.translate(-W / 2, -H * 0.42 + offsetY);
    ctx.globalAlpha = fade;

    // 字幕卡（根据整段文字宽度）
    ctx.font = 'bold ' + cardFontSize + 'px sans-serif';
    var cardW = Math.min(W * 0.8, ctx.measureText(text).width + 90);
    if (cardW < 300) cardW = 300;
    var cardH = 72;
    var cardX = W / 2 - cardW / 2;
    var cardY = H * 0.42 - cardH / 2;

    // 3D 立体阴影层（偏移 4 层）
    for (var sh = 4; sh >= 1; sh--) {
      ctx.fillStyle = 'rgba(0,0,0,' + (0.15 + sh * 0.08) + ')';
      roundRect(ctx, cardX + sh, cardY + sh, cardW, cardH, 14);
      ctx.fill();
    }

    // 主卡背景（毛玻璃）
    ctx.shadowBlur = 0;
    ctx.fillStyle = 'rgba(10,10,20,0.75)';
    roundRect(ctx, cardX, cardY, cardW, cardH, 14); ctx.fill();

    // 边框
    ctx.strokeStyle = accentHex + '55';
    ctx.lineWidth = 1.5;
    roundRect(ctx, cardX, cardY, cardW, cardH, 14); ctx.stroke();

    // 左侧 accent 竖条
    ctx.fillStyle = accentHex;
    roundRect(ctx, cardX, cardY, 4, cardH, 2); ctx.fill();

    // 顶部进度线（字幕在 subDuration 内的进度）
    var topLinePct = ((p.frame % (p.subDuration * 60)) / (p.subDuration * 60));
    ctx.fillStyle = accentHex;
    ctx.globalAlpha = fade * 0.6;
    ctx.fillRect(cardX + 8, cardY + 3, Math.max(0, topLinePct * (cardW - 16)), 2);
    ctx.globalAlpha = fade;

    // ====== 字幕文字（打字机 + 关键词高亮 + 3D 阴影） ======
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';

    // 检测是否需要换行
    var displayText = shownText;
    var lines = [];
    if (ctx.measureText(displayText).width > cardW - 70) {
      var halfLen = Math.ceil(displayText.length / 2);
      var splitAt = Math.max(displayText.lastIndexOf(' ', halfLen),
                            displayText.lastIndexOf('，', halfLen),
                            displayText.lastIndexOf('、', halfLen),
                            halfLen);
      if (splitAt < halfLen / 2) splitAt = halfLen;
      lines = [displayText.substring(0, splitAt), displayText.substring(splitAt)];
    } else {
      lines = [displayText];
    }

    var lineH = cardFontSize + 6;
    var startY = H * 0.42 - (lines.length - 1) * lineH / 2;

    for (var li = 0; li < lines.length; li++) {
      var lineTxt = lines[li];
      // 关键词高亮：检查行内是否包含关键词
      var hasKw = false, kwIdx = -1;
      for (var ki = 0; ki < keywords.length; ki++) {
        var k = keywords[ki];
        if (k && lineTxt.indexOf(k) !== -1) { hasKw = true; kwIdx = ki; break; }
      }

      // 先画 3D 阴影（多层偏移）
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.font = 'bold ' + cardFontSize + 'px sans-serif';
      ctx.fillText(lineTxt, W / 2 + 2, startY + li * lineH + 2);

      // 发光描边
      ctx.shadowColor = accentHex + 'cc';
      ctx.shadowBlur = 10;

      // 填充文字
      if (hasKw) {
        // 带关键词高亮（简化处理：整行 accent 色）
        ctx.fillStyle = theme.title || '#ffffff';
        ctx.fillText(lineTxt, W / 2, startY + li * lineH);
        // 关键词再用 accent 色描一遍
        var kpos = lineTxt.indexOf(keywords[kwIdx]);
        if (kpos >= 0) {
          var before = lineTxt.substring(0, kpos);
          var kWord = lineTxt.substring(kpos, kpos + keywords[kwIdx].length);
          ctx.fillStyle = accentHex;
          // 测量前面字符的宽度
          var beforeW = ctx.measureText(before).width;
          ctx.fillText(kWord, W / 2 - ctx.measureText(lineTxt).width / 2 + beforeW + ctx.measureText(kWord).width / 2,
                       startY + li * lineH);
        }
      } else {
        ctx.fillStyle = theme.title || '#ffffff';
        ctx.fillText(lineTxt, W / 2, startY + li * lineH);
      }
      ctx.shadowBlur = 0;
    }

    // 闪烁光标（打字中）
    if (isTyping && Math.sin(p.cursorBlink) > -0.3) {
      ctx.save();
      ctx.fillStyle = accentHex;
      ctx.globalAlpha = fade * 0.8;
      // 光标位置：在最后一个字右边
      var lastLine = lines[lines.length - 1];
      var cursorX = W / 2 + ctx.measureText(lastLine).width / 2 + 3;
      var cursorY = startY + (lines.length - 1) * lineH;
      var cursorLine = lines.length > 1 ? cursorY : H * 0.42;
      // 更精确：最后一行光标
      var lastIdx = lines.length - 1;
      cursorX = W / 2 + ctx.measureText(lines[lastIdx]).width / 2 + 3;
      ctx.fillRect(cursorX, cursorY - 12, 2.5, 22);
      ctx.restore();
    }

    ctx.restore();
  }

  function drawKnowledgeGroup(ctx, p, accentHex) {
    if (p.cardPopIn <= 0.01 || !p.points) return;
    var W = 854, H = 480, theme = p.theme;
    var total = p.points.length;
    var activeIdx = p.activeIdx;
    // 主卡片：当前知识点
    var mainText = p.points[activeIdx] || '';
    // 次卡片：前一个和后一个（循环）
    var prevIdx = (activeIdx - 1 + total) % total;
    var nextIdx = (activeIdx + 1) % total;
    var prevText = p.points[prevIdx] || '';
    var nextText = p.points[nextIdx] || '';

    var kscale = 0.6 + (1 - Math.pow(1 - p.cardPopIn, 3)) * 0.4;
    var kfade = p.cardPopIn;

    // Emoji 池
    var unitNo = p.unitNo || 1;
    var emojiPool = ZB_EMOJIS[unitNo] || ['💡','📚','📖','✏️'];
    var mainEmoji = emojiPool[activeIdx % emojiPool.length];
    var prevEmoji = emojiPool[prevIdx % emojiPool.length];
    var nextEmoji = emojiPool[nextIdx % emojiPool.length];

    // 网络图连线（先画连线，再画卡片）
    ctx.save();
    ctx.globalAlpha = kfade * 0.5;
    ctx.strokeStyle = accentHex;
    ctx.lineWidth = 1.5;
    ctx.setLineDash([4, 4]);
    // 位置：主卡右下、次卡左
    var mainCardX = W - 270, mainCardY = H - 125;
    var prevCardX = mainCardX - 170, prevCardY = mainCardY + 30;
    var nextCardX = mainCardX - 170, nextCardY = mainCardY - 30;
    // 画两条虚线（简化：直接连接）
    ctx.beginPath();
    ctx.moveTo(mainCardX, mainCardY + 30);
    ctx.lineTo(prevCardX + 120, prevCardY + 30);
    ctx.moveTo(mainCardX, mainCardY + 30);
    ctx.lineTo(nextCardX + 120, nextCardY + 30);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();

    // 主徽章
    var badgeW = 110, badgeH = 22, badgeX = W - 18 - badgeW, badgeY = H - 147;
    ctx.save(); ctx.globalAlpha = kfade; ctx.scale(kscale, kscale); ctx.translate(-(W - 18), -(H - 90));
    ctx.fillStyle = accentHex;
    roundRect(ctx, badgeX, badgeY, badgeW, badgeH, 6); ctx.fill();
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 11px sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(mainEmoji + ' 知识点 ' + (activeIdx + 1) + '/' + total,
                 badgeX + badgeW / 2, badgeY + badgeH / 2);
    ctx.restore();

    // 主卡片（当前知识点）— 大卡
    var mCardW = 250, mCardH = 64;
    var mCardX = W - 18 - mCardW, mCardY = H - 123;
    ctx.save(); ctx.globalAlpha = kfade; ctx.scale(kscale, kscale); ctx.translate(-(W - 18), -(H - 90));
    // 主卡阴影
    ctx.shadowColor = 'rgba(0,0,0,0.4)'; ctx.shadowBlur = 12; ctx.shadowOffsetY = 2;
    ctx.fillStyle = 'rgba(255,255,255,0.1)';
    roundRect(ctx, mCardX, mCardY, mCardW, mCardH, 10); ctx.fill();
    ctx.shadowBlur = 0; ctx.shadowOffsetY = 0;
    ctx.strokeStyle = accentHex + '88'; ctx.lineWidth = 1.5;
    roundRect(ctx, mCardX, mCardY, mCardW, mCardH, 10); ctx.stroke();

    // 主卡图标（左侧圆形 + emoji）
    var iconCX = mCardX + 24, iconCY = mCardY + mCardH / 2;
    ctx.fillStyle = accentHex + '44';
    ctx.beginPath(); ctx.arc(iconCX, iconCY, 18, 0, Math.PI * 2); ctx.fill();
    ctx.font = '22px sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(mainEmoji, iconCX, iconCY);

    // 主卡文字
    ctx.fillStyle = '#ffffff'; ctx.font = 'bold 14px sans-serif';
    ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    var mW = mCardW - 56;
    var mTxt = mainText;
    if (ctx.measureText(mTxt).width > mW) {
      while (ctx.measureText(mTxt + '…').width > mW && mTxt.length > 6) mTxt = mTxt.substring(0, mTxt.length - 1);
      mTxt = mTxt + '…';
    }
    ctx.fillText(mTxt, iconCX + 22, iconCY);
    ctx.restore();

    // 前一个（左侧小卡）
    drawSubCard(ctx, p, prevCardX, prevCardY, prevText, prevEmoji, prevIdx, 'prev', kfade, accentHex);
    // 后一个（左侧小卡，上）
    drawSubCard(ctx, p, nextCardX, nextCardY, nextText, nextEmoji, nextIdx, 'next', kfade, accentHex);
  }

  function drawSubCard(ctx, p, x, y, text, emoji, idx, dir, fade, accentHex) {
    var W = 854, H = 480;
    ctx.save();
    ctx.globalAlpha = fade * 0.7;
    ctx.fillStyle = 'rgba(255,255,255,0.06)';
    roundRect(ctx, x, y, 150, 54, 8); ctx.fill();
    ctx.strokeStyle = accentHex + '44'; ctx.lineWidth = 1;
    roundRect(ctx, x, y, 150, 54, 8); ctx.stroke();
    // Emoji
    ctx.font = '20px sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillStyle = '#ffffff';
    ctx.fillText(emoji, x + 18, y + 27);
    // 箭头标记
    ctx.fillStyle = accentHex + 'cc';
    ctx.font = 'bold 10px sans-serif';
    ctx.fillText(dir === 'prev' ? '◀ 上' : '下 ▶', x + 18, y + 8);
    // 文字
    ctx.fillStyle = '#ffffff'; ctx.font = '11px sans-serif';
    ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    var tw = text;
    if (ctx.measureText(tw).width > 115) {
      while (ctx.measureText(tw + '…').width > 115 && tw.length > 4) tw = tw.substring(0, tw.length - 1);
      tw = tw + '…';
    }
    ctx.fillText(tw, x + 40, y + 30);
    // 编号
    ctx.fillStyle = 'rgba(255,255,255,0.4)'; ctx.font = '9px monospace';
    ctx.textAlign = 'right'; ctx.textBaseline = 'top';
    ctx.fillText('#' + (idx + 1), x + 144, y + 40);
    ctx.restore();
  }

  function drawTimeline(ctx, p, mode, accentHex) {
    if (p.points.length <= 1) return;
    var W = 854, H = 480, t = p.t, theme = p.theme;
    var dotY = H - 28;
    var totalDots = p.points.length;
    var dotSpacing = Math.min(22, Math.max(12, 300 / totalDots));
    var dotStartX = W / 2 - (totalDots - 1) * dotSpacing / 2;

    // 进度线
    ctx.save(); ctx.strokeStyle = 'rgba(255,255,255,0.2)'; ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(dotStartX - dotSpacing / 2, dotY);
    ctx.lineTo(dotStartX + (totalDots - 1) * dotSpacing + dotSpacing / 2, dotY);
    ctx.stroke(); ctx.restore();

    // 已完成高亮段
    var activeX = dotStartX + p.activeIdx * dotSpacing;
    ctx.save(); ctx.strokeStyle = accentHex; ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(dotStartX - dotSpacing / 2, dotY);
    ctx.lineTo(activeX, dotY);
    ctx.stroke(); ctx.restore();

    // 点
    for (var d = 0; d < totalDots; d++) {
      var dx = dotStartX + d * dotSpacing;
      var isActive = d === p.activeIdx;
      ctx.save();
      if (isActive) {
        var breathe = 0.5 + 0.5 * Math.sin(t * 4);
        var hg = ctx.createRadialGradient(dx, dotY, 0, dx, dotY, 12 + breathe * 4);
        hg.addColorStop(0, accentHex + '88');
        hg.addColorStop(1, 'transparent');
        ctx.fillStyle = hg;
        ctx.fillRect(dx - 16, dotY - 16, 32, 32);
        ctx.fillStyle = '#ffffff';
        ctx.beginPath(); ctx.arc(dx, dotY, 4 + breathe * 1.5, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = accentHex;
        ctx.beginPath(); ctx.arc(dx, dotY, 2, 0, Math.PI * 2); ctx.fill();
      } else {
        ctx.fillStyle = 'rgba(255,255,255,' + (d < p.activeIdx ? '0.8' : '0.3') + ')';
        ctx.beginPath(); ctx.arc(dx, dotY, 2.5, 0, Math.PI * 2); ctx.fill();
      }
      ctx.restore();
    }
  }

  function drawBranding(ctx, p, mode) {
    var W = 854, H = 480, theme = p.theme;
    var accentHex = theme.accent || '#0f3460';
    ctx.save();
    var bx = 22, by = 22, bw = 118, bh = 22;
    ctx.fillStyle = 'rgba(0,0,0,0.4)';
    roundRect(ctx, bx, by, bw, bh, 4); ctx.fill();
    ctx.fillStyle = accentHex;
    ctx.font = 'bold 10px sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText('🚆 智北 · 轨道科普', bx + bw / 2, by + bh / 2);
    // TTS 状态指示
    if (mode === 0 && p.ttsOn) {
      var ttsBreathe = 0.5 + 0.5 * Math.sin(p.t * 6);
      ctx.fillStyle = 'rgba(255,215,0,' + ttsBreathe.toFixed(2) + ')';
      ctx.beginPath(); ctx.arc(bx + bw + 8, by + bh / 2, 3.5, 0, Math.PI * 2); ctx.fill();
    }
    ctx.restore();
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y,     x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x,     y + h, r);
    ctx.arcTo(x,     y + h, x,     y,     r);
    ctx.arcTo(x,     y,     x + w, y,     r);
    ctx.closePath();
  }

  // ---------- Helpers ----------
  function $(id) { return document.getElementById(id); }
  function fmtDur(sec) {
    sec = sec || 120;
    var m = Math.floor(sec / 60), s = sec % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }
  function toast(msg, type) {
    var t = document.createElement('div');
    t.className = 'rb-toast' + (type ? ' ' + type : '');
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 2200);
  }
  function getToken() {
    try { return localStorage.getItem(TOKEN_KEY); } catch (e) { return null; }
  }
  function setToken(t) {
    try { localStorage.setItem(TOKEN_KEY, t); } catch (e) {}
  }
  function clearToken() {
    try { localStorage.removeItem(TOKEN_KEY); } catch (e) {}
  }
  function parseJwt(t) {
    try {
      var parts = t.split('.');
      var payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      return payload;
    } catch (e) { return null; }
  }

  // ---------- API ----------
  async function api(path, opts) {
    opts = opts || {};
    opts.headers = opts.headers || {};
    if (state.token) opts.headers['Authorization'] = 'Bearer ' + state.token;
    if (opts.body && typeof opts.body !== 'string') {
      opts.body = JSON.stringify(opts.body);
      opts.headers['Content-Type'] = 'application/json';
    }
    var res = await fetch(API + path, opts);
    if (res.status === 401) {
      clearToken();
      state.token = null; state.user = null; state.role = null;
      updateNav();
      openAuth();
      throw new Error('login required');
    }
    var ct = res.headers.get('content-type') || '';
    var data = ct.includes('json') ? await res.json() : await res.text();
    if (!res.ok) {
      var msg = (data && data.error) || res.statusText || 'request failed';
      throw new Error(msg);
    }
    return data;
  }

  // ---------- Auth ----------
  function initAuth() {
    var t = getToken();
    if (t) {
      state.token = t;
      var p = parseJwt(t);
      if (p) { state.user = p.sub || p.user; state.role = p.role; }
      api('/rail/progress').then(function (d) {
        state.prog = d.prog;
        if (d.role) state.role = d.role;
        updateNav();
      }).catch(function () { updateNav(); });
    }
    updateNav();
  }

  function updateNav() {
    var loginBtn = $('rbLoginBtn'), logoutBtn = $('rbLogoutBtn');
    var quotaEl = $('rbQuota'), progEl = $('rbProgress');
    if (state.user) {
      if (loginBtn) { loginBtn.style.display = 'none'; }
      if (logoutBtn) {
        logoutBtn.style.display = '';
        logoutBtn.textContent = '退出 (' + state.user + ')';
      }
      if (state.prog) {
        var total = countUnlockedLessons();
        if (progEl) progEl.textContent = total;
      }
    } else {
      if (loginBtn) { loginBtn.style.display = ''; }
      if (logoutBtn) { logoutBtn.style.display = 'none'; }
      if (progEl) progEl.textContent = '0';
    }
    if (quotaEl) quotaEl.textContent = '—';
  }

  function countUnlockedLessons() {
    if (!state.catalog || !state.prog) return 0;
    if (state.role === 'admin') return 2000;
    var total = 0;
    try {
      var units = state.catalog.units || [];
      for (var i = 0; i < units.length; i++) {
        var u = units[i];
        if (u.free || (state.prog.unlocked_units || []).indexOf(u.no) !== -1) {
          total += 100; continue;
        }
        for (var j = 0; j < (u.parts || []).length; j++) {
          var p = u.parts[j];
          if ((state.prog.unlocked_parts || []).indexOf(p.id) !== -1) {
            total += 10; continue;
          }
          for (var k = 0; k < (p.lessons || []).length; k++) {
            var l = p.lessons[k];
            if ((state.prog.unlocked_lessons || []).indexOf(l.id) !== -1 || l.free) total++;
          }
        }
      }
    } catch (e) {}
    return total;
  }

  // ---------- Globals for HTML onclick ----------
  window.openRailAuth = openAuth;
  window.doRailLogin = doLogin;
  window.doRailLogout = doLogout;
  window.confirmRailBuy = confirmBuy;

  function openAuth() {
    var m = $('rbLoginModal');
    if (m) m.style.display = '';
    setTimeout(function () { var i = $('rbMPass'); if (i) i.focus(); }, 100);
  }
  function closeAuth() { var m = $('rbLoginModal'); if (m) m.style.display = 'none'; }

  async function doLogin() {
    var u = $('rbMUser').value.trim();
    var p = $('rbMPass').value;
    var err = $('rbMErr');
    if (!u || !p) { if (err) err.textContent = '请输入账号和密码'; return; }
    try {
      var data = await api('/login', {
        method: 'POST', body: { credential: u, username: u, password: p }
      });
      state.token = data.token;
      setToken(data.token);
      var pl = parseJwt(data.token);
      state.user = pl.sub; state.role = pl.role;
      closeAuth();
      toast('登录成功 · ' + data.username, 'ok');
      await loadCatalog();
      var prog = await api('/rail/progress');
      state.prog = prog.prog;
      updateNav();
      refreshCurrentView();
    } catch (e) {
      if (err) err.textContent = e.message || '登录失败';
      else toast(e.message, 'err');
    }
  }

  // ---------- Register (Enhanced v2 Multi-Step) ----------
  var regState = {
    step: 1,
    verify: 'phone',   // 'phone' | 'email'
    codeSent: false,
    codeCountdown: 0,
    passwordStrength: 0,
    faceStream: null,
    faceData: null
  };

  window.openRailRegister = openRailRegister;
  window.closeRailRegister = closeRailRegister;
  window.switchRegTab = switchRegTab;
  window.sendRegCode = sendRegCode;
  window.nextRegStep = nextRegStep;
  window.prevRegStep = prevRegStep;
  window.checkPasswordStrength = checkPasswordStrength;
  window.matchRegPasswords = matchRegPasswords;
  window.toggleFaceCapture = toggleFaceCapture;
  window.submitRegistration = submitRegistration;

  function openRailRegister() {
    // 关闭登录弹窗
    var lm = $('rbLoginModal'); if (lm) lm.style.display = 'none';
    // 打开注册弹窗
    var m = $('rbRegisterModal'); if (m) m.style.display = '';
    resetRegForm();
    regState.step = 1; regState.verify = 'phone';
    updateRegUI();
  }
  function closeRailRegister() {
    stopFaceStream();
    var m = $('rbRegisterModal'); if (m) m.style.display = 'none';
  }
  function resetRegForm() {
    ['rbRegPhone','rbRegEmail','rbRegCode','rbRegUsername','rbRegPassword',
     'rbRegPassword2','rbRegIdCard','rbRegActivation'].forEach(function(id){
      var el = $(id); if(el) el.value = '';
    });
    ['rbRegErr1','rbRegErr2','rbRegErr3','rbMockHint','rbMatchHint'].forEach(function(id){
      var el = $(id); if(el) { el.textContent = ''; el.style.display = 'none'; }
    });
    regState.codeSent = false; regState.codeCountdown = 0;
    regState.passwordStrength = 0; regState.faceData = null;
    regState.faceStream = null;
    // Reset face UI
    var vp = $('rbFaceVideo'), cv = $('rbFaceCanvas');
    if (vp) vp.style.display = 'none'; if (cv) cv.style.display = 'none';
    var ph = $('rbFacePlaceholder'), tk = $('rbFaceTaken');
    if (ph) ph.style.display = ''; if (tk) tk.style.display = 'none';
    var fb = $('rbFaceBtn'); if (fb) fb.textContent = '📷 开启摄像头';
    ['rbStrengthFill','rbStrengthLabel'].forEach(function(id){ var e=$(id); if(e){ if(e.classList){ e.classList.remove('s0','s1','s2','s3','s4'); } else { e.className=''; } e.textContent='强度检测'; e.style.width='10%'; } });
  }

  function switchRegTab(t) {
    regState.verify = t;
    var pt = $('rbTabPhone'), et = $('rbTabEmail');
    var pf = $('rbPhoneField'), ef = $('rbEmailField');
    if (t === 'phone') {
      if (pt) pt.classList.add('active'); if (et) et.classList.remove('active');
      if (pf) pf.style.display = ''; if (ef) ef.style.display = 'none';
    } else {
      if (et) et.classList.add('active'); if (pt) pt.classList.remove('active');
      if (ef) ef.style.display = ''; if (pf) pf.style.display = 'none';
    }
    regState.codeSent = false; regState.codeCountdown = 0;
    updateCodeBtn();
  }

  function updateCodeBtn() {
    var btn = $('rbSendCodeBtn'); if (!btn) return;
    if (regState.codeCountdown > 0) {
      btn.disabled = true; btn.textContent = regState.codeCountdown + 's';
    } else {
      btn.disabled = false; btn.textContent = '获取验证码';
    }
  }

  async function sendRegCode() {
    var hint = $('rbMockHint');
    try {
      var body = {};
      var ep = '';
      if (regState.verify === 'phone') {
        var p = $('rbRegPhone').value.trim();
        if (!p) { toast('请输入手机号', 'err'); return; }
        if (!/^1[3-9]\d{9}$/.test(p)) { toast('手机号格式不正确', 'err'); return; }
        body = { phone: p }; ep = '/send-sms-code';
      } else {
        var e = $('rbRegEmail').value.trim();
        if (!e) { toast('请输入邮箱', 'err'); return; }
        if (!/^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$/.test(e)) { toast('邮箱格式不正确', 'err'); return; }
        body = { email: e }; ep = '/send-email-code';
      }
      var data = await api(ep, { method: 'POST', body: body });
      // 显示 mock 验证码（MOCK 模式下）
      if (hint) {
        hint.style.display = '';
        hint.innerHTML = '💡 MOCK 模式 · 验证码是 <strong style="color:#d35400;font-size:16px">' + data.mock_code + '</strong>（5 分钟内有效）';
      }
      regState.codeSent = true;
      // 60 秒倒计时
      regState.codeCountdown = 60;
      var t = setInterval(function() {
        regState.codeCountdown--;
        updateCodeBtn();
        if (regState.codeCountdown <= 0) { clearInterval(t); }
      }, 1000);
      toast('验证码已发送', 'ok');
    } catch (err) {
      toast(err.message || '发送失败', 'err');
    }
  }

  function updateRegUI() {
    // 面板显隐
    for (var i = 1; i <= 4; i++) {
      var p = $('rbRegPanel' + i); if (p) p.style.display = (i === regState.step) ? '' : 'none';
      var s = $('rbRegStep' + i);
      if (s) {
        s.classList.remove('active','done');
        if (i < regState.step) s.classList.add('done');
        else if (i === regState.step) s.classList.add('active');
      }
    }
  }

  function nextRegStep(from) {
    // 校验当前步
    var ok = validateRegStep(from);
    if (!ok) return;
    if (regState.step < 4) { regState.step++; updateRegUI(); }
  }
  function prevRegStep(from) {
    if (regState.step > 1) { regState.step--; updateRegUI(); }
  }

  function validateRegStep(step) {
    var err = $('rbRegErr' + step); if (err) err.textContent = '';
    if (step === 1) {
      var u = $('rbRegUsername').value.trim();
      var code = $('rbRegCode').value.trim();
      if (!u || u.length < 3) { if (err) err.textContent = '用户名至少 3 字符'; return false; }
      if (u.length > 20) { if (err) err.textContent = '用户名最多 20 字符'; return false; }
      if (!code) { if (err) err.textContent = '请先获取并填写验证码'; return false; }
      if (!regState.codeSent) { toast('请先点击"获取验证码"', 'err'); return false; }
      if (regState.verify === 'phone') {
        var p = $('rbRegPhone').value.trim();
        if (!p || !/^1[3-9]\d{9}$/.test(p)) { if (err) err.textContent = '手机号格式不正确'; return false; }
      } else {
        var e = $('rbRegEmail').value.trim();
        if (!e || !/^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$/.test(e)) { if (err) err.textContent = '邮箱格式不正确'; return false; }
      }
    } else if (step === 2) {
      var pw1 = $('rbRegPassword').value;
      var pw2 = $('rbRegPassword2').value;
      if (!pw1 || pw1.length < 6) { if (err) err.textContent = '密码至少 6 位'; return false; }
      if (pw1 !== pw2) { if (err) err.textContent = '两次密码不一致'; return false; }
      var idc = $('rbRegIdCard').value.trim();
      if (idc && !/^\d{17}[\dXx]$/.test(idc)) { if (err) err.textContent = '身份证号格式不正确'; return false; }
    } else if (step === 3) {
      var ag = $('rbAgreeTerms');
      if (ag && !ag.checked) { if (err) err.textContent = '请先同意用户协议'; return false; }
    }
    return true;
  }

  function checkPasswordStrength(pw) {
    var score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (/[A-Z]/.test(pw) && /[a-z]/.test(pw)) score++;
    if (/\d/.test(pw)) score++;
    if (/[^\w\s]/.test(pw)) score++;
    score = Math.min(4, Math.max(0, score));
    regState.passwordStrength = score;
    var fill = $('rbStrengthFill'), label = $('rbStrengthLabel');
    if (fill) {
      fill.className = 'rb-strength-fill s' + score;
    }
    if (label) {
      var labels = ['极弱','弱','中等','强','极强'];
      label.textContent = labels[score];
    }
  }

  function matchRegPasswords() {
    var pw1 = $('rbRegPassword').value;
    var pw2 = $('rbRegPassword2').value;
    var hint = $('rbMatchHint');
    if (!hint) return;
    if (!pw2) { hint.className = 'rb-match-hint'; hint.textContent = ''; return; }
    if (pw1 === pw2) { hint.className = 'rb-match-hint ok'; hint.textContent = '✓ 密码一致'; }
    else { hint.className = 'rb-match-hint err'; hint.textContent = '✗ 密码不一致'; }
  }

  async function toggleFaceCapture() {
    var btn = $('rbFaceBtn'), vp = $('rbFaceVideo'), cv = $('rbFaceCanvas');
    var ph = $('rbFacePlaceholder'), tk = $('rbFaceTaken');

    if (regState.faceStream) {
      // 状态 B（视频预览中）→ 拍照存图 → 状态 C
      try {
        var ctx = cv.getContext('2d');
        cv.width = 220; cv.height = 165;
        ctx.drawImage(vp, 0, 0, 220, 165);
        regState.faceData = cv.toDataURL('image/jpeg', 0.6);
      } catch (e) {}
      stopFaceStream();
      if (vp) vp.style.display = 'none';
      if (cv) cv.style.display = '';
      if (ph) ph.style.display = 'none';
      if (tk) tk.style.display = '';
      if (btn) btn.textContent = '📷 重新采集';
      toast('人脸采集成功', 'ok');
      return;
    }
    if (regState.faceData) {
      // 状态 C（已采集）→ 清空重来 → 状态 A
      regState.faceData = null;
      if (cv) cv.style.display = 'none';
      if (tk) tk.style.display = 'none';
      if (ph) ph.style.display = '';
      if (btn) btn.textContent = '📷 开启摄像头';
      return;
    }
    // 状态 A（未采集）→ 开启摄像头 → 状态 B
    try {
      var stream = await navigator.mediaDevices.getUserMedia({ video: { width: 220, height: 165 } });
      regState.faceStream = stream;
      if (vp) { vp.srcObject = stream; vp.style.display = ''; vp.play(); }
      if (ph) ph.style.display = 'none';
      if (tk) tk.style.display = 'none';
      if (btn) btn.textContent = '📸 点击拍照确认';
    } catch (e) {
      toast('摄像头无法访问: ' + e.message, 'err');
    }
  }

  function stopFaceStream() {
    if (regState.faceStream) {
      try { regState.faceStream.getTracks().forEach(function(t) { t.stop(); }); } catch(e) {}
      regState.faceStream = null;
    }
  }

  async function submitRegistration() {
    // Step 3 校验
    if (!validateRegStep(3)) return;
    var btn = $('rbSubmitBtn'); if (btn) btn.disabled = true; btn.textContent = '注册中…';

    try {
      var body = {
        username: $('rbRegUsername').value.trim(),
        password: $('rbRegPassword').value,
        code: $('rbRegCode').value.trim(),
        verify_type: regState.verify,
        phone: (regState.verify === 'phone') ? $('rbRegPhone').value.trim() : '',
        email: (regState.verify === 'email') ? $('rbRegEmail').value.trim() : '',
        id_card: $('rbRegIdCard').value.trim(),
        face_data: regState.faceData || '',
        identity: $('rbRegIdentity').value,
        activation_code: $('rbRegActivation').value.trim()
      };
      var data = await api('/register', { method: 'POST', body: body });
      // Step 4: 成功
      regState.step = 4; updateRegUI();
      regState.codeSent = false;
      // 显示成功信息
      var msg = [];
      msg.push('🎉 欢迎加入，' + data.username + '！');
      msg.push('身份：' + (data.identity || 'other'));
      if (data.activation_applied) msg.push('✅ 激活码已生效');
      if (data.face_verified) msg.push('✅ 人脸已验证');
      $('rbSuccessMsg').innerHTML = msg.join('<br>');

      // 自动登录 + 跳转
      setTimeout(async function() {
        // 自动登录（后端已返回 token）
        state.token = data.token;
        setToken(data.token);
        var pl = parseJwt(data.token);
        state.user = pl.sub; state.role = pl.role;
        closeRailRegister();
        toast('注册成功 · 已自动登录', 'ok');
        await loadCatalog();
        var prog = await api('/rail/progress');
        state.prog = prog.prog;
        updateNav();
        refreshCurrentView();
      }, 2500);
    } catch (e) {
      console.error('=== REGISTER ERROR ===', e.message, e.stack, e);
      var err = $('rbRegErr3'); if (err) err.textContent = e.message || '注册失败';
      if (btn) { btn.disabled = false; btn.textContent = '🚀 完成注册'; }
    }
  }

  function doLogout() {
    clearToken();
    state.token = null; state.user = null; state.role = null; state.prog = null;
    updateNav();
    toast('已退出登录');
    refreshCurrentView();
  }

  // ---------- Unlock helpers ----------
  function isLessonUnlocked(lesson, part, unit) {
    if (!state.prog) return !!unit.free;
    if (state.role === 'admin') return true;
    if (unit.free || lesson.free) return true;
    if ((state.prog.unlocked_units || []).indexOf(unit.no) !== -1) return true;
    if ((state.prog.unlocked_parts || []).indexOf(part.id) !== -1) return true;
    if ((state.prog.unlocked_lessons || []).indexOf(lesson.id) !== -1) return true;
    return false;
  }
  function isPartUnlocked(part, unit) {
    if (!state.prog) return !!unit.free;
    if (state.role === 'admin') return true;
    if (unit.free) return true;
    if ((state.prog.unlocked_units || []).indexOf(unit.no) !== -1) return true;
    if ((state.prog.unlocked_parts || []).indexOf(part.id) !== -1) return true;
    return false;
  }
  function isUnitUnlocked(unit) {
    if (!state.prog) return !!unit.free;
    if (state.role === 'admin') return true;
    if (unit.free) return true;
    if ((state.prog.unlocked_units || []).indexOf(unit.no) !== -1) return true;
    return false;
  }

  // ---------- Catalog Loading ----------
  async function loadCatalog() {
    try {
      var data = await api('/rail/catalog');
      state.catalog = { meta: data.meta, units: data.units };
      if (data.prog) state.prog = data.prog;

      // 合并视频元数据（独立文件，避免大 JSON 深度解析问题）
      try {
        var vmRes = await fetch((window.__zbRuntime || '') + '/api/rail/video-meta');
        if (vmRes.ok) {
          var videoMeta = await vmRes.json();
          // videoMeta 是 { lesson_id: { ...meta } }
          var catalog = state.catalog || {};
          for (var ui = 0; ui < (catalog.units || []).length; ui++) {
            var unit = catalog.units[ui];
            for (var pi = 0; pi < (unit.parts || []).length; pi++) {
              var part = unit.parts[pi];
              for (var li = 0; li < (part.lessons || []).length; li++) {
                var lesson = part.lessons[li];
                if (videoMeta[lesson.id]) {
                  lesson.video_meta = videoMeta[lesson.id];
                }
              }
            }
          }
        }
      } catch (e) {
        // video_meta 加载失败不影响核心功能
        console.warn('video-meta load failed, videos disabled');
      }

      updateNav();
    } catch (e) {
      console.warn('loadCatalog failed', e.message);
    }
  }

  // ---------- Router ----------
  function boot() {
    $('rbLoader').style.display = 'none';
    $('rbApp').style.display = '';
    initAuth();
    loadCatalog().then(function () { renderHome(); });
  }

  function refreshCurrentView() {
    if (state.view === 'home') renderHome();
    else if (state.view === 'unit') renderUnit(state.viewParam);
    else if (state.view === 'lesson') renderLesson(state.viewParam);
  }

  function goHome() { state.view = 'home'; state.viewParam = null; state.openParts = {}; renderHome(); }
  function goUnit(no) { state.view = 'unit'; state.viewParam = no; state.openParts = {}; renderUnit(no); }
  function goLesson(lid) { state.view = 'lesson'; state.viewParam = lid; renderLesson(lid); }

  // ---------- Render: Home ----------
  function renderHome() {
    var main = $('rbMain');
    var c = state.catalog;
    if (!c) { main.innerHTML = '<div class="rb-empty"><div class="rb-e-emoji">⏳</div>课程库加载中…</div>'; return; }

    var html =
      '<div class="rb-hero">' +
        '<h1>🚆 智北轨道科普学院</h1>' +
        '<p>20 个单元 · 200 个部分 · 2000 条小结视频，系统学习轨道交通全链路知识。从地铁到高铁，从信号到牵引，从制造到运营。</p>' +
        '<div class="rb-hero-meta">' +
          '<div class="rb-meta-item">📚 20 单元全体系</div>' +
          '<div class="rb-meta-item">🎬 2000 条视频</div>' +
          '<div class="rb-meta-item">💰 ¥1/小结 · ¥9/部分 · ¥89/单元</div>' +
          '<div class="rb-meta-item">🎁 第 1 单元全部免费</div>' +
        '</div>' +
      '</div>' +
      '<div class="rb-section-title">全部课程目录</div>' +
      '<div class="rb-unit-grid">';

    for (var i = 0; i < c.units.length; i++) {
      var u = c.units[i];
      var unlocked = isUnitUnlocked(u);
      var badgeHtml = u.free
        ? '<span class="rb-badge rb-badge-free">🚆 全部免费</span>'
        : (unlocked
            ? '<span class="rb-badge rb-badge-unlocked">✅ 已解锁</span>'
            : '<span class="rb-badge rb-badge-paid">¥89/单元</span>');
      var cardClass = 'rb-unit-card' + (u.free ? ' free' : '');
      html +=
        '<div class="' + cardClass + '" onclick="window.__goUnit(' + u.no + ')">' +
          '<div class="rb-uc-head">' +
            '<span class="rb-uc-no">UNIT ' + u.no + '</span>' +
            '<span class="rb-uc-icon">' + u.icon + '</span>' +
          '</div>' +
          '<div class="rb-uc-name">' + u.name + '</div>' +
          '<div class="rb-uc-meta">10 部分 × 10 小结 · 共 100 讲</div>' +
          badgeHtml +
        '</div>';
    }
    html += '</div>';
    main.innerHTML = html;

    // register global
    window.__goUnit = goUnit;
  }

  // ---------- Render: Unit Detail ----------
  function renderUnit(no) {
    var main = $('rbMain');
    var c = state.catalog;
    var u = null;
    for (var i = 0; i < (c.units || []).length; i++) {
      if (c.units[i].no === no) { u = c.units[i]; break; }
    }
    if (!u) { main.innerHTML = '<div class="rb-empty">单元不存在</div>'; return; }

    var unitUnlocked = isUnitUnlocked(u);

    var html =
      '<div class="rb-unit-header">' +
        '<a class="rb-back" onclick="window.__goHome()">← 返回课程目录</a>' +
        '<h2>' + u.icon + ' 第 ' + u.no + ' 单元 · ' + u.name +
          (u.free ? ' <span class="rb-badge rb-badge-free">🚆 全部免费</span>' : '') +
          (unitUnlocked && !u.free ? ' <span class="rb-badge rb-badge-unlocked">✅ 已解锁</span>' : '') +
        '</h2>' +
        '<div class="rb-meta-line">' +
          '<span>📚 ' + u.parts.length + ' 部分</span>' +
          '<span>🎬 ' + (u.total_lessons || u.parts.length * 10) + ' 条小结</span>' +
          (u.free ? '<span>🎁 全部免费试看</span>' : '<span>💰 ¥89 解锁本单元</span>') +
        '</div>' +
      '</div>' +
      '<div class="rb-part-list">';

    for (var p = 0; p < (u.parts || []).length; p++) {
      var part = u.parts[p];
      var partUnlocked = isPartUnlocked(part, u);
      var open = !!state.openParts[part.id];

      html +=
        '<div class="rb-part-row' + (open ? ' open' : '') + '" data-pid="' + part.id + '">' +
          '<div class="rb-part-head" onclick="window.__togglePart(\'' + part.id + '\')">' +
            '<span class="rb-p-icon">' + part.icon + '</span>' +
            '<div class="rb-p-info">' +
              '<div class="rb-p-no">第 ' + u.no + '.' + part.no + ' 部分</div>' +
              '<div class="rb-p-name">' + part.name + '</div>' +
            '</div>' +
            '<div class="rb-p-right">' +
              (u.free || partUnlocked
                ? '<span class="rb-badge rb-badge-unlocked">✅</span>'
                : '<span class="rb-badge rb-badge-locked">🔒 ¥9</span>') +
              '<span class="rb-p-chev">▶</span>' +
            '</div>' +
          '</div>' +
          '<div class="rb-part-body">';

      for (var l = 0; l < (part.lessons || []).length; l++) {
        var lesson = part.lessons[l];
        var lessonUnlocked = isLessonUnlocked(lesson, part, u);
        var locked = !lessonUnlocked;
        var rowClass = 'rb-lesson-row ' +
          (locked && !u.free && !lesson.free && !partUnlocked && !unitUnlocked ? 'locked-l' :
           (lessonUnlocked ? 'unlocked-l' : (u.free || lesson.free ? 'free-l' : '')));
        var badge = '';
        if (u.free || lesson.free) badge = '<span class="rb-l-badge" style="background:#E8FFEA;color:#00B42A">免费</span>';
        else if (lessonUnlocked) badge = '<span class="rb-l-badge" style="background:#E8F3FF;color:#165DFF">已解锁</span>';
        else badge = '<span class="rb-l-badge" style="background:#FFF1E8;color:#FF7D00">¥1</span>';

        html +=
          '<div class="' + rowClass + '" onclick="window.__goLesson(\'' + lesson.id + '\')">' +
            '<span class="rb-l-no">L' + lesson.no + '</span>' +
            '<span class="rb-l-icon">' + (locked && !u.free && !lesson.free ? '🔒' : '▶') + '</span>' +
            '<span class="rb-l-title">' + lesson.title + '</span>' +
            '<span class="rb-l-duration">' + fmtDur(lesson.duration) + '</span>' +
            badge +
          '</div>';
      }

      html += '</div></div>';
    }
    html += '</div>';
    main.innerHTML = html;

    window.__goHome = goHome;
    window.__goLesson = goLesson;
    window.__togglePart = function (pid) {
      state.openParts[pid] = !state.openParts[pid];
      renderUnit(no);
    };
  }

  // ---------- Render: Lesson ----------
  async function renderLesson(lid) {
    var main = $('rbMain');
    main.innerHTML = '<div class="rb-empty"><div class="rb-e-emoji">⏳</div>加载中…</div>';

    try {
      var data = await api('/rail/lesson/' + lid);
      var lesson = data.lesson, unitNo = data.unit, unitName = data.unit_name,
          partNo = data.part, partName = data.part_name,
          unlocked = data.unlocked, isFreeLesson = data.is_free, unitFree = data.unit_free;

      // 后端 lesson API 直接返回顶层 video_meta，挂到 lesson 对象上
      if (data.video_meta) {
        lesson.video_meta = data.video_meta;
      }

      // 从 catalog 找到 unit/part 用于侧边栏
      var unit = null, part = null;
      var c = state.catalog || {};
      for (var i = 0; i < (c.units || []).length; i++) {
        if (c.units[i].no === unitNo) {
          unit = c.units[i];
          for (var j = 0; j < (unit.parts || []).length; j++) {
            if (unit.parts[j].id === 'u' + unitNo + 'p' + partNo) { part = unit.parts[j]; break; }
          }
          break;
        }
      }

      var canAccess = unlocked || state.role === 'admin';
      var headerBadge = unitFree
        ? '<span class="rb-badge rb-badge-free">🚆 免费单元</span>'
        : (isFreeLesson ? '<span class="rb-badge rb-badge-free">🎁 免费试看</span>'
          : (unlocked ? '<span class="rb-badge rb-badge-unlocked">✅ 已解锁</span>'
            : '<span class="rb-badge rb-badge-paid">🔒 未解锁</span>'));

      // ========== Canvas 视频播放器 ==========
      var videoSection;
      if (canAccess) {
        var vm = lesson.video_meta || {};
        var vid = lesson.id;
        var duration = vm.duration || lesson.duration || 90;
        var isStatic = vm.video_mode === 'static'; // U1 质量差的 static 模式
        videoSection =
          '<div class="rb-video-wrap">' +
            '<div class="rb-video-player" id="rbvp_' + vid + '" style="position:relative;width:100%;aspect-ratio:16/9;border-radius:10px;overflow:hidden;background:' + (vm.theme && vm.theme.bg_from ? vm.theme.bg_from : '#1a1a2e') + ';">' +
              '<canvas class="rbvp-canvas" width="854" height="480" style="display:block;width:100%;height:100%;"></canvas>' +
              // 控制条
              '<div class="rbvp-controls" style="position:absolute;bottom:0;left:0;right:0;padding:8px 12px;background:linear-gradient(transparent,rgba(0,0,0,.75));display:flex;align-items:center;gap:10px;">' +
                '<button class="rbvp-play" onclick="window.__vpToggle(\'' + vid + '\')" style="width:36px;height:36px;border-radius:50%;border:none;background:rgba(255,255,255,.12);color:white;cursor:pointer;font-size:16px;">▶</button>' +
                '<div style="font-size:12px;color:#e0e0e0;font-family:monospace;min-width:42px;" id="rbvp_cur_' + vid + '">00:00</div>' +
                '<div class="rbvp-progress" style="flex:1;height:4px;background:rgba(255,255,255,.2);border-radius:2px;cursor:pointer;" onclick="window.__vpSeek(\'' + vid + '\',event)">' +
                  '<div class="rbvp-bar" style="width:0%;height:100%;background:#fff;border-radius:2px;"></div>' +
                '</div>' +
                '<div style="font-size:12px;color:#e0e0e0;font-family:monospace;min-width:42px;">' + fmtDur(duration) + '</div>' +
                '<button onclick="window.__vpReplay(\'' + vid + '\')" style="width:28px;height:28px;border:none;background:rgba(255,255,255,.12);color:white;border-radius:4px;cursor:pointer;font-size:14px;" title="重播">🔄</button>' +
              '</div>' +
              // 标题栏
              '<div style="position:absolute;top:0;left:0;right:0;padding:10px 14px;background:linear-gradient(rgba(0,0,0,.6),transparent);display:flex;align-items:center;gap:10px;">' +
                '<div style="font-size:20px;">' + (vm.icon || '🚆') + '</div>' +
                '<div style="flex:1;color:white;font-size:13px;font-weight:600;text-shadow:0 1px 3px rgba(0,0,0,.6);">' +
                  '第 ' + (vm.unit_no || unitNo) + ' 单元 · ' + (vm.unit_name || unitName) +
                  ' <span style="color:#999;font-weight:400;">| ' + lesson.title + '</span>' +
                '</div>' +
                '<div style="font-size:11px;padding:2px 8px;background:rgba(255,255,255,.15);border-radius:10px;color:#ddd;">' + (isStatic ? '简易画面' : '动态画面') + '</div>' +
              '</div>' +
            '</div>' +
          '</div>';
      } else {
        videoSection =
          '<div class="rb-video-wrap">' +
            '<div class="rb-paid-wall">' +
              '<div class="rb-pw-lock">🔒</div>' +
              '<h3>此小结需要解锁</h3>' +
              '<p>「' + lesson.title + '」</p>' +
              '<div class="rb-pw-btns">' +
                '<button class="rb-btn-success" onclick="window.__buyLesson(\'' + lesson.id + '\')">¥1 解锁此小结</button>' +
                (!unitFree && unit ?
                  '<button class="rb-btn-secondary" onclick="window.__buyUnit(' + unit.no + ')">¥89 解锁全单元</button>' : '') +
              '</div>' +
            '</div>' +
          '</div>';
      }

      // 文档（未解锁时也显示文档前几段作为 teaser）
      var docHtml = canAccess
        ? renderMd(lesson.doc_markdown || '')
        : '<div style="color:var(--text-3);font-size:13px">' +
            '<p>🔒 解锁后可阅读完整配套文档。</p>' +
            '<p style="margin-top:10px;opacity:.6">' + truncateMd(lesson.doc_markdown || '', 200) + '</p>' +
          '</div>';

      // 侧边栏：同单元其他小结
      var sideHtml = '';
      if (part && part.lessons) {
        sideHtml += '<div class="rb-side-card"><h4>📖 本部分其他小结</h4><ul class="rb-side-list">';
        for (var k = 0; k < part.lessons.length; k++) {
          var ll = part.lessons[k];
          var llUnlocked = isLessonUnlocked(ll, part, unit || {});
          var cls = ll.id === lid ? 'current' : '';
          var mark = llUnlocked || unitFree || isFreeLesson ? '' : ' 🔒';
          sideHtml += '<li class="' + cls + '" onclick="window.__goLesson(\'' + ll.id + '\')">' +
            'L' + ll.no + ' · ' + ll.title + mark + '</li>';
        }
        sideHtml += '</ul></div>';
      }
      // 侧边栏：价格参考 + 快速解锁
      if (!canAccess) {
        sideHtml +=
          '<div class="rb-buy-box">' +
            '<div style="font-size:13px;color:var(--text-2)">解锁价格</div>' +
            '<div class="rb-bb-price">¥1</div>' +
            '<div class="rb-bb-desc">单条小结 · 约 ' + fmtDur(lesson.duration) + ' 视频 + 完整文档</div>' +
            '<button class="rb-btn-primary rb-btn-lg" onclick="window.__buyLesson(\'' + lesson.id + '\')">立即解锁</button>' +
            (part ? '<div style="margin-top:10px;font-size:12px;color:var(--text-3)">或 <a onclick="window.__buyPart(\'' + part.id + '\')" style="color:var(--warn);cursor:pointer;font-weight:600">¥9 解锁本部分 10 条</a></div>' : '') +
            (unit && !unitFree ? '<div style="margin-top:4px;font-size:12px;color:var(--text-3)">或 <a onclick="window.__buyUnit(' + unit.no + ')" style="color:var(--warn);cursor:pointer;font-weight:600">¥89 解锁全单元 100 条</a></div>' : '') +
          '</div>';
      }

      main.innerHTML =
        '<div class="rb-lesson-view">' +
          '<div class="rb-lesson-main">' +
            videoSection +
            '<div class="rb-lesson-info">' +
              '<div class="rb-li-crumbs">' +
                '<a onclick="window.__goHome()" style="color:var(--text-3);cursor:pointer">轨道科普</a> / ' +
                '<a onclick="window.__goUnit(' + unitNo + ')" style="color:var(--text-3);cursor:pointer">第 ' + unitNo + ' 单元 · ' + unitName + '</a> / ' +
                '第 ' + unitNo + '.' + partNo + ' 部分' +
              '</div>' +
              '<h2>' + lesson.title + ' ' + headerBadge + '</h2>' +
              '<div class="rb-li-meta">' +
                '<span>▶ 约 ' + fmtDur(lesson.duration) + '</span>' +
                '<span>📚 第 ' + unitNo + '.' + partNo + '.' + lesson.no + ' 讲</span>' +
              '</div>' +
            '</div>' +
            '<div class="rb-doc-section"><h4>📝 配套学习文档</h4>' +
              '<div class="rb-doc-md">' + docHtml + '</div>' +
            '</div>' +
          '</div>' +
          '<div class="rb-lesson-side">' + sideHtml + '</div>' +
        '</div>';

      window.__buyLesson = buyLesson;
      window.__buyPart = buyPart;
      window.__buyUnit = buyUnit;
      window.__goHome = goHome;
      window.__goUnit = goUnit;
      window.__goLesson = goLesson;

      // 初始化 Canvas 视频播放器
      if (canAccess && lesson.video_meta) {
        setTimeout(function() { initCanvasPlayer(vid, lesson.video_meta); }, 50);
      }

    } catch (e) {
      main.innerHTML = '<div class="rb-empty"><div class="rb-e-emoji">❌</div>加载失败：' +
        (e.message || e) + '<div style="margin-top:10px"><button class="rb-btn-secondary" onclick="location.reload()">重试</button></div></div>';
      toast(e.message || '加载失败', 'err');
    }
  }

  // ---------- Simple Markdown Renderer ----------
  function renderMd(md) {
    if (!md) return '';
    var html = md;
    // Convert headings
    html = html.replace(/^### (.+)$/gm, '<h4 style="font-size:16px;color:#1D2129;margin:20px 0 10px;font-weight:700">$1</h4>');
    html = html.replace(/^#### (.+)$/gm, '<h4>$1</h4>');
    // Bold
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    // Convert ordered lists (lines starting with "1. " or "- ")
    html = html.replace(/^\d+\.\s+(.+)$/gm, '<li>$1</li>');
    html = html.replace(/^-\s+(.+)$/gm, '<li>$1</li>');
    // Wrap consecutive <li> in <ol> or <ul>
    html = html.replace(/((?:<li>.*?<\/li>\n?)+)/g, function (m) {
      return '<ul style="padding-left:20px;margin:8px 0">' + m + '</ul>';
    });
    // Paragraphs (remaining non-empty lines)
    html = html.split('\n').map(function (line) {
      line = line.trim();
      if (!line) return '';
      if (line.startsWith('<')) return line;
      return '<p>' + line + '</p>';
    }).join('');
    return html;
  }

  function truncateMd(md, max) {
    if (!md) return '';
    var plain = md.replace(/[#*]/g, '').replace(/\n/g, ' ');
    return plain.length > max ? plain.substring(0, max) + '…' : plain;
  }

  // ---------- Purchase Flow ----------
  var pendingBuy = null; // { kind: 'unit'|'part'|'lesson', id, title, price }
  var payCtx = null;     // { payMethods, zbBalance, orderId, pollTimer, payeeBank }

  function buyLesson(lid) {
    pendingBuy = { kind: 'lesson', id: lid, title: '单条小结', price: 1 };
    showBuyModal();
  }
  function buyPart(pid) {
    pendingBuy = { kind: 'part', id: pid, title: '整个部分（10 条小结）', price: 9 };
    showBuyModal();
  }
  function buyUnit(no) {
    pendingBuy = { kind: 'unit', id: no, title: '整个单元（100 条小结）', price: 89 };
    showBuyModal();
  }

  function showBuyModal() {
    if (!state.user) { toast('请先登录', 'err'); openAuth(); return; }
    if (state.role === 'admin') { toast('admin 账号已全部解锁', 'ok'); return; }

    payCtx = { payMethods: [], zbBalance: 0, orderId: null, pollTimer: null, selectedMethod: null };

    var body = $('rbBuyBody');
    var itemLabel = { unit: '整个单元', part: '单个部分', lesson: '单条小结' };
    body.innerHTML =
      '<div class="rb-buy-item" style="flex-direction:column;align-items:stretch;margin-bottom:14px;">' +
        '<div style="font-size:15px;font-weight:700;color:#1D2129;margin-bottom:6px;">' + pendingBuy.title + '</div>' +
        '<div style="font-size:13px;color:#86909C;">' + itemLabel[pendingBuy.kind] + ' · 永久解锁</div>' +
        '<div style="margin-top:8px;font-size:20px;font-weight:800;color:#F53F3F;">¥' + pendingBuy.price + '</div>' +
      '</div>' +

      // Tab 切换
      '<div style="display:flex;background:#F2F3F5;border-radius:8px;padding:4px;margin-bottom:14px;">' +
        '<button class="rb-tab-btn rb-tab-active" data-tab="code" onclick="switchBuyTab(\'code\')" id="rbTabCode" style="flex:1;padding:10px;border:none;border-radius:6px;font-size:13px;font-weight:600;cursor:pointer;background:white;color:#1D2129;box-shadow:0 1px 2px rgba(0,0,0,0.05);">🔑 激活码</button>' +
        '<button class="rb-tab-btn" data-tab="pay" onclick="switchBuyTab(\'pay\')" id="rbTabPay" style="flex:1;padding:10px;border:none;border-radius:6px;font-size:13px;font-weight:600;cursor:pointer;background:transparent;color:#4E5969;">💳 在线支付</button>' +
      '</div>' +

      // 激活码 Tab
      '<div id="rbTabPaneCode">' +
        '<label style="display:block;font-size:13px;font-weight:600;color:#1D2129;margin-bottom:8px;">输入激活码</label>' +
        '<input id="rbCodeInput" type="text" placeholder="ZB-XXXXXXXXXXXX" style="width:100%;padding:12px 16px;font-size:15px;background:#F2F3F5;border:1px solid #E5E6EB;border-radius:8px;font-family:monospace;outline:none;">' +
        '<div style="margin-top:8px;font-size:12px;color:#86909C;">输入 admin 发放的激活码（不区分大小写，分隔符可选）</div>' +
      '</div>' +

      // 在线支付 Tab（初始隐藏，加载中）
      '<div id="rbTabPanePay" style="display:none;">' +
        '<div id="rbPayLoading" style="text-align:center;padding:20px;color:#86909C;font-size:13px;">加载支付方式中…</div>' +
        '<div id="rbPayContent" style="display:none;"></div>' +
      '</div>';

    $('rbBuyModal').style.display = '';
    $('rbBuyBtn').textContent = '确认解锁';
    $('rbBuyBtn').onclick = confirmBuy;
    setTimeout(function(){ var inp = $('rbCodeInput'); if(inp) inp.focus(); }, 100);

    // 加载支付方式 + ZBpay 充值档位（并行）
    Promise.all([
      api('/rail/pay-methods'),
      api('/pay/pricing')
    ]).then(function(results) {
      var d = results[0];
      var pr = results[1];
      payCtx.payMethods = d.methods || [];
      payCtx.zbBalance = d.zbpay_balance || 0;
      payCtx.payeeBank = d.payee_bank || null;
      payCtx.depositPlans = pr.zbpay_deposit_plans || [];
      payCtx.depositReady = true;
      renderPayTab();
    }).catch(function() {
      payCtx.depositReady = true;
      renderPayTab();
    });
  }

  // 切换 Tab（全局函数供 onclick 调用）
  window.switchBuyTab = function(tab) {
    var codeBtn = $('rbTabCode'), payBtn = $('rbTabPay');
    var codePane = $('rbTabPaneCode'), payPane = $('rbTabPanePay');
    if (tab === 'code') {
      codeBtn.className = 'rb-tab-btn rb-tab-active';
      codeBtn.style.background = 'white'; codeBtn.style.color = '#1D2129'; codeBtn.style.boxShadow = '0 1px 2px rgba(0,0,0,0.05)';
      payBtn.className = 'rb-tab-btn';
      payBtn.style.background = 'transparent'; payBtn.style.color = '#4E5969'; payBtn.style.boxShadow = 'none';
      codePane.style.display = ''; payPane.style.display = 'none';
      $('rbBuyBtn').style.display = '';
      $('rbBuyBtn').textContent = '确认解锁';
      $('rbBuyBtn').onclick = confirmBuy;
      // 停止支付轮询
      if (payCtx && payCtx.pollTimer) { clearTimeout(payCtx.pollTimer); payCtx.pollTimer = null; }
    } else {
      payBtn.className = 'rb-tab-btn rb-tab-active';
      payBtn.style.background = 'white'; payBtn.style.color = '#1D2129'; payBtn.style.boxShadow = '0 1px 2px rgba(0,0,0,0.05)';
      codeBtn.className = 'rb-tab-btn';
      codeBtn.style.background = 'transparent'; codeBtn.style.color = '#4E5969'; codeBtn.style.boxShadow = 'none';
      codePane.style.display = 'none'; payPane.style.display = '';
      $('rbBuyBtn').style.display = 'none'; // 支付 Tab 隐藏通用按钮
    }
  };

  function renderPayTab() {
    var loading = $('rbPayLoading');
    var content = $('rbPayContent');
    if (!loading) return;
    loading.style.display = 'none';
    content.style.display = '';

    var items = payCtx.payMethods.map(function(m) {
      var zbTag = m.zbdeposit ? '<span style="margin-left:4px;font-size:10px;padding:1px 5px;background:#F2F3F5;color:#86909C;border-radius:3px;">ZB充值</span>' : '';
      return '<div class="rb-pay-method" data-id="' + m.id + '" onclick="selectPayMethod(\'' + m.id + '\')" style="display:flex;align-items:center;padding:12px;border:1px solid #E5E6EB;border-radius:10px;cursor:pointer;margin-bottom:8px;transition:all 0.15s;">' +
        '<div style="font-size:22px;margin-right:12px;">' + m.icon + '</div>' +
        '<div style="flex:1;">' +
          '<div style="font-size:14px;font-weight:600;color:#1D2129;">' + m.label + zbTag + '</div>' +
          '<div style="font-size:11px;color:#86909C;margin-top:2px;">' + m.desc + '</div>' +
        '</div>' +
        '<div class="rb-pay-radio" style="width:18px;height:18px;border:2px solid #C9CDD4;border-radius:50%;"></div>' +
      '</div>';
    }).join('');

    var zbTip = '';
    var plans = payCtx.depositPlans || [];
    var planHtml = plans.map(function(p) {
      var bonus = p.bonus > 0 ? '<span style="margin-left:4px;font-size:10px;color:#F53F3F;font-weight:600;">+' + p.bonus + '</span>' : '';
      return '<button onclick="depositZbpay(' + p.amount + ')" style="flex:1;padding:10px 6px;background:white;border:1px solid #E5E6EB;border-radius:8px;cursor:pointer;font-size:12px;font-weight:600;color:#1D2129;min-width:60px;">' +
        '¥' + p.amount + bonus +
      '</button>';
    }).join('');
    zbTip =
      '<div style="margin-top:12px;padding:12px;background:linear-gradient(135deg,#F2F7FF,#EBF5FF);border:1px solid #C9D6FF;border-radius:10px;">' +
        '<div style="font-size:12px;font-weight:700;color:#165DFF;margin-bottom:6px;">🟣 ZBpay 余额</div>' +
        '<div style="font-size:22px;font-weight:800;color:#1D2129;margin-bottom:8px;">¥' + payCtx.zbBalance.toFixed(2) + '</div>' +
        (plans.length ?
          '<div style="font-size:11px;color:#86909C;margin-bottom:6px;">快速充值（点击即到账）</div>' +
          '<div style="display:flex;gap:6px;flex-wrap:wrap;">' + planHtml + '</div>'
          : '<div style="font-size:11px;color:#86909C;">充值档位加载中…</div>'
        ) +
      '</div>';

    var payeeHtml = '';
    if (payCtx.payeeBank) {
      var pb = payCtx.payeeBank;
      var maskedNo = pb.account_no || '**** **** **** ****';
      payeeHtml =
        '<div style="margin-top:14px;padding:12px;background:linear-gradient(135deg,#FFF7E6,#FFFBF5);border:1px solid #FFDAB9;border-radius:10px;">' +
          '<div style="font-size:12px;font-weight:700;color:#D46B08;margin-bottom:8px;">🏦 统一收款账户</div>' +
          '<div style="font-size:13px;color:#1D2129;margin-bottom:4px;"><b>' + pb.account_name + '</b>（' + pb.bank_name + '）</div>' +
          '<div id="railBankNo1" style="font-family:monospace;font-size:16px;font-weight:800;color:#F53F3F;letter-spacing:1px;user-select:none;">' + maskedNo + '</div>' +
          '<div style="margin-top:4px;display:flex;align-items:center;gap:8px;">' +
            '<button onclick="revealBankCard(\'railBankNo1\')" style="font-size:11px;padding:3px 10px;background:rgba(0,0,0,0.05);border:1px solid rgba(0,0,0,0.1);border-radius:100px;cursor:pointer;color:#4E5969;">👁 查看完整卡号</button>' +
            '<button onclick="copyBankCard()" style="font-size:11px;padding:3px 10px;background:rgba(0,0,0,0.05);border:1px solid rgba(0,0,0,0.1);border-radius:100px;cursor:pointer;color:#4E5969;">📋 复制掩码</button>' +
          '</div>' +
          '<div style="margin-top:6px;font-size:11px;color:#86909C;">所有方式收款至此卡，请在付款备注中注明订单号</div>' +
        '</div>';
    }

    content.innerHTML =
      '<div style="font-size:13px;font-weight:600;color:#1D2129;margin-bottom:10px;">💳 选择支付方式</div>' +
      items + zbTip + payeeHtml +
      '<div id="rbPaySelectedArea" style="margin-top:14px;"></div>';
  }

  window.selectPayMethod = function(id) {
    payCtx.selectedMethod = id;
    // 视觉高亮
    document.querySelectorAll('.rb-pay-method').forEach(function(el) {
      if (el.getAttribute('data-id') === id) {
        el.style.borderColor = '#165DFF';
        el.style.background = '#F2F7FF';
        var radio = el.querySelector('.rb-pay-radio');
        if (radio) { radio.style.borderColor = '#165DFF'; radio.style.background = '#165DFF'; }
      } else {
        el.style.borderColor = '#E5E6EB';
        el.style.background = '';
        var radio = el.querySelector('.rb-pay-radio');
        if (radio) { radio.style.borderColor = '#C9CDD4'; radio.style.background = ''; }
      }
    });
    // 显示确认按钮
    var area = $('rbPaySelectedArea');
    var methodMeta = payCtx.payMethods.find(function(m){ return m.id === id; });
    if (id === 'zbpay') {
      var canPay = payCtx.zbBalance >= pendingBuy.price;
      area.innerHTML =
        '<div style="font-size:12px;color:#4E5969;margin-bottom:10px;">' +
          (canPay ? '余额充足，可直接支付' : '余额不足，请先充值') +
        '</div>' +
        '<button id="rbPayConfirmBtn" onclick="doZbpay()" ' + (canPay ? '' : 'disabled') +
          ' style="width:100%;padding:12px;background:' + (canPay ? '#165DFF' : '#C9CDD4') + ';color:white;border:none;border-radius:8px;font-size:14px;font-weight:600;cursor:' + (canPay ? 'pointer' : 'not-allowed') + ';">' +
          (canPay ? '🟣 用 ZBpay 余额 ¥' + pendingBuy.price + ' 支付' : '充值后支付') +
        '</button>';
    } else {
      area.innerHTML =
        '<button id="rbPayConfirmBtn" onclick="createRailOrder()" style="width:100%;padding:12px;background:#165DFF;color:white;border:none;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer;">' +
          methodMeta.label + ' ¥' + pendingBuy.price + ' 立即支付 →' +
        '</button>';
    }
  };

  // 给 ZBpay 充值（mock 模式，方便测试）
  window.depositZbpay = function(amount) {
    api('/rail/deposit', { method: 'POST', body: { amount: amount, channel: 'bank' } }).then(function(d) {
      payCtx.zbBalance = d.balance;
      toast('✅ 充值成功 ¥' + amount + '，当前余额 ¥' + d.balance.toFixed(2), 'ok');
      renderPayTab();
      if (payCtx.selectedMethod) { selectPayMethod(payCtx.selectedMethod); }
    }).catch(function(e) { toast('❌ 充值失败：' + e.message, 'err'); });
  };

  // ZBpay 余额支付（后端直接完成订单 + 解锁）
  window.doZbpay = function() {
    var btn = $('rbPayConfirmBtn'); if (btn) { btn.disabled = true; btn.textContent = '支付中…'; }
    api('/rail/orders', {
      method: 'POST',
      body: { kind: pendingBuy.kind, target_id: 'u' + pendingBuy.id, pay_method: 'zbpay' }
    }).then(function(d) {
      // 成功即已解锁
      return finalizeRailPay(d, 'zbpay');
    }).catch(function(e) {
      toast('❌ ' + e.message, 'err');
      if (btn) { btn.disabled = false; btn.textContent = '🟣 用 ZBpay 余额支付'; }
    });
  };

  // 非 ZBpay 方式：先创建订单，再展示 checkout 信息
  window.createRailOrder = function() {
    var btn = $('rbPayConfirmBtn'); if (btn) { btn.disabled = true; btn.textContent = '创建订单中…'; }
    api('/rail/orders', {
      method: 'POST',
      body: { kind: pendingBuy.kind, target_id: 'u' + pendingBuy.id, pay_method: payCtx.selectedMethod }
    }).then(function(d) {
      payCtx.orderId = d.order_id;
      showCheckoutUI(d);
    }).catch(function(e) {
      toast('❌ ' + e.message, 'err');
      if (btn) { btn.disabled = false; btn.textContent = '立即支付'; }
    });
  };

  function showCheckoutUI(d) {
    var area = $('rbPaySelectedArea');
    var info = d.checkout_info || {};
    var method = info.method || payCtx.selectedMethod;

    // 样式：根据支付方式
    var brandColor = '#1D2129';
    var brandName = '支付';
    var brandIcon = '💳';
    if (method === 'alipay') { brandColor = '#1677FF'; brandName = '支付宝扫码'; brandIcon = '💙'; }
    else if (method === 'wechat') { brandColor = '#07C160'; brandName = '微信扫码'; brandIcon = '💚'; }
    else if (method === 'bank') { brandColor = '#F53F3F'; brandName = '银行卡转账'; brandIcon = '🏦'; }

    // 倒计时
    var expireTs = null;
    if (info.expires_at) { expireTs = new Date(info.expires_at).getTime(); }

    var qrHtml = '';
    if (info.qr_url) {
      // 微信/支付宝带 logo 角标
      var qrBadge = '';
      if (method === 'alipay') { qrBadge = '<div style="position:absolute;bottom:-8px;left:50%;transform:translateX(-50%);background:#1677FF;color:white;font-size:10px;padding:2px 10px;border-radius:10px;">支付宝</div>'; }
      else if (method === 'wechat') { qrBadge = '<div style="position:absolute;bottom:-8px;left:50%;transform:translateX(-50%);background:#07C160;color:white;font-size:10px;padding:2px 10px;border-radius:10px;">微信</div>'; }
      qrHtml =
        '<div style="text-align:center;margin:14px 0;position:relative;padding-bottom:18px;">' +
          '<div style="display:inline-block;padding:12px;background:white;border:2px solid ' + brandColor + ';border-radius:12px;box-shadow:0 4px 20px rgba(0,0,0,0.08);">' +
            '<img src="' + info.qr_url + '" style="width:170px;height:170px;display:block;">' +
          '</div>' +
          qrBadge +
          '<div style="font-size:11px;color:#86909C;margin-top:10px;">订单号 <span style="font-family:monospace;color:#1D2129;">' + d.order_id + '</span></div>' +
          '<div style="font-size:11px;color:#86909C;">金额 <b style="color:#F53F3F;">¥' + d.amount + '</b></div>' +
        '</div>';
    }
    var zbNote = info.zb_deposit
      ? '<div style="font-size:11px;color:#FF7D00;margin-top:8px;">⚠️ 此方式可经 ZBpay 充值完成，或直接向下卡转账</div>'
      : '';

    // 收款银行卡卡片（所有方式通用）
    var pb = info.payee_bank || payCtx.payeeBank;
    var bankHtml = '';
    if (pb) {
      var maskedNo2 = pb.account_no || '**** **** **** ****';
      bankHtml =
        '<div style="margin-top:12px;padding:12px;background:linear-gradient(135deg,#FFF7E6,#FFFBF5);border:1px solid #FFDAB9;border-radius:10px;">' +
          '<div style="font-size:12px;font-weight:700;color:#D46B08;margin-bottom:8px;">🏦 收款账户（所有方式通用）</div>' +
          '<div style="font-size:13px;color:#1D2129;margin-bottom:4px;">户名：<b>' + pb.account_name + '</b></div>' +
          '<div style="font-size:13px;color:#1D2129;margin-bottom:4px;">银行：' + pb.bank_name + '</div>' +
          '<div id="railBankNo2" style="font-family:monospace;font-size:17px;font-weight:800;color:#F53F3F;letter-spacing:1px;user-select:none;">' + maskedNo2 + '</div>' +
          '<div style="margin-top:4px;display:flex;align-items:center;gap:8px;">' +
            '<button onclick="revealBankCard(\'railBankNo2\')" style="font-size:11px;padding:3px 10px;background:rgba(0,0,0,0.05);border:1px solid rgba(0,0,0,0.1);border-radius:100px;cursor:pointer;color:#4E5969;">👁 查看完整卡号</button>' +
            '<button onclick="copyBankCard()" style="font-size:11px;padding:3px 10px;background:rgba(0,0,0,0.05);border:1px solid rgba(0,0,0,0.1);border-radius:100px;cursor:pointer;color:#4E5969;">📋 复制掩码</button>' +
          '</div>' +
          '<div style="margin-top:6px;font-size:11px;color:#86909C;">转账 <b style="color:#F53F3F;">¥' + d.amount + '</b>，备注订单号：<span style="font-family:monospace;color:#165DFF;">' + d.order_id + '</span></div>' +
        '</div>';
    }

    area.innerHTML =
      '<div style="padding:14px;border-radius:10px;margin-top:10px;border-left:3px solid ' + brandColor + ';background:#FAFBFC;">' +
        '<div style="font-size:13px;font-weight:700;color:#1D2129;margin-bottom:6px;">' + brandIcon + ' ' + brandName + '</div>' +
        '<div style="font-size:12px;color:#4E5969;margin-bottom:6px;">' + (info.hint || '请完成支付后点击下方按钮') + '</div>' +
        '<div id="rbCountdown" style="font-size:11px;color:#86909C;margin-bottom:8px;"></div>' +
        qrHtml + zbNote + bankHtml +
        '<div style="display:flex;gap:8px;margin-top:14px;">' +
          '<button onclick="completeRailOrder()" style="flex:1;padding:11px;background:#00B42A;color:white;border:none;border-radius:8px;font-size:13px;font-weight:600;cursor:pointer;">✅ 我已完成支付</button>' +
          '<button onclick="cancelRailOrder()" style="padding:11px 14px;background:white;color:#4E5969;border:1px solid #E5E6EB;border-radius:8px;font-size:13px;cursor:pointer;">取消</button>' +
        '</div>' +
        '<div style="margin-top:8px;font-size:10px;color:#C9CDD4;text-align:center;">本订单 15 分钟内有效</div>' +
      '</div>';

    // 启动倒计时
    if (expireTs) {
      payCtx.countdownTimer = setInterval(function() {
        var left = Math.max(0, Math.floor((expireTs - Date.now()) / 1000));
        var el = $('rbCountdown');
        if (el) {
          var mm = String(Math.floor(left / 60)).padStart(2, '0');
          var ss = String(left % 60).padStart(2, '0');
          el.innerHTML = left > 0
            ? '⏳ 订单将在 <b style="color:#FF7D00;">' + mm + ':' + ss + '</b> 后过期'
            : '⚠️ 订单已过期，请取消后重新下单';
        }
        if (left <= 0) { clearInterval(payCtx.countdownTimer); payCtx.countdownTimer = null; }
      }, 1000);
    }

    // 同时启动订单状态轮询（每 3 秒查一次）
    payCtx.pollTimer = setTimeout(pollRailOrderStatus, 3000);
  }

  function pollRailOrderStatus() {
    if (!payCtx.orderId) return;
    api('/rail/orders/' + payCtx.orderId).then(function(d) {
      var o = d.order || {};
      if (o.status === 'paid') {
        stopRailPoll();
        completeRailOrder();
      } else {
        payCtx.pollTimer = setTimeout(pollRailOrderStatus, 3000);
      }
    }).catch(function() { /* network fail, keep polling */ payCtx.pollTimer = setTimeout(pollRailOrderStatus, 5000); });
  }
  function stopRailPoll() {
    if (payCtx && payCtx.pollTimer) { clearTimeout(payCtx.pollTimer); payCtx.pollTimer = null; }
    if (payCtx && payCtx.countdownTimer) { clearInterval(payCtx.countdownTimer); payCtx.countdownTimer = null; }
  }

  window.completeRailOrder = function() {
    if (!payCtx.orderId) return;
    var txn = 'MOCK-' + Date.now();
    api('/rail/orders/' + payCtx.orderId + '/complete', {
      method: 'POST',
      body: { pay_method: payCtx.selectedMethod, transaction_id: txn }
    }).then(function(d) {
      stopRailPoll();
      finalizeRailPay(d, payCtx.selectedMethod);
    }).catch(function(e) {
      toast('❌ 支付确认失败：' + e.message, 'err');
    });
  };

  window.cancelRailOrder = function() {
    stopRailPoll();
    payCtx.orderId = null;
    var area = $('rbPaySelectedArea');
    if (area) area.innerHTML = '';
    toast('已取消支付', 'err');
  };

  // ========== 银行卡号隐藏/显示 ==========
  window.revealBankCard = async function(elId) {
    try {
      // Step 1: 获取一次性 token
      var r1 = await api('/rail/bank-reveal-token', { method: 'POST', body: JSON.stringify({}) });
      var code = r1.reveal_code;
      var expireIn = r1.expire_in;
      // Step 2: 弹窗让用户确认
      var entered = window.prompt('请输入下方 6 位验证码查看完整卡号（' + expireIn + ' 秒有效，仅本次有效）：\n\n验证码：' + code);
      if (!entered) return;
      // Step 3: 换完整卡号
      var r2 = await api('/rail/bank-card', { method: 'POST', body: JSON.stringify({ reveal_code: entered }) });
      var no = (r2.account_no || '').replace(/(.{4})/g, '$1 ').trim();
      var el = document.getElementById(elId);
      if (el) {
        el.textContent = no;
        el.style.userSelect = 'all';
      }
      toast('✅ 完整卡号已显示（仅本次会话有效）', 'ok');
    } catch (e) {
      // api 未登录返回 401
      if (e && e.status === 401) {
        toast('⚠️ 请先登录后查看完整卡号', 'warn');
      } else {
        toast('❌ ' + (e.message || '获取失败'), 'err');
      }
    }
  };

  window.copyBankCard = async function() {
    // 找到第一个显示卡号的元素（掩码版）
    var el = document.getElementById('railBankNo1') || document.getElementById('railBankNo2');
    if (!el) { toast('未找到卡号', 'err'); return; }
    var rawNo = el.textContent.replace(/\s/g, '');
    try {
      await navigator.clipboard.writeText(rawNo);
      toast('📋 卡号已复制到剪贴板', 'ok');
    } catch {
      // 降级：选择文本
      el.style.userSelect = 'all';
      el.focus();
      toast('请手动选中复制', 'warn');
    }
  };

  async function finalizeRailPay(d, method) {
    try {
      // 刷新 prog 和 catalog
      var progData = await api('/rail/progress');
      state.prog = progData.prog;
      updateNav();
      $('rbBuyModal').style.display = 'none';
      toast('✅ 支付成功！内容已解锁（' + (method || 'online') + '）', 'ok');
      await loadCatalog();
      refreshCurrentView();
      payCtx = null;
    } catch (e) {
      toast('✅ 已解锁，但刷新列表失败：' + e.message, 'ok');
      $('rbBuyModal').style.display = 'none';
    }
    pendingBuy = null;
  }

  async function confirmBuy() {
    if (!pendingBuy) return;
    var inp = $('rbCodeInput');
    var code = inp ? inp.value.trim() : '';
    if (!code) { toast('请输入激活码', 'err'); return; }
    var btn = $('rbBuyBtn');
    btn.disabled = true; btn.textContent = '验证中…';
    try {
      var res = await api('/rail/redeem', { method: 'POST', body: { code: code } });
      var progData = await api('/rail/progress');
      state.prog = progData.prog;
      updateNav();
      $('rbBuyModal').style.display = 'none';
      toast('✅ 激活成功！内容已解锁', 'ok');
      await loadCatalog();
      refreshCurrentView();
    } catch (e) {
      toast('❌ ' + (e.message || '激活失败'), 'err');
    } finally {
      btn.disabled = false; btn.textContent = '确认解锁';
      pendingBuy = null;
    }
  }

  // ---------- Start ----------
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

})();
