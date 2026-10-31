// ============================================
// ZhiBei Tech Website - Main JS (v2 with AI Demo)
// ============================================

(function () {
  'use strict';

  // -------- Navbar Scroll --------
  const navbar = document.getElementById('navbar');
  window.addEventListener('scroll', () => {
    if (navbar) {
      if (window.scrollY > 50) {
        navbar.style.boxShadow = '0 10px 40px rgba(0,0,0,0.4)';
      } else {
        navbar.style.boxShadow = 'none';
      }
    }
  });

  // -------- Reveal Animation --------
  const reveals = document.querySelectorAll('.reveal');
  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        io.unobserve(entry.target);
      }
    });
  }, { threshold: 0.15 });
  reveals.forEach((el) => io.observe(el));

  // -------- Smooth Scroll --------
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', function (e) {
      const href = this.getAttribute('href');
      if (href === '#' || href.length < 2) return;
      const target = document.querySelector(href);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  // -------- Chat Demo --------
  const chatMessages = document.getElementById('chatMessages');
  const chatInput = document.getElementById('chatInput');
  const sendBtn = document.getElementById('sendBtn');
  const modelSelect = document.getElementById('modelSelect');
  const clearChat = document.getElementById('clearChat');

  const statLatency = document.getElementById('statLatency');
  const statTokens = document.getElementById('statTokens');
  const statModel = document.getElementById('statModel');
  const statStatus = document.getElementById('statStatus');

  // Track status
  let apiAvailable = false;
  let chatHistory = [];

  // Detect API base URL: if port differs or on github pages, use fallback
  function getAPIBase() {
    // If localhost:8080 — use local API server
    if (location.hostname === 'localhost' || location.hostname === '127.0.0.1') {
      return `${location.protocol}//${location.host}/api`;
    }
    // For non-localhost (GitHub Pages etc.), we fall back to the built-in mock mode
    return null;
  }

  // Check API health on load
  async function checkAPI() {
    const apiBase = getAPIBase();
    if (!apiBase) {
      // Not localhost — use mock mode
      apiAvailable = false;
      if (statStatus) statStatus.textContent = '🟡 演示模式';
      return;
    }
    try {
      const res = await fetch(`${apiBase}/health`);
      const data = await res.json();
      apiAvailable = data.status === 'healthy';
      if (statStatus) statStatus.textContent = apiAvailable ? '🟢 在线' : '🟡 演示模式';
    } catch {
      apiAvailable = false;
      if (statStatus) statStatus.textContent = '🟡 演示模式';
    }
  }

  // Mock AI responses (used when API server not available)
  const mockResponses = {
    default: [
      '您好！我是智北 AI 助手 ZB-01。这是前端演示模式的模拟回复。\n\n**要体验完整 AI 能力：**\n1. 在本地运行 server.ps1 启动 API 服务器\n2. 访问 http://localhost:8080 即可\n\n我支持 3 款自研模型：ZB-Large / ZB-Turbo / ZB-Code，提供对话、生成、代码、数据分析四大能力。',
      '这是一个有趣的问题！\n\n**智北 AI 分析路径：**\n• 意图识别 → 明确需求类型\n• 知识检索 → 匹配领域知识\n• 推理生成 → 构建结构化回答\n• 质量校验 → 确保准确性\n\n提示：启动本地 API 服务器可获得真正的 AI 回复！',
      '好的！让我来帮您分析。\n\n当前处于**前端演示模式**，展示的是模拟回复。\n\n**启动方式：**\n```powershell\npowershell -ExecutionPolicy Bypass -File .\\server.ps1\n```\n\n启动后访问 http://localhost:8080 即可体验完整 AI API。'
    ],
    greet: ['您好！我是智北 AI 助手 ZB-01，很高兴为您服务！', '你好！我是智北科技自研 AI，请问有什么可以帮您？'],
    code: ['好的！这是一个 Python 排序示例：\n\n```python\ndef quicksort(arr):\n    if len(arr) <= 1:\n        return arr\n    pivot = arr[len(arr)//2]\n    left = [x for x in arr if x < pivot]\n    mid = [x for x in arr if x == pivot]\n    right = [x for x in arr if x > pivot]\n    return quicksort(left) + mid + quicksort(right)\n\nprint(quicksort([3,1,4,1,5,9,2,6]))\n# → [1, 1, 2, 3, 4, 5, 6, 9]\n```']
  };

  function pickMockReply(msg) {
    const m = (msg || '').toLowerCase();
    if (/^(你好|您好|hi|hello|hey)/i.test(m)) return mockResponses.greet[Math.floor(Math.random() * mockResponses.greet.length)];
    if (/(代码|code|函数|function|def |import)/i.test(m)) return mockResponses.code[0];
    return mockResponses.default[Math.floor(Math.random() * mockResponses.default.length)];
  }

  async function sendMessage() {
    const text = chatInput.value.trim();
    if (!text || sendBtn.disabled) return;

    // Add user message
    addMessage('user', text);
    chatInput.value = '';
    chatInput.style.height = 'auto';

    // Add typing indicator
    const typingEl = addTyping();
    sendBtn.disabled = true;

    const startTime = performance.now();
    const model = modelSelect.value;
    if (statModel) statModel.textContent = model.toUpperCase().replace('ZB-', 'ZB-').replace('-V1', '');

    let reply = '';
    let tokens = 0;

    // Try API if available
    const apiBase = getAPIBase();
    if (apiBase && apiAvailable) {
      try {
        const res = await fetch(`${apiBase}/chat`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ model, message: text })
        });
        const data = await res.json();
        reply = data.reply || '(无回复)';
        tokens = data.usage ? data.usage.total_tokens : 0;
      } catch (err) {
        reply = `⚠️ API 错误：${err.message}`;
      }
    } else {
      // Mock mode — fake delay
      await new Promise((r) => setTimeout(r, 600 + Math.random() * 800));
      reply = pickMockReply(text);
      tokens = Math.floor(text.length / 2) + Math.floor(Math.random() * 100);
    }

    const latency = Math.round(performance.now() - startTime);

    // Remove typing, add real reply
    typingEl.remove();
    addMessage('ai', reply);

    if (statLatency) statLatency.textContent = `${latency}ms`;
    if (statTokens) statTokens.textContent = tokens;
    if (statStatus) statStatus.textContent = apiAvailable ? '🟢 在线' : '🟡 演示模式';

    sendBtn.disabled = false;
  }

  function addMessage(role, text) {
    const div = document.createElement('div');
    div.className = 'msg msg-' + role;
    const avatar = role === 'user' ? '您' : '🤖';
    div.innerHTML = `<div class="msg-avatar">${avatar}</div><div class="msg-bubble"></div>`;
    chatMessages.appendChild(div);

    // Render with simple markdown (code blocks, bold, lists)
    const bubble = div.querySelector('.msg-bubble');
    bubble.innerHTML = formatMarkdown(text);
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  function addTyping() {
    const div = document.createElement('div');
    div.className = 'msg msg-ai';
    div.innerHTML = `<div class="msg-avatar">🤖</div><div class="msg-bubble"><div class="typing"><span></span><span></span><span></span></div></div>`;
    chatMessages.appendChild(div);
    chatMessages.scrollTop = chatMessages.scrollHeight;
    return div;
  }

  // Lightweight markdown
  function formatMarkdown(text) {
    let out = text;
    // Code blocks
    out = out.replace(/```([\s\S]*?)```/g, (_, code) => `<pre style="background:#0d1117;padding:12px;border-radius:8px;overflow-x:auto;margin:8px 0;font-family:monospace;font-size:12px;line-height:1.6;color:#c9d1d9;">${code.trim()}</pre>`);
    // Bold
    out = out.replace(/\*\*([^*]+)\*\*/g, '<strong style="color:var(--accent-cyan)">$1</strong>');
    // Bullet lists
    out = out.replace(/^- (.+)$/gm, '• $1');
    // Line breaks
    out = out.replace(/\n/g, '<br>');
    return out;
  }

  // Auto-resize textarea
  if (chatInput) {
    chatInput.addEventListener('input', function () {
      this.style.height = 'auto';
      this.style.height = Math.min(this.scrollHeight, 120) + 'px';
    });
    chatInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
      }
    });
  }
  if (sendBtn) sendBtn.addEventListener('click', sendMessage);

  // Clear chat
  if (clearChat) {
    clearChat.addEventListener('click', () => {
      chatMessages.innerHTML = `
        <div class="msg msg-ai">
          <div class="msg-avatar">🤖</div>
          <div class="msg-bubble">
            对话已清空！试试这些问题：
            <div class="suggestions">
              <button class="suggestion" data-q="你是谁，介绍一下自己？">你是谁？</button>
              <button class="suggestion" data-q="帮我写一个 Python 排序函数">写一个 Python 排序函数</button>
              <button class="suggestion" data-q="帮我写一篇关于 AI 的短文">写一篇关于 AI 的短文</button>
            </div>
          </div>
        </div>`;
      bindSuggestions();
    });
  }

  // Suggestion buttons
  function bindSuggestions() {
    document.querySelectorAll('.suggestion').forEach((btn) => {
      btn.addEventListener('click', () => {
        chatInput.value = btn.getAttribute('data-q');
        sendMessage();
      });
    });
  }
  bindSuggestions();

  // Model selector update
  if (modelSelect) {
    modelSelect.addEventListener('change', () => {
      if (statModel) statModel.textContent = modelSelect.value.toUpperCase();
    });
  }

  // -------- cURL Tab Switcher --------
  document.querySelectorAll('.curl-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      const parent = tab.closest('.api-curl');
      if (!parent) return;
      parent.querySelectorAll('.curl-tab').forEach((t) => t.classList.remove('active'));
      tab.classList.add('active');
      parent.querySelectorAll('.curl-content').forEach((c) => c.classList.add('hidden'));
      parent.querySelector('#curl' + tab.dataset.tab.charAt(0).toUpperCase() + tab.dataset.tab.slice(1)).classList.remove('hidden');
    });
  });

  // -------- Contact Form --------
  const contactForm = document.getElementById('contactForm');
  if (contactForm) {
    contactForm.addEventListener('submit', (e) => {
      e.preventDefault();
      alert('✅ 消息已提交！智北科技团队将在 24 小时内与您联系。\n\n（此为演示网站，本地演示模式下不会实际发送邮件）');
      contactForm.reset();
    });
  }

  // -------- Init --------
  checkAPI();

  // ============================================================
  // ZBpay Extension
  // ============================================================
  const LS_AUTH = 'zb_auth_token';
  const LS_USER = 'zb_auth_user';
  let currentAuth = null;

  // --- Utils ---
  function getToken() { return localStorage.getItem(LS_AUTH); }
  function setToken(t) { if (t) { localStorage.setItem(LS_AUTH, t); } else { localStorage.removeItem(LS_AUTH); } }
  function getUser() {
    try { return JSON.parse(localStorage.getItem(LS_USER) || 'null'); } catch { return null; }
  }
  function setUser(u) { if (u) { localStorage.setItem(LS_USER, JSON.stringify(u)); } else { localStorage.removeItem(LS_USER); } }
  function fmtQuota(n) {
    n = Number(n) || 0;
    if (n >= 1000000) return (n/1000000).toFixed(1) + 'M';
    if (n >= 1000) return (n/1000).toFixed(1) + 'K';
    return n.toString();
  }
  function toast(msg, type='info') {
    const t = document.createElement('div');
    t.className = `toast toast-${type}`;
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity 0.3s'; setTimeout(() => t.remove(), 300); }, 2800);
  }
  async function apiFetch(path, opts={}) {
    const headers = { 'Content-Type': 'application/json', ...(opts.headers||{}) };
    const token = getToken();
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const r = await fetch(path, { ...opts, headers });
    const ct = r.headers.get('content-type') || '';
    const data = ct.includes('json') ? await r.json() : await r.text();
    if (!r.ok) throw new Error(data?.error || `HTTP ${r.status}`);
    return data;
  }

  // --- Auth UI ---
  function refreshNav() {
    const u = getUser();
    currentAuth = u;
    const guest = document.getElementById('navGuest');
    const user = document.getElementById('navUser');
    const quota = document.getElementById('navQuota');
    if (u) {
      if (guest) guest.style.display = 'none';
      if (user) user.style.display = '';
      if (quota) quota.textContent = fmtQuota(u.quota_tokens) + ' Tokens';
      // refresh from server
      apiFetch('/api/me').then(me => {
        setUser(me);
        if (quota) quota.textContent = fmtQuota(me.quota_tokens) + ' Tokens';
      }).catch(()=>{});
    } else {
      if (guest) guest.style.display = '';
      if (user) user.style.display = 'none';
    }
  }
  window.doLogout = function() {
    setToken(null); setUser(null); refreshNav(); toast('已退出登录', 'info');
  };
  window.openAuth = function(mode) { showAuthModal(mode); };

  function showAuthModal(mode) {
    closeModal();
    const root = document.getElementById('modalRoot');
    const title = mode === 'login' ? '欢迎回来' : '注册新账户';
    const sub = mode === 'login' ? '登录后即可购买 Token 额度' : '注册即送 100,000 Tokens 免费额度';
    const body = `
      <div class="modal-mask" onclick="if(event.target===this) closeModal()">
        <div class="modal">
          <button class="modal-close" onclick="closeModal()">✕</button>
          <h3>${mode === 'login' ? '🔐 ' : '✨ '}${title}</h3>
          <p class="modal-sub">${sub}</p>
          ${mode === 'register' ? `
          <div class="form-group"><label>邮箱 (可选)</label><input id="authEmail" type="email" placeholder="you@company.com"></div>` : ''}
          <div class="form-group"><label>用户名</label><input id="authUser" type="text" placeholder="your_username" autocomplete="username"></div>
          <div class="form-group"><label>密码</label><input id="authPass" type="password" placeholder="至少 6 位" autocomplete="current-password"></div>
          <button class="btn btn-primary btn-full" onclick="doAuth('${mode}')">
            ${mode === 'login' ? '登 录' : '注 册'}
          </button>
          <div class="switch-auth">
            ${mode === 'login' ? '没有账号？' : '已有账号？'}
            <a onclick="showAuthModal('${mode === 'login' ? 'register' : 'login'}')">
              ${mode === 'login' ? '立即注册 →' : '立即登录 →'}
            </a>
          </div>
        </div>
      </div>`;
    root.innerHTML = body;
    setTimeout(() => document.getElementById('authUser')?.focus(), 50);
  }
  window.doAuth = async function(mode) {
    const user = document.getElementById('authUser').value.trim();
    const pass = document.getElementById('authPass').value;
    const email = document.getElementById('authEmail')?.value.trim() || '';
    if (!user || !pass) { toast('请输入用户名和密码', 'error'); return; }
    try {
      const url = mode === 'login' ? '/api/login' : '/api/register';
      const body = mode === 'login' ? { username: user, password: pass } : { username: user, password: pass, email };
      const data = await apiFetch(url, { method: 'POST', body: JSON.stringify(body) });
      setToken(data.token); setUser(data); refreshNav(); closeModal();
      toast(mode === 'login' ? `欢迎回来，${data.username}！` : `注册成功！免费额度 ${fmtQuota(data.quota_tokens)} Tokens`, 'success');
    } catch(e) { toast(e.message, 'error'); }
  };
  window.closeModal = function() {
    const m = document.getElementById('modalRoot'); if (m) m.innerHTML = '';
  };

  // --- Pricing + Payment Flow ---
  let pricingProducts = [];
  function tierOf(id) {
    if (id.startsWith('dev_')) return 'dev';
    if (id.startsWith('pro_')) return 'pro';
    if (id.startsWith('enterprise_')) return 'enterprise';
    return 'all';
  }
  function loadPricing() {
    apiFetch('/api/pay/pricing').then(data => {
      pricingProducts = data.products;
      renderPricingGrid('all');
      document.querySelectorAll('.pay-tab').forEach(t => {
        t.addEventListener('click', () => {
          document.querySelectorAll('.pay-tab').forEach(x => x.classList.remove('active'));
          t.classList.add('active');
          renderPricingGrid(t.dataset.tier);
        });
      });
    }).catch(err => toast('加载定价失败: ' + err.message, 'error'));
  }
  function renderPricingGrid(tier) {
    const grid = document.getElementById('pricingGrid'); if (!grid) return;
    const tagClass = { '免费': 'tag-free', '热门': 'tag-hot', '推荐': 'tag-rec', '企业': 'tag-ent' };
    grid.innerHTML = pricingProducts.map(p => {
      const amount = p.amount === 0 ? '免费' : ('¥' + p.amount);
      const period = p.interval === 'monthly' ? '/ 月' : '/ 年';
      const hidden = (tier !== 'all' && tierOf(p.id) !== tier) ? 'hidden' : '';
      return `
        <div class="price-card reveal" ${hidden}>
          ${p.tag ? `<span class="price-badge-tag ${tagClass[p.tag] || 'tag-hot'}">${p.tag}</span>` : ''}
          <div class="price-name">${p.name}</div>
          <div class="price-num"><span class="price-symbol">${p.amount === 0 ? '' : '¥'}</span>${p.amount === 0 ? '免费' : (p.amount < 100 ? p.amount : p.amount)}</div>
          <div class="price-period">${p.amount === 0 ? '' : period}</div>
          <ul class="price-features">
            <li>🎁 ${fmtQuota(p.quota_tokens)} Tokens 额度</li>
            <li>✅ 全部模型可用</li>
            <li>⚡ 专属 API Key</li>
            <li>🔑 随时升级或退款</li>
          </ul>
          <button class="btn ${p.amount === 0 ? 'btn-outline' : 'btn-primary'} pay-now-btn" onclick="openPay('${p.id}')">
            ${p.amount === 0 ? '免费激活' : '立即支付'}
          </button>
        </div>`;
    }).join('');
  }

  window.openPay = function(pid) {
    const p = pricingProducts.find(x => x.id === pid);
    if (!p) return;
    if (!getToken()) { toast('请先登录或注册', 'info'); showAuthModal('login'); return; }
    showPayModal(p, 1);
  };
  function showPayModal(product, step, orderId) {
    closeModal();
    const root = document.getElementById('modalRoot');
    const amountText = product.amount === 0 ? '免费' : ('¥' + product.amount);
    let stepsHtml = '';
    if (step >= 1) {
      const step1 = step === 1 ? 'active' : 'done';
      const step2 = step >= 2 ? (step === 2 ? 'active' : 'done') : '';
      const step3 = step >= 3 ? 'active' : '';
      stepsHtml = `
        <div class="pay-step done"><div class="step-num">✓</div> 选择套餐</div>
        <div class="pay-step ${step === 2 ? 'active' : ''}"><div class="step-num">${step >= 3 ? '✓' : '2'}</div> 确认订单</div>
        <div class="pay-step ${step === 3 ? 'active' : ''}"><div class="step-num">3</div> 完成支付</div>`;
    }

    let contentHtml = '';
    if (step === 2) {
      contentHtml = `
        <div class="pay-mock-box">
          <div class="qr-icon">📱</div>
          <p>扫码支付 <strong>${amountText}</strong> 或点击下方按钮模拟支付</p>
          <button class="btn btn-primary btn-full" onclick="mockPay('${orderId}')">🅰️ 模拟支付成功（ZBpay Demo）</button>
        </div>
        <p style="font-size:11px;color:var(--text-muted);text-align:center">此为演示环境 · 不会实际扣款 · 真实接入需对接支付宝/微信支付</p>`;
    } else if (step === 3) {
      contentHtml = `
        <div class="pay-success-box">
          <div class="check-icon">✓</div>
          <h4>支付成功！</h4>
          <p>${fmtQuota(product.quota_tokens)} Tokens 已到账</p>
        </div>`;
    }

    const body = `
      <div class="modal-mask" onclick="if(event.target===this) closeModal()">
        <div class="modal">
          <button class="modal-close" onclick="closeModal()">✕</button>
          <h3>💳 ZBpay 支付</h3>
          <p class="modal-sub">${product.name}</p>

          <div class="pay-product-summary">
            <div class="pps-name">${product.name}</div>
            <div class="pps-quota">🎁 到账额度 ${fmtQuota(product.quota_tokens)} Tokens</div>
            <div class="pps-amount">${product.amount === 0 ? '免费' : ('¥' + product.amount)}${product.amount === 0 ? '' : '<small>.00</small>'}</div>
          </div>

          ${step > 1 ? stepsHtml : ''}
          ${contentHtml}

          ${step === 1 ? `<button class="btn btn-primary btn-full" onclick="createOrder('${product.id}')">确认并创建订单 →</button>` : ''}
          ${step === 3 ? `<button class="btn btn-primary btn-full" onclick="closeModal();refreshNav();toast('额度已更新！','success')">完成，查看我的配额</button>` : ''}
        </div>
      </div>`;
    root.innerHTML = body;
  }
  window.createOrder = async function(pid) {
    const p = pricingProducts.find(x => x.id === pid);
    const loadingToast = toast('正在创建订单...', 'info');
    try {
      const data = await apiFetch('/api/pay/orders', { method: 'POST', body: JSON.stringify({ product: pid }) });
      showPayModal(p, 2, data.order_id);
      toast(`订单已创建 ${data.order_id}`, 'info');
    } catch(e) { toast('下单失败: ' + e.message, 'error'); }
  };
  window.mockPay = async function(oid) {
    try {
      const data = await apiFetch('/api/pay/mock-pay', { method: 'POST', body: JSON.stringify({ order_id: oid }) });
      const p = pricingProducts.find(x => true); // we don't know which product - fetch order
      const orderData = await apiFetch('/api/pay/orders/' + oid);
      const pinfo = { name: orderData.product_name, quota_tokens: orderData.quota_tokens, amount: orderData.amount };
      setUser({ ...getUser(), quota_tokens: (getUser()?.quota_tokens || 0) + data.quota_credited });
      showPayModal(pinfo, 3);
      refreshNav();
    } catch(e) { toast('支付失败: ' + e.message, 'error'); }
  };

  // --- Orders ---
  window.openOrders = async function() {
    if (!getToken()) { showAuthModal('login'); return; }
    try {
      const data = await apiFetch('/api/pay/orders');
      showOrdersModal(data.orders || []);
    } catch(e) { toast(e.message, 'error'); }
  };
  function showOrdersModal(orders) {
    closeModal();
    const root = document.getElementById('modalRoot');
    const statusClass = { pending: 'status-pending', paid: 'status-paid', refunded: 'status-refunded', failed: 'status-failed' };
    const statusText = { pending: '待支付', paid: '已支付', refunded: '已退款', failed: '失败' };
    const rows = orders.length === 0
      ? '<div class="order-empty">暂无订单 · 去 <a href="#pricing" style="color:var(--accent-cyan);text-decoration:underline">定价区</a> 购买 Token 吧</div>'
      : orders.map(o => `
        <div class="order-row">
          <div>
            <div class="o-product">${o.product_name}</div>
            <div class="o-id">${o.order_id}</div>
          </div>
          <div class="o-amount">¥${o.amount}</div>
          <span class="o-status ${statusClass[o.status] || 'status-failed'}">${statusText[o.status] || o.status}</span>
          ${o.status === 'paid' ? `<button class="btn btn-outline" style="padding:4px 10px;font-size:11px" onclick="doRefund('${o.order_id}')">退款</button>` : ''}
        </div>`).join('');
    root.innerHTML = `
      <div class="modal-mask" onclick="if(event.target===this) closeModal()">
        <div class="modal modal-lg">
          <button class="modal-close" onclick="closeModal()">✕</button>
          <h3>📋 我的订单</h3>
          <p class="modal-sub">共 ${orders.length} 个订单</p>
          <div class="orders-list">${rows}</div>
        </div>
      </div>`;
  }
  window.doRefund = async function(oid) {
    if (!confirm('确定要退款吗？对应的 Token 额度将被扣除。')) return;
    try {
      await apiFetch('/api/pay/orders/' + oid + '/refund', { method: 'POST' });
      toast('退款成功！', 'success');
      refreshNav(); openOrders();
    } catch(e) { toast(e.message, 'error'); }
  };

  // Boot
  refreshNav();
  loadPricing();
})();
