/* ============================================
   ZhiBei Workbench · Main App v2
   仿飞书 Web 客户端 SPA 结构
   ============================================ */
(function(){
  'use strict';
  var API = (window.__zbRuntime && window.__zbRuntime.apiBase) || '/api';
  var TOKEN_KEY = 'zb_wb_token';
  var state = {
    token: localStorage.getItem(TOKEN_KEY) || '',
    user: null,
    currentView: 'home',
    overview: null,
    apps: null,
    todos: null,
    schedule: null,
    chatHistory: [{ from:'ai', text:'你好！我是智北 AI 助手 🤖 有什么可以帮你的？' }]
  };

  /* ============ UTILS ============ */
  function h(tag, attrs, children){
    var el = document.createElement(tag);
    if(attrs){
      var keys = Object.keys(attrs);
      for(var ki=0; ki<keys.length; ki++){
        var k = keys[ki];
        var v = attrs[k];
        if(v === undefined || v === null) continue;
        if(k==='class') el.className = String(v);
        else if(k==='style') el.style.cssText = String(v);
        else if(k==='onclick') el.onclick = v;
        else if(k.indexOf('on')===0){ /* skip other events */ }
        else { try { el.setAttribute(k, String(v)); } catch(e){ /* ignore bad attrs */ } }
      }
    }
    if(children !== undefined && children !== null){
      var arr = Array.isArray(children) ? children : [children];
      for(var i=0;i<arr.length;i++){
        var c = arr[i];
        if(c === null || c === undefined || c === false) continue;
        if(typeof c === 'string' || typeof c === 'number'){
          el.appendChild(document.createTextNode(String(c)));
        } else if(c.nodeType && typeof c.appendChild !== 'undefined'){
          try { el.appendChild(c); } catch(e){ /* ignore detached nodes */ }
        }
      }
    }
    return el;
  }
  function api(path, opts){
    opts = opts || {};
    var headers = Object.assign({ 'Content-Type':'application/json' }, opts.headers||{});
    if(state.token) headers['Authorization'] = 'Bearer '+state.token;
    var p = fetch(API+path, Object.assign({ headers:headers }, opts));
    return p.then(function(r){
      if(r.status===401){ state.token=''; localStorage.removeItem(TOKEN_KEY); showLogin(); throw new Error('unauthorized'); }
      return r.json();
    });
  }
  function debounce(fn,delay){ var t; return function(){ var args=arguments; clearTimeout(t); var self=this; t=setTimeout(function(){ fn.apply(self,args); },delay); }; }

  /* ============ BOOT ============ */
  function boot(){
    if(state.token){
      api('/me').then(function(d){
        if(d && d.username){ state.user=d; showApp(); } else { showLogin(); }
      }).catch(function(){ showLogin(); });
    } else { showLogin(); }
  }

  /* ============ LOGIN ============ */
  function showLogin(){
    hideLoading();
    document.title = '智北工作台 · 登录';
    document.body.className = 'zb-login';
    document.body.innerHTML = '';
    var card = h('div',{class:'zb-login-card'},[
      h('div',{class:'zb-login-logo'},[
        h('div',{class:'ic'},'ZB'),
        h('div',{},[h('div',{class:'tn'},'智北工作台'),h('div',{class:'ts'},'ZhiBei Workbench · 协作 · 效率 · AI')])
      ]),
      h('div',{class:'zb-login-title'},'欢迎回来'),
      h('div',{class:'zb-login-sub'},'请使用企业管理员账号登录'),
      h('div',{class:'zb-login-field'},[h('label',{},'账号'), h('input',{id:'loginUser',placeholder:'admin',value:'admin'})]),
      h('div',{class:'zb-login-field'},[h('label',{},'密码'), h('input',{id:'loginPass',type:'password',placeholder:'请输入密码',value:'CSFXlhy14'})]),
      h('button',{class:'zb-login-btn',id:'loginBtn'},'登录工作台'),
      h('div',{class:'zb-login-err',id:'loginErr'})
    ]);
    document.body.appendChild(card);
    var btn = document.getElementById('loginBtn');
    var err = document.getElementById('loginErr');
    function doLogin(){
      var u = document.getElementById('loginUser').value.trim();
      var p = document.getElementById('loginPass').value;
      if(!u||!p){ err.textContent='请输入账号和密码'; return; }
      btn.disabled=true; btn.textContent='登录中…'; err.textContent='';
      api('/login',{method:'POST',body:JSON.stringify({username:u,password:p})}).then(function(d){
        if(d && d.token){
          state.token = d.token; state.user = d;
          localStorage.setItem(TOKEN_KEY,d.token); showApp();
        } else { err.textContent = (d&&d.error)||'登录失败'; btn.disabled=false; btn.textContent='登录工作台'; }
      }).catch(function(e){ err.textContent = e.message||'网络错误'; btn.disabled=false; btn.textContent='登录工作台'; });
    }
    btn.onclick = doLogin;
    document.getElementById('loginPass').addEventListener('keydown',function(e){ if(e.key==='Enter') doLogin(); });
  }

  /* ============ APP SHELL ============ */
  function hideLoading(){ var l=document.getElementById('zbLoading'); if(l) l.style.display='none'; }

  function showApp(){
    hideLoading();
    document.title = '智北工作台 · ZhiBei Workbench';
    document.body.className = 'zb-workbench';
    var shell = document.getElementById('zbShell');
    document.body.innerHTML='';
    document.body.appendChild(shell);
    shell.innerHTML='';
    shell.classList.remove('app-shell-hide');
    shell.appendChild(h('div',{class:'zb-banner',id:'zbBanner'}));
    var wrap = h('div',{class:'zb-app'});
    var app = h('div',{id:'zbApp'});
    wrap.appendChild(app);
    wrap.appendChild(h('div',{id:'zbOverlay',style:'position:absolute;top:0;left:0;height:0;z-index:2'}));
    shell.appendChild(wrap);
    renderShell();
    loadOverview();
  }

  function renderShell(){
    var host = document.getElementById('zbApp');
    host.innerHTML='';
    host.style.display='flex';

    // LEFT NAV
    var nav = h('div',{class:'zb-col zb-col-nav'});
    nav.appendChild(h('div',{class:'zb-nav-logo'},'ZB'));
    var navItems = [
      {key:'home',    icon:'🏠', tip:'工作台'},
      {key:'apps',    icon:'⚡', tip:'应用中心'},
      {key:'schedule',icon:'📅', tip:'日程会议'},
      {key:'todos',   icon:'✅', tip:'任务待办'},
      {key:'docs',    icon:'📄', tip:'文档中心'},
      {key:'messages',icon:'💬', tip:'消息中心'}
    ];
    navItems.forEach(function(item){
      var el = h('div',{class:'zb-nav-item'+(item.key==='home'?' active':''), title:item.tip}, item.icon);
      el.setAttribute('data-view', item.key);
      if(item.key==='messages'){ el.appendChild(h('div',{class:'badge'},'3')); }
      el.onclick = function(){ switchView(item.key); };
      nav.appendChild(el);
    });
    var bottomWrap = h('div',{class:'zb-nav-bottom'});
    bottomWrap.appendChild(h('div',{class:'zb-nav-item',title:'设置',onclick:function(){ alert('设置面板'); }},'⚙️'));
    nav.appendChild(bottomWrap);
    host.appendChild(nav);

    // MSG COLUMN
    var msg = h('div',{class:'zb-col zb-col-msg'});
    var mh = h('div',{class:'zb-msg-head'},[
      h('h3',{},'消息'),
      h('div',{class:'zb-msg-search'},[h('span',{},'🔍'), h('input',{placeholder:'搜索消息、联系人…'})])
    ]);
    msg.appendChild(mh);
    var tabs = h('div',{class:'zb-msg-tabs'});
    ['全部','未读','@我','应用通知'].forEach(function(t,i){
      tabs.appendChild(h('div',{class:'zb-msg-tab'+(i===0?' active':''),onclick:function(){
        var siblings=tabs.querySelectorAll('.zb-msg-tab'); for(var s=0;s<siblings.length;s++) siblings[s].classList.remove('active');
        this.classList.add('active');
      }},t));
    });
    msg.appendChild(tabs);
    msg.appendChild(h('div',{class:'zb-msg-list',id:'zbMsgList'}));
    host.appendChild(msg);

    // MAIN COLUMN
    var main = h('div',{class:'zb-col zb-col-main'});
    var tb = h('div',{class:'zb-topbar'},[
      h('div',{class:'zb-search-wrap'},[h('span',{class:'ic'},'🔍'), h('input',{placeholder:'搜索应用、文档、同事…',id:'zbMainSearch'})]),
      h('div',{class:'zb-top-right'},[
        h('div',{class:'zb-tb-btn',title:'通知',onclick:function(){ switchView('messages'); }}, [h('span',{},'🔔'), h('span',{class:'dot'})]),
        h('div',{class:'zb-tb-btn',title:'待办',onclick:function(){ switchView('todos'); }},'✅'),
        h('div',{class:'zb-tb-btn',title:'日历',onclick:function(){ switchView('schedule'); }},'📅'),
        h('div',{class:'zb-user-chip',onclick:function(){ showUserMenu(); }}, [
          h('div',{class:'zb-avatar'}, ((state.user&&state.user.username)||'A').charAt(0).toUpperCase()),
          h('div',{class:'zb-user-info'},[
            h('div',{class:'name'}, (state.user&&state.user.username)||'admin'),
            h('div',{class:'role'}, (state.user&&state.user.role)==='admin'?'超级管理员':'普通成员')
          ])
        ])
      ])
    ]);
    main.appendChild(tb);
    main.appendChild(h('div',{class:'zb-main-scroll',id:'zbMainScroll'}));
    host.appendChild(main);

    // AI COLUMN
    var ai = h('div',{class:'zb-col zb-col-ai'});
    ai.appendChild(h('div',{class:'zb-ai-head'},[
      h('div',{class:'zb-ai-title'},[h('span',{class:'ai-dot'}), 'ZB-AI 对话助手']),
      h('div',{style:'font-size:11px;color:#86909C'},'在线 · 4 模型可选')
    ]));
    var chatBox = h('div',{class:'zb-ai-chat',id:'zbAiChat'});
    state.chatHistory.forEach(function(m){ chatBox.appendChild(renderAiMsg(m)); });
    ai.appendChild(chatBox);
    ai.appendChild(h('div',{class:'zb-ai-quick'},[
      h('div',{class:'zb-ai-quick-title'},'快捷指令'),
      h('div',{class:'zb-ai-quick-btn','data-q':'帮我写一个项目周报模板',onclick:function(){ document.getElementById('zbAiInput').value=this.dataset.q; sendAiMsg(); }},'📝 帮我写项目周报模板'),
      h('div',{class:'zb-ai-quick-btn','data-q':'分析本周待办优先级建议',onclick:function(){ document.getElementById('zbAiInput').value=this.dataset.q; sendAiMsg(); }},'🎯 分析本周待办优先级'),
      h('div',{class:'zb-ai-quick-btn','data-q':'生成一份会议纪要摘要格式',onclick:function(){ document.getElementById('zbAiInput').value=this.dataset.q; sendAiMsg(); }},'📋 会议纪要摘要模板'),
      h('div',{class:'zb-ai-quick-btn','data-q':'用一句话介绍智北智能轨道交通',onclick:function(){ document.getElementById('zbAiInput').value=this.dataset.q; sendAiMsg(); }},'💡 一句话介绍公司')
    ]));
    var aiInput = h('textarea',{placeholder:'和 ZB-AI 对话… 按 Enter 发送',id:'zbAiInput'});
    aiInput.addEventListener('keydown',function(e){
      if(e.key==='Enter' && !e.shiftKey){ e.preventDefault(); sendAiMsg(); }
    });
    aiInput.addEventListener('input',function(){
      this.style.height='auto'; this.style.height=Math.min(this.scrollHeight,120)+'px';
    });
    ai.appendChild(h('div',{class:'zb-ai-input'},[
      aiInput,
      h('button',{class:'zb-ai-send',id:'zbAiSend',onclick:sendAiMsg},'➤')
    ]));
    host.appendChild(ai);

    // search
    document.getElementById('zbMainSearch').addEventListener('input',debounce(function(e){ doSearch(e.target.value); },300));

    // Bind user chip click reliably (override any h()-set onclick)
    var chip = host.querySelector('.zb-user-chip');
    if(chip){
      chip.addEventListener('click', function(e){ e.stopPropagation(); showUserMenu(); });
      chip.style.cursor = 'pointer';
    }
  }

  function renderAiMsg(m){
    var cls = m.from==='user' ? 'user' : 'ai';
    return h('div',{class:'zb-ai-msg '+cls}, String(m.text));
  }
  function appendAiMsg(m){
    var box = document.getElementById('zbAiChat');
    box.appendChild(renderAiMsg(m));
    box.scrollTop = box.scrollHeight;
  }
  function sendAiMsg(){
    var ta = document.getElementById('zbAiInput');
    var text = ta.value.trim(); if(!text) return;
    ta.value = '';
    appendAiMsg({from:'user',text:text});
    state.chatHistory.push({from:'user',text:text});
    appendAiMsg({from:'ai',text:'⏳ 正在思考…'});
    api('/chat',{method:'POST',body:JSON.stringify({message:text,model:'ZB-Turbo-v1'})}).then(function(d){
      var box = document.getElementById('zbAiChat');
      var msgs = box.querySelectorAll('.zb-ai-msg.ai');
      var last = msgs[msgs.length-1];
      if(last){ last.textContent = (d&&d.reply) ? d.reply : 'AI 暂时没有回复'; }
    }).catch(function(){
      var box = document.getElementById('zbAiChat');
      var msgs = box.querySelectorAll('.zb-ai-msg.ai');
      var last = msgs[msgs.length-1];
      if(last) last.textContent = '⚠️ AI 服务暂不可用，请检查登录或稍后再试';
    });
  }

  /* ============ USER MENU ============ */
  function showUserMenu(){
    console.log('[ZB] showUserMenu called, body children:', document.body.children.length);
    // close any existing modal
    document.querySelectorAll('.zb-modal-bg').forEach(function(m){ m.remove(); });
    var bg = h('div',{class:'zb-modal-bg'},null);
    bg.style.zIndex = '9999';
    bg.addEventListener('click',function(e){ if(e.target===bg) bg.remove(); });
    var modal = h('div',{class:'zb-modal',style:'width:360px'},[
      h('div',{class:'zb-modal-head'},[
        h('div',{class:'zb-modal-title'},'个人中心'),
        h('div',{class:'zb-modal-close',onclick:function(){ bg.remove(); }},'✕')
      ]),
      h('div',{class:'zb-modal-body',style:'text-align:center'},[
        h('div',{class:'zb-avatar',style:'width:64px;height:64px;font-size:28px;margin:0 auto 12px'}, ((state.user.username)||'A').charAt(0).toUpperCase()),
        h('div',{style:'font-size:16px;font-weight:600;margin-bottom:4px'}, state.user.username),
        h('div',{style:'font-size:12px;color:#86909C;margin-bottom:4px'}, state.user.email||'—'),
        h('div',{style:'display:inline-block;padding:2px 10px;border-radius:10px;background:#E8F3FF;color:#165DFF;font-size:11px;margin-bottom:16px'}, state.user.role==='admin'?'超级管理员':'普通成员'),
        h('div',{style:'border-top:1px solid #F2F3F5;margin-top:12px;padding-top:16px;text-align:left;display:flex;flex-direction:column;gap:10px'},[
          h('div',{class:'zb-modal-title',style:'font-size:13px;color:#4E5969'},'当前 Token 额度'),
          h('div',{style:'font-size:20px;font-weight:700;color:#165DFF'}, (state.user.quota_tokens||0).toLocaleString() + ' tokens'),
          h('div',{style:'font-size:12px;color:#86909C'},'企业版无限额度')
        ])
      ]),
      h('div',{class:'zb-modal-foot'},[
        h('button',{class:'zb-btn zb-btn-secondary',onclick:function(){ bg.remove(); }},'取消'),
        h('button',{class:'zb-btn zb-btn-primary',style:'background:#F53F3F',onclick:function(){
          localStorage.removeItem(TOKEN_KEY); state.token=''; state.user=null; bg.remove(); showLogin();
        }},'退出登录')
      ])
    ]);
    bg.appendChild(modal);
    document.body.appendChild(bg);
  }

  /* ============ VIEW ROUTING ============ */
  function switchView(v){
    state.currentView = v;
    var items = document.querySelectorAll('.zb-nav-item');
    for(var i=0;i<items.length;i++){
      items[i].classList.toggle('active', items[i].getAttribute('data-view')===v);
    }
    var sc = document.getElementById('zbMainScroll'); if(!sc) return;
    sc.innerHTML='';
    sc.classList.remove('zb-fade-in'); void sc.offsetWidth; sc.classList.add('zb-fade-in');
    switch(v){
      case 'home':     renderHome(); break;
      case 'apps':     renderApps(); break;
      case 'schedule': renderSchedule(); break;
      case 'todos':    renderTodos(); break;
      case 'docs':     renderDocs(); break;
      case 'messages': renderMessages(); break;
    }
  }

  function loadOverview(){
    api('/wb/overview').then(function(d){
      state.overview = d;
      renderMessages();
      switchView(state.currentView);
    });
  }

  /* ============ HOME ============ */
  function renderHome(){
    var sc = document.getElementById('zbMainScroll');
    var d = state.overview || {};
    var greeting = (d.greeting||'你好');
    var uname = (d.user&&d.user.name) || (state.user&&state.user.username) || '同事';

    // Greet banner
    sc.appendChild(h('div',{class:'zb-greet'},[
      h('h1',{}, greeting + '，' + uname + ' 👋'),
      h('p',{}, d.date_str || ''),
      h('div',{class:'zb-greet-stats'},[
        h('div',{class:'zb-greet-stat'},[h('div',{class:'val'}, d.pending_count||0),h('div',{class:'lbl'},'待办')]),
        h('div',{class:'zb-greet-stat'},[h('div',{class:'val'}, d.today_meetings||0),h('div',{class:'lbl'},'今日会议')]),
        h('div',{class:'zb-greet-stat'},[h('div',{class:'val'}, d.unread_count||0),h('div',{class:'lbl'},'未读消息')]),
        h('div',{class:'zb-greet-stat'},[h('div',{class:'val'}, '4'),h('div',{class:'lbl'},'可用 AI 模型')])
      ])
    ]));

    // Row 1: schedule + todos
    var row = h('div',{class:'zb-row'});
    var schCard = h('div',{class:'zb-card'});
    schCard.appendChild(h('div',{class:'zb-card-head'},[
      h('div',{class:'zb-card-title'},[h('span',{class:'dot'}),'今日日程']),
      h('div',{class:'zb-card-more',onclick:function(){ switchView('schedule'); }},'查看全部 »')
    ]));
    var schBody = h('div',{class:'zb-card-body'});
    var schs = d.today_schedule || [];
    if(schs.length===0){ schBody.appendChild(h('div',{style:'color:#86909C;font-size:13px;text-align:center;padding:20px'},'🎉 今天没有会议，专注搞事情！')); }
    for(var si=0; si<schs.length; si++){
      var s = schs[si];
      schBody.appendChild(h('div',{class:'zb-schedule-item'},[
        h('div',{class:'zb-sch-time'},[
          h('div',{class:'t'}, s.time),
          h('div',{class:'d'}, s.date.split('-').slice(1).join('/'))
        ]),
        h('div',{class:'zb-sch-body'},[
          h('div',{class:'zb-sch-title'}, [h('span',{},s.title), h('span',{class:'zb-sch-badge'}, s.type)]),
          h('div',{class:'zb-sch-meta'},[h('span',{},'📍 '+s.loc), h('span',{},'📹 '+s.type)])
        ])
      ]));
    }
    schCard.appendChild(schBody); row.appendChild(schCard);

    var todoCard = h('div',{class:'zb-card'});
    todoCard.appendChild(h('div',{class:'zb-card-head'},[
      h('div',{class:'zb-card-title'},[h('span',{class:'dot',style:'background:#FF7D00'}),'待办任务']),
      h('div',{class:'zb-card-more',onclick:function(){ switchView('todos'); }},'查看全部 »')
    ]));
    var todoBody = h('div',{class:'zb-card-body'});
    var todos = d.pending_todos || [];
    if(todos.length===0){ todoBody.appendChild(h('div',{style:'color:#86909C;font-size:13px;text-align:center;padding:20px'},'✅ 所有任务都完成了！')); }
    for(var ti=0; ti<Math.min(5,todos.length); ti++){
      todoBody.appendChild(buildTodoItem(todos[ti]));
    }
    todoCard.appendChild(todoBody); row.appendChild(todoCard);
    sc.appendChild(row);

    // Row 2: quick apps + recent docs
    var row2 = h('div',{class:'zb-row'});

    var qaCard = h('div',{class:'zb-card'});
    qaCard.appendChild(h('div',{class:'zb-card-head'},[
      h('div',{class:'zb-card-title'},[h('span',{class:'dot',style:'background:#00B42A'}),'常用应用']),
      h('div',{class:'zb-card-more',onclick:function(){ switchView('apps'); }},'全部应用 »')
    ]));
    var qaBody = h('div',{class:'zb-card-body'});
    var qaGrid = h('div',{class:'zb-apps-grid'});
    (d.quick_apps||[]).forEach(function(a){
      qaGrid.appendChild(h('div',{class:'zb-app-card',onclick:function(){ alert('打开: '+a.name); }},[
        h('div',{class:'zb-app-ic',style:'background:'+a.color+'1A;color:'+a.color}, a.icon),
        h('div',{class:'zb-app-name'}, a.name),
        h('div',{class:'zb-app-desc'}, a.desc)
      ]));
    });
    qaBody.appendChild(qaGrid); qaCard.appendChild(qaBody); row2.appendChild(qaCard);

    var docCard = h('div',{class:'zb-card'});
    docCard.appendChild(h('div',{class:'zb-card-head'},[
      h('div',{class:'zb-card-title'},[h('span',{class:'dot',style:'background:#722ED1'}),'最近文档']),
      h('div',{class:'zb-card-more',onclick:function(){ switchView('docs'); }},'查看全部 »')
    ]));
    var docBody = h('div',{class:'zb-card-body'});
    (d.recent_docs||[]).forEach(function(doc){
      docBody.appendChild(h('div',{class:'zb-doc-item'},[
        h('div',{class:'zb-doc-ic '+doc.type}, String(doc.type).toUpperCase().substring(0,4)),
        h('div',{class:'zb-doc-body'},[
          h('div',{class:'zb-doc-name'}, doc.name),
          h('div',{class:'zb-doc-meta'}, doc.owner + ' · ' + doc.updated)
        ]),
        doc.star ? h('span',{class:'zb-doc-star'},'★') : h('span',{style:'width:14px'},'')
      ]));
    });
    docCard.appendChild(docBody); row2.appendChild(docCard);
    sc.appendChild(row2);
  }

  function buildTodoItem(t){
    var row = h('div',{class:'zb-todo-item'+(t.status==='done'?' done':'')});
    var check = h('div',{class:'zb-todo-check'+(t.status==='done'?' done':'')});
    check.onclick = function(){ row.classList.toggle('done'); check.classList.toggle('done'); };
    row.appendChild(check);
    var body = h('div',{class:'zb-todo-body'});
    var priMap = {high:'高',medium:'中',low:'低'};
    body.appendChild(h('div',{class:'zb-todo-title'},[
      h('span',{class:'zb-prio '+t.priority}, priMap[t.priority]||'低'),
      ' ' + t.title
    ]));
    body.appendChild(h('div',{class:'zb-todo-meta'},[
      '📌 ' + t.type,
      '   👤 ' + t.from,
      '   ⏳ 截止 ' + t.due
    ]));
    row.appendChild(body);
    return row;
  }

  /* ============ APPS ============ */
  function renderApps(){
    var sc = document.getElementById('zbMainScroll');
    sc.appendChild(h('div',{style:'margin-bottom:20px'},[
      h('h2',{style:'font-size:20px;font-weight:700;margin-bottom:4px'},'⚡ 应用中心'),
      h('p',{style:'color:#86909C;font-size:13px'},'企业应用 12 个 · AI 大模型 4 个可选')
    ]));
    api('/wb/apps').then(function(d){
      state.apps = d;
      var gridCard = h('div',{class:'zb-card'});
      gridCard.appendChild(h('div',{class:'zb-card-head'},[h('div',{class:'zb-card-title'},[h('span',{class:'dot'}),'全部应用（'+d.apps.length+'）'])]));
      var gridBody = h('div',{class:'zb-card-body'});
      var grid = h('div',{class:'zb-apps-grid'});
      (d.apps||[]).forEach(function(a){
        grid.appendChild(h('div',{class:'zb-app-card',onclick:function(){ alert('打开: '+a.name); }},[
          h('div',{class:'zb-app-ic',style:'background:'+a.color+'1A;color:'+a.color}, a.icon),
          h('div',{class:'zb-app-name'}, a.name),
          h('div',{class:'zb-app-desc'}, a.desc)
        ]));
      });
      gridBody.appendChild(grid); gridCard.appendChild(gridBody); sc.appendChild(gridCard);

      var aiCard = h('div',{class:'zb-card',style:'margin-top:20px'});
      aiCard.appendChild(h('div',{class:'zb-card-head'},[h('div',{class:'zb-card-title'},[h('span',{class:'dot',style:'background:#722ED1'}),'AI 大模型（'+d.ai_models.length+'）'])]));
      var aiBody = h('div',{class:'zb-card-body'});
      (d.ai_models||[]).forEach(function(m){
        aiBody.appendChild(h('div',{class:'zb-doc-item',style:'padding:14px 0'},[
          h('div',{class:'zb-app-ic',style:'width:44px;height:44px;font-size:20px;background:'+m.color+'1A;color:'+m.color},'🤖'),
          h('div',{class:'zb-doc-body'},[
            h('div',{class:'zb-doc-name'}, [m.name + '  ', h('span',{class:'zb-prio',style:'background:'+m.color+'1A;color:'+m.color}, m.tag)]),
            h('div',{class:'zb-doc-meta'}, m.desc + ' · 上下文 ' + m.tokens + ' · 成本 ' + m.cost)
          ]),
          h('button',{class:'zb-btn zb-btn-primary',style:'padding:6px 12px;font-size:12px'}, m.name=== (localStorage.getItem('zb_wb_default_model')||'') ? '已默认' : '设为默认')
        ]));
      });
      aiCard.appendChild(aiBody); sc.appendChild(aiCard);
    });
  }

  /* ============ SCHEDULE ============ */
  function renderSchedule(){
    var sc = document.getElementById('zbMainScroll');
    sc.appendChild(h('div',{style:'margin-bottom:20px'},[
      h('h2',{style:'font-size:20px;font-weight:700;margin-bottom:4px'},'📅 日程会议'),
      h('p',{style:'color:#86909C;font-size:13px'},'7 天内共 7 项日程')
    ]));
    api('/wb/schedule').then(function(d){
      var card = h('div',{class:'zb-card'});
      card.appendChild(h('div',{class:'zb-card-head'},[h('div',{class:'zb-card-title'},[h('span',{class:'dot'}),'全部日程'])]));
      var body = h('div',{class:'zb-card-body'});
      (d.schedule||[]).forEach(function(s){
        body.appendChild(h('div',{class:'zb-schedule-item'},[
          h('div',{class:'zb-sch-time'},[h('div',{class:'t'}, s.time),h('div',{class:'d'}, s.date)]),
          h('div',{class:'zb-sch-body'},[
            h('div',{class:'zb-sch-title'}, [s.title, h('span',{class:'zb-sch-badge'}, s.type)]),
            h('div',{class:'zb-sch-meta'},['📍 '+s.loc, '📅 '+s.date])
          ])
        ]));
      });
      card.appendChild(body); sc.appendChild(card);
    });
  }

  /* ============ TODOS ============ */
  function renderTodos(){
    var sc = document.getElementById('zbMainScroll');
    sc.appendChild(h('div',{style:'margin-bottom:20px'},[
      h('h2',{style:'font-size:20px;font-weight:700;margin-bottom:4px'},'✅ 任务待办'),
      h('p',{style:'color:#86909C;font-size:13px'},(state.overview&&state.overview.pending_count||0)+' 项待处理')
    ]));
    api('/wb/todos').then(function(d){
      state.todos = d;
      var card = h('div',{class:'zb-card'});
      card.appendChild(h('div',{class:'zb-card-head'},[h('div',{class:'zb-card-title'},[h('span',{class:'dot',style:'background:#FF7D00'}),'我的待办（'+(d.pending||0)+' 待处理）'])]));
      var body = h('div',{class:'zb-card-body'});
      (d.todos||[]).forEach(function(t){ body.appendChild(buildTodoItem(t)); });
      card.appendChild(body); sc.appendChild(card);
    });
  }

  /* ============ DOCS ============ */
  function renderDocs(){
    var sc = document.getElementById('zbMainScroll');
    sc.appendChild(h('div',{style:'margin-bottom:20px'},[
      h('h2',{style:'font-size:20px;font-weight:700;margin-bottom:4px'},'📄 文档中心'),
      h('p',{style:'color:#86909C;font-size:13px'},'最近访问的团队文档')
    ]));
    var card = h('div',{class:'zb-card'});
    card.appendChild(h('div',{class:'zb-card-head'},[h('div',{class:'zb-card-title'},[h('span',{class:'dot',style:'background:#722ED1'}),'最近文档'])]));
    var body = h('div',{class:'zb-card-body'});
    var docs = (state.overview&&state.overview.recent_docs) || [];
    docs.forEach(function(doc){
      body.appendChild(h('div',{class:'zb-doc-item',onclick:function(){ alert('打开文档: '+doc.name); }},[
        h('div',{class:'zb-doc-ic '+doc.type}, String(doc.type).toUpperCase().substring(0,4)),
        h('div',{class:'zb-doc-body'},[
          h('div',{class:'zb-doc-name'}, doc.name),
          h('div',{class:'zb-doc-meta'}, doc.owner + ' · ' + doc.updated)
        ]),
        doc.star ? h('span',{class:'zb-doc-star'},'★') : null
      ]));
    });
    card.appendChild(body); sc.appendChild(card);
  }

  /* ============ MESSAGES ============ */
  function renderMessages(){
    var list = document.getElementById('zbMsgList'); if(!list) return;
    list.innerHTML='';
    var msgs = (state.overview && state.overview.messages) || [];
    if(msgs.length===0){ list.appendChild(h('div',{style:'padding:20px;text-align:center;color:#86909C;font-size:13px'},'暂无消息')); return; }
    var colors = ['#165DFF','#00B42A','#FF7D00','#F53F3F','#722ED1','#14C9C9','#3491FA'];
    msgs.forEach(function(m,i){
      var c = m.avatar==='⚙️' ? '#86909C' : colors[i%colors.length];
      var item = h('div',{class:'zb-msg-item'+(m.unread?' unread':'')});
      item.appendChild(h('div',{class:'avatar',style:'background:'+c}, m.avatar));
      var bodyWrap = h('div',{class:'body'});
      bodyWrap.appendChild(h('div',{class:'top'},[
        h('div',{class:'name'}, m.from),
        h('div',{class:'time'}, m.time)
      ]));
      bodyWrap.appendChild(h('div',{class:'text'}, m.text));
      item.appendChild(bodyWrap);
      if(m.unread) item.appendChild(h('div',{class:'unread-dot'}));
      item.onclick = function(){
        this.classList.remove('unread');
        var d = this.querySelector('.unread-dot'); if(d) d.remove();
      };
      list.appendChild(item);
    });
  }

  /* ============ SEARCH ============ */
  function doSearch(q){
    if(!q || q.length<1){ switchView(state.currentView); return; }
    api('/wb/search?q='+encodeURIComponent(q)).then(function(d){
      var sc = document.getElementById('zbMainScroll'); if(!sc) return;
      sc.innerHTML = '';
      sc.appendChild(h('div',{style:'margin-bottom:20px'},[
        h('h2',{style:'font-size:20px;font-weight:700;margin-bottom:4px'},'🔍 搜索结果：'+q),
        h('p',{style:'color:#86909C;font-size:13px'},'找到 '+(d.apps.length+d.docs.length)+' 条结果')
      ]));
      if(d.apps.length){
        var c1 = h('div',{class:'zb-card',style:'margin-bottom:16px'});
        c1.appendChild(h('div',{class:'zb-card-head'},[h('div',{class:'zb-card-title'},[h('span',{class:'dot'}),'应用 ('+d.apps.length+')'])]));
        var b1 = h('div',{class:'zb-card-body'});
        var g = h('div',{class:'zb-apps-grid'});
        d.apps.forEach(function(a){ g.appendChild(h('div',{class:'zb-app-card',onclick:function(){ alert(a.name); }},[
          h('div',{class:'zb-app-ic',style:'background:'+a.color+'1A;color:'+a.color}, a.icon),
          h('div',{class:'zb-app-name'}, a.name),h('div',{class:'zb-app-desc'}, a.desc)
        ])); });
        b1.appendChild(g); c1.appendChild(b1); sc.appendChild(c1);
      }
      if(d.docs.length){
        var c2 = h('div',{class:'zb-card'});
        c2.appendChild(h('div',{class:'zb-card-head'},[h('div',{class:'zb-card-title'},[h('span',{class:'dot',style:'background:#722ED1'}),'文档 ('+d.docs.length+')'])]));
        var b2 = h('div',{class:'zb-card-body'});
        d.docs.forEach(function(doc){ b2.appendChild(h('div',{class:'zb-doc-item'},[
          h('div',{class:'zb-doc-ic '+doc.type}, String(doc.type).toUpperCase().substring(0,4)),
          h('div',{class:'zb-doc-body'},[h('div',{class:'zb-doc-name'}, doc.name), h('div',{class:'zb-doc-meta'}, doc.owner+' · '+doc.updated)]),
          doc.star?h('span',{class:'zb-doc-star'},'★'):null
        ])); });
        c2.appendChild(b2); sc.appendChild(c2);
      }
      if(!d.apps.length && !d.docs.length){ sc.appendChild(h('div',{style:'padding:40px;text-align:center;color:#86909C'},'😢 没有找到相关结果')); }
    });
  }

  document.addEventListener('DOMContentLoaded', boot);
})();
