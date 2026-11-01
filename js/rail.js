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
        method: 'POST', body: { username: u, password: p }
      });
      state.token = data.token;
      setToken(data.token);
      var pl = parseJwt(data.token);
      state.user = pl.sub; state.role = pl.role;
      closeAuth();
      toast('登录成功 · ' + u, 'ok');
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
      updateNav();
    } catch (e) {
      // catalog 公开端点不应失败；如果失败通常是网络问题
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

      // Video placeholder (no actual video files yet)
      var videoSection;
      if (canAccess) {
        videoSection =
          '<div class="rb-video-wrap">' +
            '<div class="rb-video-placeholder">' +
              '<div class="rb-vp-emoji">📽️</div>' +
              '<div class="rb-vp-text">配套视频（约 ' + fmtDur(lesson.duration) + '）</div>' +
              '<div class="rb-vp-sub">视频制作中 · 配套文档已可阅读</div>' +
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
    var plain = md.replace(/[#*`]/g, '').replace(/\n/g, ' ');
    return plain.length > max ? plain.substring(0, max) + '…' : plain;
  }

  // ---------- Purchase Flow ----------
  var pendingBuy = null; // { kind: 'unit'|'part'|'lesson', id, title, price }

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

    var body = $('rbBuyBody');
    var itemLabel = { unit: '整个单元', part: '单个部分', lesson: '单条小结' };
    body.innerHTML =
      '<div class="rb-buy-item" style="flex-direction:column;align-items:stretch;">' +
        '<div style="font-size:15px;font-weight:700;color:#1D2129;margin-bottom:8px;">' + pendingBuy.title + '</div>' +
        '<div style="font-size:12px;color:#86909C;">' + itemLabel[pendingBuy.kind] + ' · 永久解锁</div>' +
      '</div>' +
      '<div style="margin-top:14px;">' +
        '<label style="display:block;font-size:13px;font-weight:600;color:#1D2129;margin-bottom:8px;">🔑 激活码</label>' +
        '<input id="rbCodeInput" type="text" placeholder="ZB-XXXXXXXXXXXX" style="width:100%;padding:12px 16px;font-size:15px;background:#F2F3F5;border:1px solid #E5E6EB;border-radius:8px;font-family:monospace;outline:none;">' +
        '<div style="margin-top:8px;font-size:12px;color:#86909C;">输入 admin 发放的激活码（不区分大小写，分隔符可选）</div>' +
      '</div>';
    $('rbBuyModal').style.display = '';
    setTimeout(function(){ var inp = $('rbCodeInput'); if(inp) inp.focus(); }, 100);
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
