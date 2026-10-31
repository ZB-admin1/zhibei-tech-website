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
})();
