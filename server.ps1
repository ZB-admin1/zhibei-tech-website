# ============================================
# ZhiBei Tech AI API Server v3
# Features: Auth, Sessions, Image Gen, Admin
# Zero Chinese literals - UTF-8 BOM required
# ============================================

param([int]$Port = 8080)
$ErrorActionPreference = "Stop"

# -------- Config --------
$STORAGE_DIR = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "data"
$USERS_FILE  = Join-Path $STORAGE_DIR "users.json"
$SESS_DIR    = Join-Path $STORAGE_DIR "sessions"
$APIKEYS_FILE= Join-Path $STORAGE_DIR "apikeys.json"
$STATS_FILE  = Join-Path $STORAGE_DIR "stats.json"
$ORDERS_FILE = Join-Path $STORAGE_DIR "ORDERS.json"
$TXN_FILE    = Join-Path $STORAGE_DIR "TRANSACTIONS.json"
$ENT_EMP_FILE = Join-Path $STORAGE_DIR "EMPLOYEES.json"
$ENT_DEPT_FILE = Join-Path $STORAGE_DIR "DEPARTMENTS.json"
$ENT_LOG_FILE = Join-Path $STORAGE_DIR "AUDIT_LOG.json"
$WB_TODO_FILE = Join-Path $STORAGE_DIR "WB_TODO.json"
$WB_APP_FILE  = Join-Path $STORAGE_DIR "WB_APPS.json"
$RAIL_CAT_FILE = Join-Path $STORAGE_DIR "RAIL_CATALOG.json"
$RAIL_PROG_FILE= Join-Path $STORAGE_DIR "RAIL_PROGRESS.json"
$RAIL_CODE_FILE= Join-Path $STORAGE_DIR "RAIL_CODES.json"
$CODE_TPL_FILE= Join-Path $STORAGE_DIR "CODE_TEMPLATES.json"
$CODE_HIST_FILE= Join-Path $STORAGE_DIR "CODE_HISTORY.json"
$RAIL_ORDERS_FILE = Join-Path $STORAGE_DIR "RAIL_ORDERS.json"
$ZB_WALLET_FILE = Join-Path $STORAGE_DIR "ZB_WALLET.json"
$RAIL_VIDEO_META_FILE = Join-Path $STORAGE_DIR "RAIL_VIDEO_META.json"
$MOCK_WHITELIST_FILE = Join-Path $STORAGE_DIR "MOCK_WHITELIST.json"
$SCRIPT_ROOT  = Split-Path -Parent $MyInvocation.MyCommand.Path
$JWT_SECRET  = "zb-secret-2026-zhibei-tech-inner"
$ADMIN_USER  = "admin"
$ADMIN_PASS  = "CSFXlhy14"

# -------- Auth Code Storage (Mock SMS/Email) --------
$script:SMS_CODES  = @{}    # @{ "+8613800138000" = @{ code="123456"; expire=[datetime]; attempts=0 } }
$script:EMAIL_CODES = @{}   # same structure
$script:bankRevealTokens = @{}   # 银行卡号查看临时 token（{user.sub = @{ token; expires; used } }）
$script:bankRevealLastCall = @{} # 限流
$script:CODE_RATE   = @{}   # @{ "192.168.1.1" = @{ last_send=[datetime]; count_per_day=0 } }
$script:MOCK_WHITELIST = @()  # array of IP strings that can use MOCK SMS/Email

function Save-MockWhitelist {
    $script:MOCK_WHITELIST | ConvertTo-Json | Out-File -FilePath $MOCK_WHITELIST_FILE -Encoding utf8
}
function Load-MockWhitelist {
    if (Test-Path $MOCK_WHITELIST_FILE) {
        try {
            $arr = (Get-Content $MOCK_WHITELIST_FILE -Raw | ConvertFrom-Json)
            $script:MOCK_WHITELIST = @($arr)
        } catch {
            $script:MOCK_WHITELIST = @()
        }
    }
}
function Get-MyIPs {
    <# 返回本机所有 IP（自动放行） #>
    $ips = @("127.0.0.1", "::1")
    try {
        $netIPs = Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" }
        foreach ($n in $netIPs) { $ips += $n.IPAddress }
    } catch {}
    return $ips
}
function Test-MockAllowed([string]$ClientIP) {
    <# 判断该 IP 是否允许使用 MOCK 验证码（本机自动 + 管理员授权） #>
    if (-not $ClientIP) { return $false }
    $localIPs = Get-MyIPs
    foreach ($lip in $localIPs) {
        if ($ClientIP -eq $lip) { return $true }
    }
    foreach ($w in $script:MOCK_WHITELIST) {
        if ([string]$w -eq $ClientIP) { return $true }
    }
    return $false
}

function New-6DigitCode {
    $r = New-Object System.Random
    return $r.Next(100000, 999999).ToString()
}
function Add-PhoneCode([string]$Phone,[string]$Code,[int]$ValidMinutes=5) {
    $script:SMS_CODES[$Phone] = [pscustomobject]@{ code=$Code; expire=(Get-Date).AddMinutes($ValidMinutes); attempts=0; sent_at=(Get-Date) }
}
function Add-EmailCode([string]$Email,[string]$Code,[int]$ValidMinutes=5) {
    $script:EMAIL_CODES[$Email.ToLower()] = [pscustomobject]@{ code=$Code; expire=(Get-Date).AddMinutes($ValidMinutes); attempts=0; sent_at=(Get-Date) }
}
function Test-PhoneCode([string]$Phone,[string]$Code) {
    if (-not $script:SMS_CODES.ContainsKey($Phone)) { return $false }
    $e = $script:SMS_CODES[$Phone]
    if ((Get-Date) -gt $e.expire) { $script:SMS_CODES.Remove($Phone); return $false }
    $e.attempts++
    if ($e.attempts -gt 5) { return $false }
    return ($e.code -eq $Code)
}
function Test-EmailCode([string]$Email,[string]$Code) {
    $k = $Email.ToLower()
    if (-not $script:EMAIL_CODES.ContainsKey($k)) { return $false }
    $e = $script:EMAIL_CODES[$k]
    if ((Get-Date) -gt $e.expire) { $script:EMAIL_CODES.Remove($k); return $false }
    $e.attempts++
    if ($e.attempts -gt 5) { return $false }
    return ($e.code -eq $Code)
}

# -------- Validation Helpers --------
function Test-PhoneCN([string]$Phone) {
    if ([string]::IsNullOrWhiteSpace($Phone)) { return $false }
    $p = $Phone -replace '[\s\-\+]',''
    return ($p -match '^1[3-9]\d{9}$')
}
function Test-EmailCN([string]$Email) {
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    return ($Email -match '^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$')
}
function Test-IDCardCN([string]$IdCard) {
    if ([string]::IsNullOrWhiteSpace($IdCard)) { return $false }
    $v = $IdCard -replace '\s',''
    return ($v -match '^\d{17}[\dXx]$')
}
function Get-PasswordStrength([string]$Pw) {
    # 0=极弱 1=弱 2=中 3=强 4=极强
    $score = 0
    if ($Pw.Length -ge 8) { $score++ }
    if ($Pw.Length -ge 12) { $score++ }
    if ($Pw -match '[A-Z]' -and $Pw -match '[a-z]') { $score++ }
    if ($Pw -match '\d') { $score++ }
    if ($Pw -match '[^\w\s]') { $score++ }
    return [Math]::Min(4, [Math]::Max(0, $score))
}
function Get-PasswordStrengthLabel([int]$Score) {
    $labels = @('极弱','弱','中等','强','极强')
    return $labels[$Score]
}

# Ensure storage dirs
if (-not (Test-Path $STORAGE_DIR)) { New-Item -ItemType Directory -Path $STORAGE_DIR -Force | Out-Null }
if (-not (Test-Path $SESS_DIR)) { New-Item -ItemType Directory -Path $SESS_DIR -Force | Out-Null }
if (-not (Test-Path $USERS_FILE)) {
    $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ADMIN_PASS))).Replace("-","")
    @{
        users = @(@{
            username=$ADMIN_USER; password_hash=$hash; role="admin"; email="admin@zhibeitech.com";
            created_at=(Get-Date).ToString("o"); api_key="zb-admin-$(Get-Random -Min 100000 -Max 999999)"; quota_tokens=999999999
        })
    } | ConvertTo-Json -Depth 10 | Out-File -FilePath $USERS_FILE -Encoding utf8
}
if (-not (Test-Path $APIKEYS_FILE)) {
    @{ keys=@(); rate_limit=@{per_minute=60; admin_per_minute=600} } | ConvertTo-Json -Depth 10 | Out-File -FilePath $APIKEYS_FILE -Encoding utf8
}
if (-not (Test-Path $STATS_FILE)) {
    @{ total_calls=0; total_tokens=0; calls_by_model=@{}; daily=@{} } | ConvertTo-Json -Depth 10 | Out-File -FilePath $STATS_FILE -Encoding utf8
}
if (-not (Test-Path $ORDERS_FILE)) {
    @{ orders=@() } | ConvertTo-Json -Depth 10 | Out-File -FilePath $ORDERS_FILE -Encoding utf8
}
if (-not (Test-Path $TXN_FILE)) {
    @{ transactions=@() } | ConvertTo-Json -Depth 10 | Out-File -FilePath $TXN_FILE -Encoding utf8
}
if (-not (Test-Path $ENT_DEPT_FILE)) {
    @{ departments=@(
        @{ id="d1"; name="轨道交通研发中心"; parent_id=$null; headcount=128; manager="张明" },
        @{ id="d2"; name="智能信号系统部"; parent_id="d1"; headcount=45; manager="李华" },
        @{ id="d3"; name="车载AI应用部"; parent_id="d1"; headcount=38; manager="王芳" },
        @{ id="d4"; name="产品运营部"; parent_id=$null; headcount=56; manager="赵磊" },
        @{ id="d5"; name="企业服务部"; parent_id=$null; headcount=34; manager="陈静" },
        @{ id="d6"; name="财务管理部"; parent_id=$null; headcount=18; manager="刘洋" },
        @{ id="d7"; name="人力资源部"; parent_id=$null; headcount=15; manager="孙丽" }
    )} | ConvertTo-Json -Depth 10 | Out-File -FilePath $ENT_DEPT_FILE -Encoding utf8
}
if (-not (Test-Path $ENT_EMP_FILE)) {
    @{ employees=@(
        @{ id="e001"; name="程静"; position="CEO / Founder"; department_id=$null; email="admin@zhibei-tech.com"; phone="138****8888"; status="active"; join_date="2019-03-15"; role="super_admin" },
        @{ id="e002"; name="张明"; position="R&D Director"; department_id="d1"; email="zhangming@zhibei-tech.com"; phone="138****1001"; status="active"; join_date="2019-05-01"; role="admin" },
        @{ id="e003"; name="李华"; position="Signal Architect"; department_id="d2"; email="lihua@zhibei-tech.com"; phone="138****1002"; status="active"; join_date="2020-01-10"; role="member" },
        @{ id="e004"; name="王芳"; position="AI Lead"; department_id="d3"; email="wangfang@zhibei-tech.com"; phone="138****1003"; status="active"; join_date="2020-06-20"; role="member" },
        @{ id="e005"; name="赵磊"; position="Product Director"; department_id="d4"; email="zhaolei@zhibei-tech.com"; phone="138****1004"; status="active"; join_date="2019-08-15"; role="admin" },
        @{ id="e006"; name="陈静"; position="Enterprise Dir"; department_id="d5"; email="chenjing@zhibei-tech.com"; phone="138****1005"; status="active"; join_date="2021-03-01"; role="member" },
        @{ id="e007"; name="周强"; position="AI Engineer"; department_id="d3"; email="zhouqiang@zhibei-tech.com"; phone="138****1006"; status="active"; join_date="2022-07-12"; role="member" },
        @{ id="e008"; name="吴敏"; position="PM"; department_id="d2"; email="wumin@zhibei-tech.com"; phone="138****1007"; status="active"; join_date="2021-11-05"; role="member" },
        @{ id="e009"; name="郑浩"; position="QA"; department_id="d1"; email="zhenghao@zhibei-tech.com"; phone="138****1008"; status="leave"; join_date="2020-04-18"; role="member" },
        @{ id="e010"; name="孙丽"; position="HR Director"; department_id="d7"; email="sunli@zhibei-tech.com"; phone="138****1009"; status="active"; join_date="2019-06-01"; role="member" }
    )} | ConvertTo-Json -Depth 10 | Out-File -FilePath $ENT_EMP_FILE -Encoding utf8
}
if (-not (Test-Path $ENT_LOG_FILE)) {
    @{ logs=@(
        @{ id="log001"; time=(Get-Date).AddMinutes(-5).ToString("o"); actor="admin"; action="登录后台"; target="IP 192.168.2.4"; severity="info" },
        @{ id="log002"; time=(Get-Date).AddMinutes(-15).ToString("o"); actor="admin"; action="手动充值额度"; target="user buyer01 +500000 tokens"; severity="info" },
        @{ id="log003"; time=(Get-Date).AddHours(-2).ToString("o"); actor="admin"; action="修改用户配额"; target="user admin quota_tokens"; severity="info" },
        @{ id="log004"; time=(Get-Date).AddDays(-1).ToString("o"); actor="system"; action="AI API 调用量告警"; target="24h calls 1234"; severity="warning" },
        @{ id="log005"; time=(Get-Date).AddDays(-2).ToString("o"); actor="admin"; action="确认订阅续费"; target="Pro Annual 999"; severity="info" }
    )} | ConvertTo-Json -Depth 10 | Out-File -FilePath $ENT_LOG_FILE -Encoding utf8
}

# -------- Workbench Seed --------
if (-not (Test-Path $WB_TODO_FILE)) {
    @{ todos=@(
        @{ id="t1"; title="审批项目合同 F7AZ-2026-008"; type="approval"; priority="high"; due="2026-10-31"; status="pending"; from="陈静" },
        @{ id="t2"; title="完成智能信号系统 Q4 里程碑报告"; type="task"; priority="high"; due="2026-11-02"; status="pending"; from="self" },
        @{ id="t3"; title="参加车载 AI 需求评审会"; type="meeting"; priority="medium"; due="2026-11-01"; status="pending"; from="张明" },
        @{ id="t4"; title="回复客户 ZB-Metro 技术方案确认邮件"; type="task"; priority="medium"; due="2026-10-31"; status="pending"; from="self" },
        @{ id="t5"; title="整理本周代码提交日志"; type="task"; priority="low"; due="2026-11-03"; status="pending"; from="self" },
        @{ id="t6"; title="员工入职培训：安全规范"; type="meeting"; priority="low"; due="2026-11-05"; status="pending"; from="人力资源部" },
        @{ id="t7"; title="月度预算审批流程"; type="approval"; priority="medium"; due="2026-11-08"; status="pending"; from="刘洋" }
    ); schedule=@(
        @{ id="s1"; title="每日站会"; time="09:30 - 10:00"; date="2026-10-31"; loc="会议室 A"; type="meeting" },
        @{ id="s2"; title="智能信号系统需求评审"; time="10:30 - 12:00"; date="2026-10-31"; loc="线上"; type="meeting" },
        @{ id="s3"; title="商务宴请：ZB-Metro 客户"; time="12:30 - 13:30"; date="2026-10-31"; loc="公司食堂"; type="event" },
        @{ id="s4"; title="技术分享：LLM 微调实践"; time="14:00 - 15:30"; date="2026-10-31"; loc="培训室"; type="meeting" },
        @{ id="s5"; title="与 CEO 一对一沟通"; time="16:00 - 16:45"; date="2026-10-31"; loc="总经理办公室"; type="meeting" },
        @{ id="s6"; title="Q1 项目复盘"; time="10:00 - 11:30"; date="2026-11-01"; loc="会议室 B"; type="meeting" },
        @{ id="s7"; title="周会"; time="09:00 - 09:30"; date="2026-11-02"; loc="会议室 A"; type="meeting" }
    ); messages=@(
        @{ id="m1"; from="张明"; avatar="张"; text="早上好！今天上午 10:30 的评审会材料我已经发到群里了。"; time="09:15"; unread=$true },
        @{ id="m2"; from="李华"; avatar="李"; text="信号系统 v2.3 的灰度数据已经跑完，效果不错 🎉"; time="08:42"; unread=$true },
        @{ id="m3"; from="陈静"; avatar="陈"; text="项目合同需要今天内完成审批，急！"; time="昨天 17:58"; unread=$true },
        @{ id="m4"; from="赵磊"; avatar="赵"; text="AI 日报里的调用量环比增长 23%，需要你过一下。"; time="昨天 15:20"; unread=$false },
        @{ id="m5"; from="system"; avatar="⚙️"; text="ZB-Metro 订阅已自动续费成功"; time="昨天 10:03"; unread=$false }
    ); docs=@(
        @{ id="d1"; name="2026 Q4 智能信号系统里程碑计划.docx"; owner="李华"; updated="今天 09:30"; star=$true; type="doc" },
        @{ id="d2"; name="车载 AI 应用选型调研报告.pdf"; owner="王芳"; updated="昨天"; star=$true; type="pdf" },
        @{ id="d3"; name="ZBpay 系统架构图.drawio"; owner="程静"; updated="2 天前"; star=$false; type="drawio" },
        @{ id="d4"; name="合同_F7AZ-2026-008_智北-XX地铁公司.pdf"; owner="陈静"; updated="3 天前"; star=$false; type="pdf" },
        @{ id="d5"; name="10月财务报表.xlsx"; owner="刘洋"; updated="1 周前"; star=$false; type="sheet" }
    )} | ConvertTo-Json -Depth 10 | Out-File -FilePath $WB_TODO_FILE -Encoding utf8
}

if (-not (Test-Path $WB_APP_FILE)) {
    @{ apps=@(
        @{ id="app01"; name="ZB-AI 对话助手"; icon="🤖"; color="#165DFF"; desc="智北自研大模型，支持对话/生成/代码/分析"; quick=$true },
        @{ id="app02"; name="文档中心"; icon="📄"; color="#00B42A"; desc="在线文档、表格、幻灯片协作"; quick=$true },
        @{ id="app03"; name="日程会议"; icon="📅"; color="#FF7D00"; desc="日历管理、在线会议、会议室预约"; quick=$true },
        @{ id="app04"; name="任务待办"; icon="✅"; color="#722ED1"; desc="个人待办、项目任务、审批流程"; quick=$true },
        @{ id="app05"; name="企业通讯录"; icon="👥"; color="#3491FA"; desc="公司全员联系方式、组织架构"; quick=$false },
        @{ id="app06"; name="工单系统"; icon="🎫"; color="#F53F3F"; desc="IT工单、客服工单、自动派发"; quick=$false },
        @{ id="app07"; name="数据看板"; icon="📊"; color="#14C9C9"; desc="实时运营数据、财务报表"; quick=$false },
        @{ id="app08"; name="合同电子签"; icon="✍️"; color="#FF7D00"; desc="在线签署、合同管理、归档"; quick=$false },
        @{ id="app09"; name="项目管理"; icon="📌"; color="#722ED1"; desc="甘特图、任务流、进度跟踪"; quick=$false },
        @{ id="app10"; name="知识库"; icon="📚"; color="#00B42A"; desc="团队文档沉淀、智能检索"; quick=$false },
        @{ id="app11"; name="考勤打卡"; icon="⏰"; color="#F53F3F"; desc="上下班打卡、请假申请、加班记录"; quick=$false },
        @{ id="app12"; name="发票报销"; icon="🧾"; color="#3491FA"; desc="OCR 发票识别、报销单填写"; quick=$false },
        @{ id="app13"; name="地铁智能运维平台"; icon="🚇"; color="#165DFF"; desc="地铁车辆信号系统实时监测与 AI 预测"; quick=$false },
        @{ id="app14"; name="智慧地铁调度中心"; icon="🚄"; color="#00B42A"; desc="城市地铁线网统一调度指挥"; quick=$false }
    ); ai_models=@(
        @{ id="m1"; name="ZB-Large-v1"; tag="旗舰"; color="#165DFF"; desc="深度思考，长文本写作/分析"; tokens="32K"; cost="中" },
        @{ id="m2"; name="ZB-Turbo-v1"; tag="快速"; color="#14C9C9"; desc="极速响应，日常对话/摘要"; tokens="32K"; cost="低" },
        @{ id="m3"; name="ZB-Code-v1"; tag="代码"; color="#722ED1"; desc="代码生成、Debug、重构建议"; tokens="16K"; cost="中" },
        @{ id="m4"; name="ZB-Image-v1"; tag="图像"; color="#F77234"; desc="AI 绘图、风格迁移"; tokens="—"; cost="高" }
    )} | ConvertTo-Json -Depth 10 | Out-File -FilePath $WB_APP_FILE -Encoding utf8
}

# -------- Rail Academy Catalog --------
# 真实课程目录由 gen_rail_catalog.py 生成（见 data/RAIL_CATALOG.json）
# 不再自动用模板生成——如需重置，请运行 gen_rail_catalog.py
if (-not (Test-Path $RAIL_CAT_FILE)) {
    Write-Host "  [!] RAIL_CATALOG.json not found — run gen_rail_catalog.py to generate" -ForegroundColor Yellow
}
# Default all users start with free_unit unlocked + admin has everything
if (-not (Test-Path $RAIL_PROG_FILE)) {
    @{ user_prog=@{ admin=@{ unlocked_units=@(1..20); unlocked_parts=@(); unlocked_lessons=@(); paid_total=20*89 } } } | ConvertTo-Json -Depth 6 | Out-File -FilePath $RAIL_PROG_FILE -Encoding utf8
}

# -------- Rail Academy Activation Codes Seed (500 codes) --------
if (-not (Test-Path $RAIL_CODE_FILE)) {
    $codeChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".ToCharArray()
    $seedRng = [System.Random]::new(20261031)
    function New-RailCode {
        $sb = [System.Text.StringBuilder]::new()
        for($i=0;$i -lt 12;$i++){ [void]$sb.Append($codeChars[$seedRng.Next(0,$codeChars.Length)]) }
        return "ZB-" + $sb.ToString()
    }
    $codesArr = @()
    $seenCodes = @{}
    # 100 unit codes: 5 per unit × 20 units
    for($u=1;$u -le 20;$u++){
        for($k=0;$k -lt 5;$k++){
            $c = New-RailCode; while($seenCodes.ContainsKey($c)){$c = New-RailCode}
            $seenCodes[$c] = $true
            $codesArr += [pscustomobject]@{
                code=$c; status="available"; target_kind="unit"; target_id="u$u"
                price=89; used_by=$null; used_at=$null; batch="unit-seed"
            }
        }
    }
    # 200 part codes: 1 per part × 200 parts
    for($u=1;$u -le 20;$u++){
        for($p=1;$p -le 10;$p++){
            $c = New-RailCode; while($seenCodes.ContainsKey($c)){$c = New-RailCode}
            $seenCodes[$c] = $true
            $codesArr += [pscustomobject]@{
                code=$c; status="available"; target_kind="part"; target_id="u${u}p${p}"
                price=9; used_by=$null; used_at=$null; batch="part-seed"
            }
        }
    }
    # 200 lesson codes: random lessons
    for($k=0;$k -lt 200;$k++){
        $u = $seedRng.Next(1,21); $p = $seedRng.Next(1,11); $l = $seedRng.Next(1,11)
        $c = New-RailCode; while($seenCodes.ContainsKey($c)){$c = New-RailCode}
        $seenCodes[$c] = $true
        $codesArr += [pscustomobject]@{
            code=$c; status="available"; target_kind="lesson"; target_id="u${u}p${p}l${l}"
            price=1; used_by=$null; used_at=$null; batch="lesson-seed"
        }
    }
    @{
        version=1; generated=(Get-Date).ToString("o"); total=500
        charsets="ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        codes=$codesArr
    } | ConvertTo-Json -Depth 6 | Out-File -FilePath $RAIL_CODE_FILE -Encoding utf8
}

# -------- Code Templates (种子数据) --------
if (-not (Test-Path $CODE_TPL_FILE)) {
    @{ templates=@(
        @{ id="tpl_py_hello"; name="Hello World"; language="python"; description="最简 Python 入门"; category="入门"; code="print('Hello ZhiBei!')" },
        @{ id="tpl_py_fib";   name="斐波那契"; language="python"; description="计算前 N 项斐波那契数列"; category="算法"; code="def fib(n):`n    a, b = 0, 1`n    for _ in range(n):`n        a, b = b, a + b`n    return a`n`nprint([fib(i) for i in range(10)])" },
        @{ id="tpl_ps_sys";   name="系统信息"; language="powershell"; description="PowerShell 打印系统概要"; category="系统"; code="Get-ComputerInfo | Select-Object CsName, OsName, OsVersion, CsTotalPhysicalMemory | Format-List" },
        @{ id="tpl_ps_net";   name="端口扫描"; language="powershell"; description="列出本机监听端口"; category="网络"; code="Get-NetTCPConnection -State Listen | Select-Object LocalPort,OwningProcess | Sort-Object LocalPort | Format-Table -AutoSize" },
        @{ id="tpl_js_arr";   name="数组去重"; language="javascript"; description="JS 数组去重 + 排序"; category="工具"; code="const arr = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];`nconsole.log([...new Set(arr)].sort((a,b)=>a-b));" },
        @{ id="tpl_sql_pivot";name="SQL 分组统计"; language="sql"; description="GROUP BY 聚合示例"; category="数据库"; code="SELECT department, COUNT(*) AS emp_count, AVG(salary) AS avg_salary`nFROM employees`nWHERE status = 'active'`nGROUP BY department`nORDER BY emp_count DESC;" }
    ) } | ConvertTo-Json -Depth 8 | Out-File -FilePath $CODE_TPL_FILE -Encoding utf8
}
if (-not (Test-Path $CODE_HIST_FILE)) {
    @{ history=@() } | ConvertTo-Json -Depth 10 | Out-File -FilePath $CODE_HIST_FILE -Encoding utf8
}
if (-not (Test-Path $RAIL_ORDERS_FILE)) {
    @{ orders=@() } | ConvertTo-Json -Depth 10 | Out-File -FilePath $RAIL_ORDERS_FILE -Encoding utf8
}
if (-not (Test-Path $ZB_WALLET_FILE)) {
    @{ wallets=@{} } | ConvertTo-Json -Depth 6 | Out-File -FilePath $ZB_WALLET_FILE -Encoding utf8
}
if (-not (Test-Path $RAIL_VIDEO_META_FILE)) {
    @{} | ConvertTo-Json | Out-File -FilePath $RAIL_VIDEO_META_FILE -Encoding utf8
}

# -------- Rail Pay Methods (6 types) --------
$RAIL_PAY_METHODS = @(
    [pscustomobject]@{ id="alipay"; label="支付宝"; icon="💙"; desc="扫码 / 跳转支付宝 APP"; zbdeposit=$false; needs_qr=$true },
    [pscustomobject]@{ id="wechat"; label="微信支付"; icon="💚"; desc="扫码 / 跳转微信"; zbdeposit=$false; needs_qr=$true },
    [pscustomobject]@{ id="bank"; label="银行卡"; icon="💳"; desc="支持 ZBpay 充值（Visa / Mastercard / UnionPay）"; zbdeposit=$true; needs_qr=$true },
    [pscustomobject]@{ id="zbpay"; label="ZBpay 余额"; icon="🟣"; desc="平台内充值余额支付，最便捷"; zbdeposit=$false; needs_qr=$false },
    [pscustomobject]@{ id="google"; label="Google Pay"; icon="🟡"; desc="支持 ZBpay 充值（Android / Chrome）"; zbdeposit=$true; needs_qr=$false },
    [pscustomobject]@{ id="apple"; label="Apple Pay"; icon="⚫"; desc="支持 ZBpay 充值（iPhone / Safari）"; zbdeposit=$true; needs_qr=$false }
)
# RAIL pay pricing (mirrors seed codes)
$RAIL_PRICE_MAP = @{
    unit   = 89   # 元
    part   = 9
    lesson = 1
}

# -------- 收款银行卡（统一收款账户） --------
$PAYEE_BANK = [pscustomobject]@{
    bank_name    = "中国工商银行"
    account_name = "智北科技"
    account_no   = "621700386183092"
    swift        = "ICBKCNBJ"
}

# 银行卡号掩码：只显示前 4 位，其余全 ****（任何人都看不到完整号）
function Get-MaskedBank([string]$no) {
    if ([string]::IsNullOrWhiteSpace($no)) { return "" }
    $clean = ($no -replace '\s', '')
    if ($clean.Length -le 4) { return $clean }
    $prefix = $clean.Substring(0, 4)
    $maskLen = $clean.Length - 4
    $mask = ('*' * [Math]::Min($maskLen, 12))
    return "$prefix $mask"
}
function Get-PayeeBankMasked {
    [pscustomobject]@{
        bank_name    = $PAYEE_BANK.bank_name
        account_name = $PAYEE_BANK.account_name
        account_no   = (Get-MaskedBank $PAYEE_BANK.account_no)
        swift        = $PAYEE_BANK.swift
        masked       = $true
    }
}

# -------- Payment Products (ZBpay) --------
$PAY_PRODUCTS = @(
    @{ id="dev_monthly";  name="Developer Monthly";  amount=0;    quota=1000000;  interval="monthly"; tag="免费";    desc="1M tokens / 月，个人开发者首选" },
    @{ id="dev_yearly";   name="Developer Yearly";   amount=0;    quota=12000000; interval="yearly";  tag="免费";    desc="12M tokens / 年" },
    @{ id="pro_monthly";  name="Pro Monthly";        amount=99;   quota=1000000;  interval="monthly"; tag="热门";    desc="1M tokens / 月，¥99/月" },
    @{ id="pro_yearly";   name="Pro Annual";         amount=999;  quota=12000000; interval="yearly";  tag="推荐";    desc="12M tokens / 年，省¥189" },
    @{ id="enterprise_monthly"; name="Enterprise Monthly";  amount=299;  quota=3000000; interval="monthly"; tag="企业"; desc="3M tokens / 月" },
    @{ id="enterprise_yearly";  name="Enterprise Annual";   amount=2999; quota=36000000; interval="yearly";  tag="企业"; desc="36M tokens / 年，省¥589" }
)

# -------- MIME --------
$mimeTypes = @{
    ".html"="text/html; charset=utf-8";".htm"="text/html; charset=utf-8";".css"="text/css; charset=utf-8";
    ".js"="application/javascript; charset=utf-8";".json"="application/json; charset=utf-8";".xml"="application/xml; charset=utf-8";
    ".txt"="text/plain; charset=utf-8";".md"="text/markdown; charset=utf-8";".svg"="image/svg+xml";
    ".png"="image/png";".jpg"="image/jpeg";".ico"="image/x-icon";".webp"="image/webp";
    ".woff"="font/woff";".woff2"="font/woff2";".ttf"="font/ttf"
}
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
function Get-MimeType([string]$Path) {
    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    if ($mimeTypes.ContainsKey($ext)) { return $mimeTypes[$ext] }
    return "application/octet-stream"
}

# -------- HTTP Response --------
function Send-Json {
    param([System.Net.Sockets.NetworkStream]$Stream,[int]$StatusCode,[object]$Data)
    $json = $Data | ConvertTo-Json -Depth 15 -Compress
    $body = [System.Text.Encoding]::UTF8.GetBytes($json)
    $st = switch ($StatusCode) { 200 {"OK"}; 201 {"Created"}; 400 {"Bad Request"}; 401 {"Unauthorized"}; 403 {"Forbidden"}; 404 {"Not Found"}; 429 {"Too Many"}; 500 {"Internal"}; default {"Unknown"} }
    $h = ("HTTP/1.1 $StatusCode $st","Content-Type: application/json; charset=utf-8","Content-Length: $($body.Length)","Access-Control-Allow-Origin: *","Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS","Access-Control-Allow-Headers: Content-Type, Authorization","Connection: close","","") -join "`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($h)
    $Stream.Write($hb,0,$hb.Length); $Stream.Write($body,0,$body.Length); $Stream.Flush()
}
function Send-JsonRaw {
    param([System.Net.Sockets.NetworkStream]$Stream,[string]$RawText,[int]$StatusCode=200)
    $body = [System.Text.Encoding]::UTF8.GetBytes($RawText)
    $st = switch ($StatusCode) { 200 {"OK"}; 201 {"Created"}; 400 {"Bad Request"}; 500 {"Internal"}; default {"Unknown"} }
    $h = ("HTTP/1.1 $StatusCode $st","Content-Type: application/json; charset=utf-8","Content-Length: $($body.Length)","Access-Control-Allow-Origin: *","Connection: close","","") -join "`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($h)
    $Stream.Write($hb,0,$hb.Length); $Stream.Write($body,0,$body.Length); $Stream.Flush()
}
function Send-File {
    param([System.Net.Sockets.NetworkStream]$Stream,[string]$FilePath)
    if (-not (Test-Path $FilePath -PathType Leaf)) { return $false }
    $buf = [System.IO.File]::ReadAllBytes($FilePath)
    $ct = Get-MimeType $FilePath
    $h = ("HTTP/1.1 200 OK","Content-Type: $ct","Content-Length: $($buf.Length)","Access-Control-Allow-Origin: *","Connection: close","","") -join "`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($h)
    $Stream.Write($hb,0,$hb.Length); $Stream.Write($buf,0,$buf.Length); $Stream.Flush()
    return $true
}
function Send-Error { param([System.Net.Sockets.NetworkStream]$Stream,[int]$StatusCode,[string]$Msg)
    Send-Json -Stream $Stream -StatusCode $StatusCode -Data @{ error = $Msg } }

# -------- Storage Helpers --------
function Load-Users { if (Test-Path $USERS_FILE) { $u = @((Get-Content $USERS_FILE -Raw | ConvertFrom-Json).users); return ,$u } else { return ,@() } }
function Save-Users([array]$Users) { @{ users=$Users } | ConvertTo-Json -Depth 10 | Out-File -FilePath $USERS_FILE -Encoding utf8 }
function Load-UserByKey([string]$Key) {
    $users = Load-Users
    foreach ($u in $users) { if ($u.api_key -eq $Key -or $u.username -eq $Key) { return $u } }
    return $null
}
function Load-UserByName([string]$Name) {
    foreach ($u in (Load-Users)) { if ($u.username -eq $Name) { return $u } }
    return $null
}
function Save-Session([string]$Username,[object]$Session) {
    $file = Join-Path $SESS_DIR "$Username.json"
    $existing = @()
    if (Test-Path $file) { $existing = @((Get-Content $file -Raw | ConvertFrom-Json)) }
    # Replace if same id exists, else append
    $idx = -1; for ($i=0;$i -lt $existing.Count;$i++) { if ($existing[$i].id -eq $Session.id) { $idx=$i; break } }
    if ($idx -ge 0) { $existing[$idx] = $Session } else { $existing += $Session }
    $existing | ConvertTo-Json -Depth 15 | Out-File -FilePath $file -Encoding utf8
}
function Load-Sessions([string]$Username) {
    $file = Join-Path $SESS_DIR "$Username.json"
    if (Test-Path $file) { return (Get-Content $file -Raw | ConvertFrom-Json) }
    return @()
}
function Delete-Session([string]$Username,[string]$Sid) {
    $file = Join-Path $SESS_DIR "$Username.json"
    if (-not (Test-Path $file)) { return $false }
    $sessions = @(Get-Content $file -Raw | ConvertFrom-Json)
    $filtered = @($sessions | Where-Object { $_.id -ne $Sid })
    $filtered | ConvertTo-Json -Depth 15 | Out-File -FilePath $file -Encoding utf8
    return $true
}

# -------- Payment Storage (ZBpay) --------
function Load-Orders { if (Test-Path $ORDERS_FILE) { $o = @((Get-Content $ORDERS_FILE -Raw | ConvertFrom-Json).orders); return ,$o } else { return ,@() } }
function Save-Orders([array]$Orders) { @{ orders=$Orders } | ConvertTo-Json -Depth 15 | Out-File -FilePath $ORDERS_FILE -Encoding utf8 }
function Load-Transactions { if (Test-Path $TXN_FILE) { $t = @((Get-Content $TXN_FILE -Raw | ConvertFrom-Json).transactions); return ,$t } else { return ,@() } }
function Save-Transactions([array]$Txns) { @{ transactions=$Txns } | ConvertTo-Json -Depth 15 | Out-File -FilePath $TXN_FILE -Encoding utf8 }
function Get-Product([string]$ProductId) {
    foreach ($p in $PAY_PRODUCTS) { if ($p.id -eq $ProductId) { return $p } }
    return $null
}
function Add-UserQuota([string]$Username,[int]$Delta,[string]$Reason) {
    $users = Load-Users; $ok = $false
    foreach ($u in $users) {
        if ($u.username -eq $Username) {
            $u.quota_tokens = [int]$u.quota_tokens + $Delta; $ok = $true; break
        }
    }
    if ($ok) { Save-Users $users }
    return $ok
}
function New-Txn([string]$Username,[string]$Type,[int]$Amount,[int]$Quota,[string]$Ref,[string]$Note) {
    $txns = Load-Transactions
    $txns += [pscustomobject]@{
        id="txn_$(Get-Random -Min 1000000 -Max 99999999)"; username=$Username; type=$Type;
        amount=$Amount; quota_tokens=$Quota; ref=$Ref; note=$Note; created_at=(Get-Date).ToString("o")
    }
    Save-Transactions $txns
}

# -------- Auth --------
function New-Token([string]$Username,[string]$Role) {
    $header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"alg":"HS256","typ":"JWT"}')).TrimEnd("=").Replace("+","-").Replace("/","_")
    $payloadRaw = "{`"sub`":`"$Username`",`"role`":`"$Role`",`"iat`":$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()),`"exp`":$([DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeSeconds())}"
    $payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payloadRaw)).TrimEnd("=").Replace("+","-").Replace("/","_")
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($JWT_SECRET)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256(,$keyBytes)
    $sigBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$header.$payload"))
    $sig = [System.Convert]::ToBase64String($sigBytes).TrimEnd("=").Replace("+","-").Replace("/","_")
    return "$header.$payload.$sig"
}
function Verify-Token([string]$Token) {
    try {
        $parts = $Token.Split(".")
        if ($parts.Count -ne 3) { return $null }
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($JWT_SECRET)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256(,$keyBytes)
        $sigBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$($parts[0]).$($parts[1])"))
        $expectedSig = [System.Convert]::ToBase64String($sigBytes).TrimEnd("=").Replace("+","-").Replace("/","_")
        if ($parts[2] -ne $expectedSig) { return $null }
        $padded = $parts[1].Replace("-","+").Replace("_","/")
        while ($padded.Length % 4 -ne 0) { $padded += "=" }
        $payloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($padded))
        $payload = $payloadJson | ConvertFrom-Json
        if ($payload.exp -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { return $null }
        return $payload
    } catch { return $null }
}
function Get-BasicAuth([string]$Header) {
    if ([string]::IsNullOrWhiteSpace($Header)) { return $null }
    if ($Header -match "^Bearer\s+(.+)$") { return Verify-Token $Matches[1] }
    if ($Header -match "^Basic\s+(.+)$") {
        try {
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Matches[1]))
            $cols = $decoded.Split(":")
            if ($cols.Count -eq 2) {
                $user = Load-UserByName $cols[0]
                if ($user -and $user.password_hash -eq ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($cols[1]))).Replace("-",""))) {
                    return [pscustomobject]@{ sub=$user.username; role=$user.role }
                }
            }
        } catch {}
    }
    return $null
}

# -------- AI Response --------
function Get-AIResponse([string]$Prompt) {
    $p = $Prompt.Trim().ToLower()
    $ts = (Get-Date).ToString("o")
    $lat = Get-Random -Minimum 80 -Maximum 320
    if ($p -match "hello|hi\b|hey|greetings") {
        return "Hi there! I am ZhiBei AI (ZB-01). I can chat, generate text, write code, analyze data, and create images via our open API."
    }
    if ($p -match "who are you|about you|zhi?bei|zb[-_ ]?ai") {
        $NL="`n"
        return "I am ZhiBei AI ZB-01, built by ZhiBei Tech." + $NL + $NL +
               "Capabilities: Chat, Generate, Code, Analyze, Image" + $NL +
               "Models: ZB-Large / ZB-Turbo / ZB-Code" + $NL +
               "Docs: /api-docs.html"
    }
    if ($p -match "code|function|python|javascript|sql|def |import ") {
        $NL="`n"
        return "Quick Python example:" + $NL + $NL +
               "def quicksort(arr):" + $NL +
               "    if len(arr) <= 1: return arr" + $NL +
               "    pivot = arr[len(arr)//2]" + $NL +
               "    left = [x for x in arr if x < pivot]" + $NL +
               "    mid  = [x for x in arr if x == pivot]" + $NL +
               "    right = [x for x in arr if x > pivot]" + $NL +
               "    return quicksort(left) + mid + quicksort(right)" + $NL + $NL +
               "print(quicksort([3,1,4,1,5,9,2,6]))" + $NL +
               "# => [1,1,2,3,4,5,6,9]"
    }
    $NL="`n"
    return "Received: `"$Prompt`"" + $NL + $NL +
           "Analysis steps:" + $NL +
           "1. Intent recognition" + $NL +
           "2. Knowledge retrieval" + $NL +
           "3. Reasoning & generation" + $NL +
           "4. Quality verification" + $NL + $NL +
           "Model: ZB-Large-v1 | Latency: ${lat}ms | ts: $ts"
}

# -------- Image Generator (SVG) --------
function New-SvgImage([string]$Prompt) {
    $p = $Prompt.ToLower()
    $palettes = @(
        @{a="#00f0ff";b="#a855f7";c="#ec4899"},
        @{a="#10b981";b="#3b82f6";c="#06b6d4"},
        @{a="#f59e0b";b="#ef4444";c="#ec4899"},
        @{a="#6366f1";b="#8b5cf6";c="#d946ef"},
        @{a="#14b8a6";b="#0ea5e9";c="#22d3ee"},
        @{a="#f97316";b="#f43f5e";c="#a855f7"}
    )
    $pal = $palettes[(Get-Random -Min 0 -Max $palettes.Count)]
    $w = 800; $h = 600
    $svgPieces = @()
    $svgPieces += "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 $w $h' width='$w' height='$h'>"
    $svgPieces += "<defs>"
    $svgPieces += "<linearGradient id='bg' x1='0' y1='0' x2='1' y2='1'>"
    $svgPieces += "<stop offset='0%' stop-color='$($pal.a)'/>"
    $svgPieces += "<stop offset='50%' stop-color='$($pal.b)'/>"
    $svgPieces += "<stop offset='100%' stop-color='$($pal.c)'/>"
    $svgPieces += "</linearGradient>"
    $svgPieces += "<filter id='blur'><feGaussianBlur stdDeviation='30'/></filter>"
    $svgPieces += "</defs>"
    $svgPieces += "<rect width='$w' height='$h' fill='#05060a'/>"
    $svgPieces += "<rect width='$w' height='$h' fill='url(#bg)' opacity='0.15'/>"
    # Generate shapes
    $shapeCount = Get-Random -Min 8 -Max 18
    for ($i = 0; $i -lt $shapeCount; $i++) {
        $sx = Get-Random -Min 0 -Max $w
        $sy = Get-Random -Min 0 -Max $h
        $sr = Get-Random -Min 20 -Max 120
        $sc = @($pal.a,$pal.b,$pal.c)[(Get-Random -Min 0 -Max 3)]
        $so = [Math]::Round((Get-Random -Min 20 -Max 80)/100.0,2)
        $svgPieces += "<circle cx='$sx' cy='$sy' r='$sr' fill='$sc' opacity='$so' filter='url(#blur)'/>"
    }
    # Prompt text overlayif ($Prompt.Length -gt 40) { $shortPrompt = $Prompt.Substring(0,37) + "..." } else { $shortPrompt = $Prompt }
    $shortPrompt = [System.Net.WebUtility]::HtmlEncode($shortPrompt)
    $svgPieces += "<rect x='20' y='$($h-80)' width='$($w-40)' height='60' rx='12' fill='rgba(0,0,0,0.6)'/>"
    $svgPieces += "<text x='40' y='$($h-42)' font-family='monospace' font-size='18' fill='#fff'>$shortPrompt</text>"
    $svgPieces += "<text x='$($w-40)' y='30' font-family='monospace' font-size='11' fill='#666' text-anchor='end'>ZB-IMG-v1</text>"
    $svgPieces += "</svg>"
    return ($svgPieces -join "")
}

# -------- Stats Tracker --------
function Invoke-RecordStat([string]$Model,[int]$Tokens,[string]$Endpoint) {
    try {
        $s = Get-Content $STATS_FILE -Raw | ConvertFrom-Json
        $s.total_calls++
        $s.total_tokens += $Tokens
        if (-not $s.calls_by_model.PSObject.Properties[$Model]) { $s.calls_by_model | Add-Member -NotePropertyName $Model -NotePropertyValue 0 }
        $s.calls_by_model.$Model++
        $today = (Get-Date).ToString("yyyy-MM-dd")
        if (-not $s.daily.PSObject.Properties[$today]) { $s.daily | Add-Member -NotePropertyName $today -NotePropertyValue @{ calls=0; tokens=0 } }
        $s.daily.$today.calls++
        $s.daily.$today.tokens += $Tokens
        $s | ConvertTo-Json -Depth 10 | Out-File -FilePath $STATS_FILE -Encoding utf8
    } catch {}
}

# -------- Rail Academy helpers --------
function Save-RailUnlock([string]$User,[string]$Kind,$Key,[int]$Price){
    if (-not (Test-Path $RAIL_PROG_FILE)) {
        @{ user_prog=@{} } | ConvertTo-Json -Depth 6 | Out-File -FilePath $RAIL_PROG_FILE -Encoding utf8
    }
    $json = Get-Content $RAIL_PROG_FILE -Raw | ConvertFrom-Json
    if (-not $json.user_prog.PSObject.Properties[$User]) {
        $json.user_prog | Add-Member -NotePropertyName $User -NotePropertyValue @{ unlocked_units=@(); unlocked_parts=@(); unlocked_lessons=@(); paid_total=0 }
    }
    switch($Kind){
        "unit" { $arr = @($json.user_prog.$User.unlocked_units); if($arr -notcontains $Key){ $arr += [int]$Key; $json.user_prog.$User.unlocked_units = @($arr) } }
        "part" { $arr = @($json.user_prog.$User.unlocked_parts); if($arr -notcontains $Key){ $arr += $Key; $json.user_prog.$User.unlocked_parts = @($arr) } }
        "lesson" { $arr = @($json.user_prog.$User.unlocked_lessons); if($arr -notcontains $Key){ $arr += $Key; $json.user_prog.$User.unlocked_lessons = @($arr) } }
    }
    $json.user_prog.$User.paid_total = [int]$json.user_prog.$User.paid_total + $Price
    $json | ConvertTo-Json -Depth 6 | Out-File -FilePath $RAIL_PROG_FILE -Encoding utf8
    # 注意：轨道科普解锁已改为激活码驱动，不再扣 tokens
}

function Load-RailCodes {
    if (-not (Test-Path $RAIL_CODE_FILE)) { return [pscustomobject]@{ codes=@() } }
    return Get-Content $RAIL_CODE_FILE -Raw | ConvertFrom-Json
}
function Save-RailCodes([object]$Data){
    $Data | ConvertTo-Json -Depth 6 | Out-File -FilePath $RAIL_CODE_FILE -Encoding utf8
}
function Get-RailCode([string]$Code,[object]$CodesData){
    foreach($c in @($CodesData.codes)){ if($c.code -eq $Code){ return $c } }
    return $null
}
function Normalize-RailCode([string]$Code){
    $c = ($Code -replace '\s+','' -replace '[:\-]+','').ToUpper()
    $c = $c -replace '^ZB',''  # strip any accidental ZB prefix from normalization
    return "ZB-" + $c
}

# Redeem an activation code for a user. Returns $null on success, error msg string on failure.
function Redeem-RailCode([string]$Code,[string]$User){
    $codesData = Load-RailCodes
    $entry = Get-RailCode $Code $codesData
    if (-not $entry) { return "激活码不存在" }
    if ($entry.status -eq "used") { return "此激活码已被使用" }
    if ($entry.status -ne "available" -and $entry.status -ne "sold") { return "激活码状态异常" }

    # Apply the unlock based on target_kind + target_id
    $targetKind = $entry.target_kind   # unit | part | lesson
    $targetId   = $entry.target_id     # uN / uNpN / uNpNlN
    switch($targetKind){
        "unit" { Save-RailUnlock -User $User -Kind "unit" -Key ([int]$targetId.Substring(1)) -Price $entry.price }
        "part" { Save-RailUnlock -User $User -Kind "part" -Key $targetId -Price $entry.price }
        "lesson" { Save-RailUnlock -User $User -Kind "lesson" -Key $targetId -Price $entry.price }
        default { return "激活码目标类型无效: $targetKind" }
    }

    # Mark code as used
    foreach($c in @($codesData.codes)){
        if($c.code -eq $Code){
            $c.status = "used"
            $c.used_by = $User
            $c.used_at = (Get-Date).ToString("o")
            break
        }
    }
    Save-RailCodes $codesData
    return $null
}

# -------- Rail Orders Helpers --------
function Get-Price([string]$Kind) {
    if ($RAIL_PRICE_MAP.ContainsKey($Kind)) { return $RAIL_PRICE_MAP[$Kind] }
    return 0
}
function Load-RailOrders {
    if (-not (Test-Path $RAIL_ORDERS_FILE)) { return [pscustomobject]@{ orders=@() } }
    return Get-Content $RAIL_ORDERS_FILE -Raw | ConvertFrom-Json
}
function Save-RailOrders([object]$Data) {
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $RAIL_ORDERS_FILE -Encoding utf8
}
function New-OrderId {
    $rand = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$(Get-Date).ToString('o')-$((Get-Random)))"))).Replace("-","").Substring(0,16).ToUpper()
    return "ZO-$rand"
}
function Load-ZbWallet {
    if (-not (Test-Path $ZB_WALLET_FILE)) { return [pscustomobject]@{ wallets=@{} } }
    return Get-Content $ZB_WALLET_FILE -Raw | ConvertFrom-Json
}
function Save-ZbWallet([object]$Data) {
    $Data | ConvertTo-Json -Depth 6 | Out-File -FilePath $ZB_WALLET_FILE -Encoding utf8
}
function Get-ZbBalance([string]$User) {
    $w = Load-ZbWallet
    if (-not $w.wallets.PSObject.Properties[$User]) { return 0 }
    return [double]$w.wallets.$User.balance
}
function Add-ZbBalance([string]$User,[double]$Amount,[string]$Ref) {
    $w = Load-ZbWallet
    if (-not $w.wallets.PSObject.Properties[$User]) {
        $w.wallets | Add-Member -NotePropertyName $User -NotePropertyValue ([pscustomobject]@{ balance=0; transactions=@() })
    }
    $w.wallets.$User.balance = [double]$w.wallets.$User.balance + $Amount
    $tx = [pscustomobject]@{ id="t_$(Get-Random -Min 100000 -Max 999999)"; type="deposit"; amount=$Amount; ref=$Ref; at=(Get-Date).ToString("o") }
    $w.wallets.$User.transactions = @($tx) + @($w.wallets.$User.transactions | Select-Object -First 49)
    Save-ZbWallet $w
}
function Deduct-ZbBalance([string]$User,[double]$Amount,[string]$Ref) {
    $w = Load-ZbWallet
    if (-not $w.wallets.PSObject.Properties[$User]) { return $false }
    if ([double]$w.wallets.$User.balance -lt $Amount) { return $false }
    $w.wallets.$User.balance = [double]$w.wallets.$User.balance - $Amount
    $tx = [pscustomobject]@{ id="t_$(Get-Random -Min 100000 -Max 999999)"; type="spend"; amount=$Amount; ref=$Ref; at=(Get-Date).ToString("o") }
    $w.wallets.$User.transactions = @($tx) + @($w.wallets.$User.transactions | Select-Object -First 49)
    Save-ZbWallet $w
    return $true
}
function New-QrDataUrl([string]$Text, [string]$Label = "") {
    # 生成伪随机 QR SVG（基于 Text hash 可复现，PS5 兼容，无减法风险）
    [int]$gs = 25     # grid size
    [int]$cs = 8      # cell size (px)
    [int]$gs_x_cs = $gs * $cs
    [int]$corner_pos = $gs - 7   # 右上/左下定位方块的 x 或 y（提前算好，避免内联减法）
    [int]$corner_pos2 = $gs - 6  # 右下角小定位内白块

    # hash
    [int]$hash = 0
    foreach($c in $Text.ToCharArray()) {
        $hash = ($hash * 31 + [int][char]$c) % 99991
    }

    # SVG 头
    $svg = "<svg xmlns='http://www.w3.org/2000/svg' width='$gs_x_cs' height='$gs_x_cs' viewBox='0 0 $gs_x_cs $gs_x_cs'>"
    $svg += "<rect width='100%' height='100%' fill='white'/>"

    # 随机填充（基于 hash 伪随机）
    [int]$rng = $hash
    $pts = @()
    for($y=0; $y -lt $gs; $y++){
        for($x=0; $x -lt $gs; $x++){
            $rng = ($rng * 1103515245 + 12345) % 2147483648
            if(($rng -band 1) -eq 1) { $pts += @($x,$y) }
        }
    }

    for($i=0; $i -lt $pts.Count; $i+=2){
        $svg += "<rect x='$($pts[$i]*$cs)' y='$($pts[$i+1]*$cs)' width='$cs' height='$cs' fill='#1D2129'/>"
    }

    # 三个定位方块（左上 0,0 / 右上 corner_pos,0 / 左下 0,corner_pos）
    $anchors = @(@(0,0), @($corner_pos,0), @(0,$corner_pos))
    foreach($anchor in $anchors){
        [int]$ax = $anchor[0] * $cs
        [int]$ay = $anchor[1] * $cs
        $svg += "<rect x='$ax' y='$ay' width='$($cs*7)' height='$($cs*7)' fill='#1D2129'/>"
        $svg += "<rect x='$($ax+$cs)' y='$($ay+$cs)' width='$($cs*5)' height='$($cs*5)' fill='white'/>"
        $svg += "<rect x='$($ax+$cs*2)' y='$($ay+$cs*2)' width='$($cs*3)' height='$($cs*3)' fill='#1D2129'/>"
    }

    # 右下角小定位方块
    [int]$corner_big = $corner_pos * $cs
    [int]$corner_white = $corner_pos2 * $cs
    $svg += "<rect x='$corner_big' y='$corner_big' width='$($cs*5)' height='$($cs*5)' fill='#1D2129'/>"
    $svg += "<rect x='$corner_white' y='$corner_white' width='$($cs*3)' height='$($cs*3)' fill='white'/>"

    # 标签
    if($Label -ne ""){
        [int]$half = $gs_x_cs / 2
        [int]$bottom = $gs_x_cs + 14
        $svg += "<text x='$half' y='$bottom' font-size='10' text-anchor='middle' fill='#86909C' font-family='monospace'>$Label</text>"
    }
    $svg += "</svg>"
    return "data:image/svg+xml;utf8," + [System.Uri]::EscapeDataString($svg)
}
function New-AlipayQr([string]$OrderId, [double]$Amount, [string]$Note="轨道科普") {
    # 支付宝收款协议（展示给扫码识别用）
    $link = "alipays://platformapi/startapp?appId=20000056&action=qrcode&bizData=" + [System.Uri]::EscapeDataString("amount=$Amount&orderId=$OrderId&note=$Note")
    return New-QrDataUrl $link "alipay-$OrderId"
}
function New-WechatQr([string]$OrderId, [double]$Amount, [string]$Note="轨道科普") {
    # 微信收款协议
    $link = "weixin://wxpay/bizpayurl?pr=" + $OrderId + "&amount=$Amount&desc=$Note"
    return New-QrDataUrl $link "wechat-$OrderId"
}
function New-BankTransferQr([string]$OrderId, [double]$Amount) {
    $link = "ZBBANK://transfer?order=$OrderId&amount=$Amount"
    return New-QrDataUrl $link "bank-$OrderId"
}
function Complete-RailOrder([string]$OrderId,[string]$PayMethod,[string]$TransactionId,[string]$User) {
    $orders = Load-RailOrders
    foreach($o in @($orders.orders)) {
        if ($o.order_id -eq $OrderId -and $o.username -eq $User) {
            if ($o.status -ne "pending") { return "订单已处理" }
            $o.status = "paid"
            $o.pay_method = $PayMethod
            $o.paid_at = (Get-Date).ToString("o")
            if (-not $TransactionId) { $TransactionId = "MOCK-$(Get-Random -Min 1000000 -Max 9999999)" }
            $o.transaction_id = $TransactionId
            # 自动解锁
            $price = [int]$o.amount
            switch($o.kind) {
                "unit"   { Save-RailUnlock -User $User -Kind "unit"   -Key ([int]$o.target_id.Substring(1)) -Price $price }
                "part"   { Save-RailUnlock -User $User -Kind "part"   -Key $o.target_id -Price $price }
                "lesson" { Save-RailUnlock -User $User -Kind "lesson" -Key $o.target_id -Price $price }
                default  { return "订单 kind 无效" }
            }
            Save-RailOrders $orders
            return $null
        }
    }
    return "订单不存在或非本人订单"
}

# -------- Code Admin Helpers --------
function Load-CodeTemplates {
    if (-not (Test-Path $CODE_TPL_FILE)) { return [pscustomobject]@{ templates=@() } }
    return Get-Content $CODE_TPL_FILE -Raw | ConvertFrom-Json
}
function Save-CodeTemplates([object]$Data) {
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $CODE_TPL_FILE -Encoding utf8
}
function Load-CodeHistory {
    if (-not (Test-Path $CODE_HIST_FILE)) { return [pscustomobject]@{ history=@() } }
    return Get-Content $CODE_HIST_FILE -Raw | ConvertFrom-Json
}
function Save-CodeHistory([object]$Data) {
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $CODE_HIST_FILE -Encoding utf8
}
function Add-CodeHistory([string]$User,[string]$Language,[string]$Prompt,[string]$Code,[string]$Endpoint) {
    try {
        $d = Load-CodeHistory
        $d.history = @($d.history)
        if ($Prompt.Length -gt 500) { $promptShort = $Prompt.Substring(0,500) + "..." } else { $promptShort = $Prompt }
        $entry = [pscustomobject]@{
            id = "ch_$(Get-Random -Min 100000 -Max 999999)"
            user = $User; language = $Language; endpoint = $Endpoint
            prompt = $promptShort
            code_len = $Code.Length
            created_at = (Get-Date).ToString("o")
        }
        $d.history = @($entry) + @($d.history | Select-Object -First 999)
        Save-CodeHistory $d
    } catch { }  # best-effort, never fail the main endpoint
}
function Invoke-CodeSandbox([string]$Language,[string]$Code,[int]$TimeoutSec=15) {
    $elapsed = 0; $exit = -1; $out = ""; $errMsg = ""
    try {
        $lang = ($Language.Trim()).ToLower()
        if ($lang -eq "powershell") {
            $tmp = [System.IO.Path]::GetTempFileName() + ".ps1"
            [IO.File]::WriteAllText($tmp, $Code, [Text.Encoding]::UTF8)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $out = & powershell -ExecutionPolicy Bypass -NoProfile -File $tmp 2>&1 | Out-String
            $sw.Stop(); $elapsed = [int]$sw.ElapsedMilliseconds
            $exit = 0
            Remove-Item $tmp -Force -EA SilentlyContinue
        } elseif ($lang -eq "python") {
            $py = Get-Command python -EA SilentlyContinue
            if (-not $py) { $py = Get-Command python3 -EA SilentlyContinue }
            if (-not $py) { $errMsg = "python.exe not found"; $elapsed = 0 }
            else {
                $tmp = [System.IO.Path]::GetTempFileName() + ".py"
                [IO.File]::WriteAllText($tmp, $Code, [Text.Encoding]::UTF8)
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $out = & $py.Source $tmp 2>&1 | Out-String
                $sw.Stop(); $elapsed = [int]$sw.ElapsedMilliseconds
                $exit = $LASTEXITCODE
                Remove-Item $tmp -Force -EA SilentlyContinue
            }
        } elseif ($lang -eq "javascript" -or $lang -eq "node") {
            $node = Get-Command node -EA SilentlyContinue
            if (-not $node) { $errMsg = "node.exe not found"; $elapsed = 0 }
            else {
                $tmp = [System.IO.Path]::GetTempFileName() + ".js"
                [IO.File]::WriteAllText($tmp, $Code, [Text.Encoding]::UTF8)
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $out = & $node.Source $tmp 2>&1 | Out-String
                $sw.Stop(); $elapsed = [int]$sw.ElapsedMilliseconds
                $exit = $LASTEXITCODE
                Remove-Item $tmp -Force -EA SilentlyContinue
            }
        } else {
            $errMsg = "unsupported language: $Language"
        }
    } catch {
        $errMsg = $_.Exception.Message; $exit = -2
    }
    return [pscustomobject]@{ exit_code=$exit; stdout=$out; stderr=$errMsg; elapsed_ms=$elapsed }
}

# -------- API Handler --------
function Handle-API {
    param([string]$Path,[string]$Method,[string]$Body,[string]$AuthHeader,[System.Net.Sockets.NetworkStream]$Stream,[string]$ClientIP="")

    # Parse query string into $Query hashtable, strip from $Path for route matching
    $Query = @{}
    if ($Path -match '\?(.+)$') {
        $qs = $Matches[1]
        foreach ($kv in $qs -split '&') {
            $parts = $kv -split '=',2
            if ($parts.Count -eq 2) { $Query[[System.Uri]::UnescapeDataString($parts[0])] = [System.Uri]::UnescapeDataString($parts[1]) }
        }
        $Path = ($Path -split '\?')[0]
    }

    if ($Method -eq "OPTIONS") { Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok" }; return $true }

    # --- Public endpoints ---
    if ($Path -eq "/api/health") {
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="healthy"; service="ZhiBei AI API"; version="3.0.0"; timestamp=(Get-Date).ToString("o") }
        return $true
    }
    if ($Path -eq "/api/models") {
        Send-Json -Stream $Stream -StatusCode 200 -Data @{
            models = @(
                @{ id="zb-large-v1"; name="ZhiBei Large"; context_length=8192; capabilities=@("chat","generate","code","analyze","image") },
                @{ id="zb-turbo-v1"; name="ZhiBei Turbo"; context_length=4096; capabilities=@("chat","generate") },
                @{ id="zb-code-v1"; name="ZhiBei Code"; context_length=16384; capabilities=@("code","chat") }
            )
        }; return $true
    }

    # --- Auth endpoints (Enhanced v2) ---

    # --- Send SMS / Email verification codes (MOCK - code returned in response) ---
    if ($Path -eq "/api/send-sms-code" -and $Method -eq "POST") {
        try {
            # MOCK whitelist check - only local machine + admin-approved IPs
            if (-not (Test-MockAllowed -ClientIP $ClientIP)) {
                Send-Error $Stream 403 "MOCK mode requires admin approval for IP $ClientIP; local machine auto-allowed"
                return $true
            }
            $req = $Body | ConvertFrom-Json
            $phone = [string]$req.phone
            if (-not (Test-PhoneCN $phone)) { Send-Error $Stream 400 "invalid phone number"; return $true }
            $code = New-6DigitCode
            Add-PhoneCode -Phone $phone -Code $code -ValidMinutes 5
            # Mock: return the code in response (frontend displays it). In production, SMS gateway replaces this.
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                mock_code=$code; expire_in=300; message="verification code sent (MOCK mode - code shown in response)"
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }
    if ($Path -eq "/api/send-email-code" -and $Method -eq "POST") {
        try {
            # MOCK whitelist check
            if (-not (Test-MockAllowed -ClientIP $ClientIP)) {
                Send-Error $Stream 403 "MOCK mode requires admin approval for IP $ClientIP; local machine auto-allowed"
                return $true
            }
            $req = $Body | ConvertFrom-Json
            $email = [string]$req.email
            if (-not (Test-EmailCN $email)) { Send-Error $Stream 400 "invalid email"; return $true }
            $code = New-6DigitCode
            Add-EmailCode -Email $email -Code $code -ValidMinutes 5
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                mock_code=$code; expire_in=300; message="verification code sent (MOCK mode - code shown in response)"
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # --- Register (Enhanced: phone/email verify + password strength + id_card + face + identity + activation) ---
    if ($Path -eq "/api/register" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            $un   = [string]$req.username
            $pw   = [string]$req.password
            if ($req.email) { $em = [string]$req.email } else { $em = "" }
            if ($req.phone) { $phone = [string]$req.phone } else { $phone = "" }
            if ($req.code) { $code = [string]$req.code } else { $code = "" }
            if ($req.verify_type) { $verify_type = [string]$req.verify_type } else { $verify_type = "phone" }
            if ($req.id_card) { $id_card = [string]$req.id_card } else { $id_card = "" }
            if ($req.face_data) { $face_data = [string]$req.face_data } else { $face_data = "" }
            if ($req.identity) { $identity = [string]$req.identity } else { $identity = "other" }
            if ($req.activation_code) { $activation_code = [string]$req.activation_code } else { $activation_code = "" }

            # --- Basic field validation ---
            if ([string]::IsNullOrWhiteSpace($un) -or [string]::IsNullOrWhiteSpace($pw)) { Send-Error $Stream 400 "username and password required"; return $true }
            if ($un.Length -lt 3) { Send-Error $Stream 400 "username min 3 chars"; return $true }
            if ($un.Length -gt 20) { Send-Error $Stream 400 "username max 20 chars"; return $true }
            if ($pw.Length -lt 6) { Send-Error $Stream 400 "password min 6 chars"; return $true }

            # --- Verify type resolution ---
            $resolved_email = $em
            $resolved_phone = $phone
            if ($verify_type -eq "phone") {
                if (-not (Test-PhoneCN $phone)) { Send-Error $Stream 400 "invalid phone number format"; return $true }
                if (-not (Test-PhoneCode -Phone $phone -Code $code)) { Send-Error $Stream 400 "invalid or expired phone verification code"; return $true }
                # Auto-generate username from phone if none provided
                if ([string]::IsNullOrWhiteSpace($un)) { $un = "u_" + ($phone.Substring($phone.Length - 6)) }
            } elseif ($verify_type -eq "email") {
                if (-not (Test-EmailCN $em)) { Send-Error $Stream 400 "invalid email format"; return $true }
                if (-not (Test-EmailCode -Email $em -Code $code)) { Send-Error $Stream 400 "invalid or expired email verification code"; return $true }
            } else {
                Send-Error $Stream 400 "verify_type must be 'phone' or 'email'"; return $true
            }

            # --- Optional fields ---
            if (-not [string]::IsNullOrWhiteSpace($id_card)) {
                if (-not (Test-IDCardCN $id_card)) { Send-Error $Stream 400 "invalid ID card number format"; return $true }
            }
            if (-not [string]::IsNullOrWhiteSpace($em) -and $verify_type -ne "email") {
                if (-not (Test-EmailCN $em)) { Send-Error $Stream 400 "invalid email format"; return $true }
            }
            if (-not [string]::IsNullOrWhiteSpace($phone) -and $verify_type -ne "phone") {
                if (-not (Test-PhoneCN $phone)) { Send-Error $Stream 400 "invalid phone format"; return $true }
            }

            # --- Uniqueness checks ---
            $existing = Load-UserByName $un
            if ($existing) { Send-Error $Stream 400 "username already exists"; return $true }
            if (-not [string]::IsNullOrWhiteSpace($resolved_email)) {
                foreach ($u in (Load-Users)) { if ($u.email -and $u.email -eq $resolved_email) { Send-Error $Stream 400 "email already registered"; return $true } }
            }
            if (-not [string]::IsNullOrWhiteSpace($resolved_phone)) {
                foreach ($u in (Load-Users)) { if ($u.phone -and $u.phone -eq $resolved_phone) { Send-Error $Stream 400 "phone already registered"; return $true } }
            }

            # --- Identity whitelist ---
            $identities = @("student","teacher","parent","engineer","other")
            if ($identities -notcontains $identity) { $identity = "other" }

            # --- Activation code redemption (optional) ---
            $activation_applied = $false
            if (-not [string]::IsNullOrWhiteSpace($activation_code)) {
                # First check code existence
                $normCode = Normalize-RailCode -Code $activation_code
                if (-not (Get-RailCode $normCode)) { Send-Error $Stream 400 "activation code not found"; return $true }
            }

            # --- Create user ---
            $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pw))).Replace("-","")
            $strength = Get-PasswordStrength $pw
            $strength_label = Get-PasswordStrengthLabel $strength

            $face_hash = ""
            if (-not [string]::IsNullOrWhiteSpace($face_data)) {
                # Don't store full face_data for privacy. Store a hash + flag.
                $face_hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($face_data.Substring(0, [Math]::Min(50, $face_data.Length)))))).Replace("-","")
            }

            if ($id_card) { $idOut = $id_card } else { $idOut = "" }
            if ($face_hash) { $fvOut = $true } else { $fvOut = $false }
            $users = Load-Users
            $users += [pscustomobject]@{
                username=$un; password_hash=$hash; role="user";
                email=$resolved_email; phone=$resolved_phone;
                id_card=$idOut;
                face_hash=$face_hash; face_verified=$fvOut;
                identity=$identity;
                created_at=(Get-Date).ToString("o");
                api_key="zb-$(Get-Random -Min 100000 -Max 999999)";
                quota_tokens=100000
            }
            Save-Users $users
            $newUser = $users[-1]

            # --- Redeem activation if provided ---
            if (-not [string]::IsNullOrWhiteSpace($activation_code)) {
                $normCode = Normalize-RailCode -Code $activation_code
                $err = Redeem-RailCode -Code $normCode -User $un
                if ($err) {
                    # User created but activation failed - not fatal
                } else {
                    $activation_applied = $true
                }
            }

            # --- Invalidate the verification code so it cannot be reused ---
            if ($verify_type -eq "phone" -and $script:SMS_CODES.ContainsKey($phone)) { $script:SMS_CODES.Remove($phone) }
            if ($verify_type -eq "email" -and $script:EMAIL_CODES.ContainsKey($em.ToLower())) { $script:EMAIL_CODES.Remove($em.ToLower()) }

            $token = New-Token $un "user"
            Send-Json -Stream $Stream -StatusCode 201 -Data @{
                token=$token; username=$un; role="user"; api_key=$newUser.api_key;
                quota_tokens=$newUser.quota_tokens;
                email=$newUser.email; phone=$newUser.phone;
                identity=$identity;
                password_strength=$strength;
                face_verified=([bool]$face_hash);
                activation_applied=$activation_applied;
                message="registration successful"
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # --- Login (Enhanced: supports username / phone / email) ---
    if ($Path -eq "/api/login" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            $cred = [string]$req.credential
            $pw = [string]$req.password
            # Fallback for old clients sending username
            if ([string]::IsNullOrWhiteSpace($cred) -and $req.username) { $cred = [string]$req.username }
            if ([string]::IsNullOrWhiteSpace($pw)) { Send-Error $Stream 400 "password required"; return $true }
            if ([string]::IsNullOrWhiteSpace($cred)) { Send-Error $Stream 400 "username/phone/email required"; return $true }

            $user = $null
            if (Test-PhoneCN $cred) {
                foreach ($u in (Load-Users)) { if ($u.phone -and $u.phone -eq $cred) { $user = $u; break } }
            } elseif (Test-EmailCN $cred) {
                foreach ($u in (Load-Users)) { if ($u.email -and $u.email.ToLower() -eq $cred.ToLower()) { $user = $u; break } }
            } else {
                $user = Load-UserByName $cred
            }
            if (-not $user) { Send-Error $Stream 401 "invalid credentials"; return $true }

            $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pw))).Replace("-","")
            if ($user.password_hash -ne $hash) { Send-Error $Stream 401 "invalid credentials"; return $true }

            $token = New-Token $user.username $user.role
            if ($user.phone) { $pOut = $user.phone } else { $pOut = "" }
            if ($user.identity) { $idOut2 = $user.identity } else { $idOut2 = "other" }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                token=$token; username=$user.username; role=$user.role; api_key=$user.api_key;
                quota_tokens=$user.quota_tokens; email=$user.email; phone=$pOut;
                identity=$idOut2;
                message="login successful"
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # --- Auth-required endpoints ---
    $auth = Get-BasicAuth $AuthHeader
    $needsAuth = $Path -match "^/api/me" -or $Path -match "^/api/sessions" -or $Path -match "^/api/admin"
    if ($needsAuth -and -not $auth) { Send-Error $Stream 401 "authentication required"; return $true }

    if ($Path -eq "/api/me") {
        $u = Load-UserByName $auth.sub
        if (-not $u) { Send-Error $Stream 404 "user not found"; return $true }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{
            username=$u.username; role=$u.role; email=$u.email; api_key=$u.api_key;
            quota_tokens=$u.quota_tokens; created_at=$u.created_at
        }; return $true
    }

    # --- Chat endpoints (work without auth too, but with auth tracks user) ---if ($auth) { $userForQuota = Load-UserByName $auth.sub } else { $userForQuota = $null }
    $quotaExceeded = $false
    if ($userForQuota -and $userForQuota.quota_tokens -le 0) { $quotaExceeded = $true }

    if ($Path -eq "/api/chat" -and $Method -eq "POST") {
        try {
            if ($quotaExceeded) { Send-Error $Stream 429 "quota exceeded"; return $true }
            $req = $Body | ConvertFrom-Json
            $userMsg = ""
            if ($req.message) { $userMsg = [string]$req.message }
            elseif ($req.messages -and $req.messages.Count -gt 0) { $userMsg = [string]$req.messages[-1].content }
            if ([string]::IsNullOrWhiteSpace($userMsg)) { Send-Error $Stream 400 "message required"; return $true }
            if ($req.model) { $model = [string]$req.model } else { $model = "zb-large-v1" }
            if ($req.session_id) { $sid = [string]$req.session_id } else { $sid = $null }
            $replyText = Get-AIResponse -Prompt $userMsg
            $tokens = $userMsg.Length + $replyText.Length
            Invoke-RecordStat -Model $model -Tokens $tokens -Endpoint "chat"
            if ($userForQuota) {
                $users = Load-Users; foreach ($u in $users) { if ($u.username -eq $userForQuota.username) { $u.quota_tokens = [Math]::Max(0, $u.quota_tokens - $tokens) } }; Save-Users $users
            }
            # Save session
            if ($auth -and -not [string]::IsNullOrWhiteSpace($sid)) {
                $sessions = Load-Sessions $auth.sub
                $sess = $sessions | Where-Object { $_.id -eq $sid } | Select-Object -First 1
                if (-not $sess) { $sess = [pscustomobject]@{ id=$sid; title=$userMsg.Substring(0,[Math]::Min(40,$userMsg.Length)); messages=@(); created_at=(Get-Date).ToString("o"); updated_at=(Get-Date).ToString("o") } }
                $sess.messages += [pscustomobject]@{ role="user"; content=$userMsg; at=(Get-Date).ToString("o") }
                $sess.messages += [pscustomobject]@{ role="assistant"; content=$replyText; at=(Get-Date).ToString("o") }
                $sess.updated_at = (Get-Date).ToString("o")
                Save-Session $auth.sub $sess
            }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                id="chat_$(Get-Random -Min 100000 -Max 999999)"; model=$model; reply=$replyText;
                session_id=$sid;
                usage=@{ prompt_tokens=$userMsg.Length; completion_tokens=$replyText.Length; total_tokens=$tokens }
                timestamp=(Get-Date).ToString("o")
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    if ($Path -eq "/api/generate" -and $Method -eq "POST") {
        try {
            if ($quotaExceeded) { Send-Error $Stream 429 "quota exceeded"; return $true }
            $req = $Body | ConvertFrom-Json
            if ($req.prompt) { $prompt = [string]$req.prompt } else { $prompt = "" }
            if ([string]::IsNullOrWhiteSpace($prompt)) { Send-Error $Stream 400 "prompt required"; return $true }
            if ($req.model) { $model = [string]$req.model } else { $model = "zb-large-v1" }
            $text = Get-AIResponse -Prompt $prompt
            Invoke-RecordStat -Model $model -Tokens ($prompt.Length + $text.Length) -Endpoint "generate"
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                id="gen_$(Get-Random -Min 100000 -Max 999999)"; model=$model; text=$text; prompt=$prompt; timestamp=(Get-Date).ToString("o")
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    if ($Path -eq "/api/code" -and $Method -eq "POST") {
        try {
            if ($quotaExceeded) { Send-Error $Stream 429 "quota exceeded"; return $true }
            $req = $Body | ConvertFrom-Json
            if ($req.prompt) { $prompt = [string]$req.prompt } else { $prompt = "" }
            if ($req.language) { $language = [string]$req.language } else { $language = "python" }
            if ([string]::IsNullOrWhiteSpace($prompt)) { Send-Error $Stream 400 "prompt required"; return $true }
            $code = Get-AIResponse -Prompt "code $language : $prompt"
            Invoke-RecordStat -Model "zb-code-v1" -Tokens $code.Length -Endpoint "code"
            Add-CodeHistory -User ($(if($auth.sub){$auth.sub}else{'anonymous'})) -Language $language -Prompt $prompt -Code $code -Endpoint "/api/code"
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                id="code_$(Get-Random -Min 100000 -Max 999999)"; language=$language; code=$code; timestamp=(Get-Date).ToString("o")
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    if ($Path -eq "/api/analyze" -and $Method -eq "POST") {
        try {
            if ($quotaExceeded) { Send-Error $Stream 429 "quota exceeded"; return $true }
            $req = $Body | ConvertFrom-Json
            if ($req.task) { $task = [string]$req.task } else { $task = "general" }
            if ($req.data_description) { $desc = [string]$req.data_description } else { $desc = "" }
            $insights = Get-AIResponse -Prompt "data $task : $desc"
            Invoke-RecordStat -Model "zb-large-v1" -Tokens $insights.Length -Endpoint "analyze"
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                id="ana_$(Get-Random -Min 100000 -Max 999999)"; task=$task; insights=$insights;
                confidence=[Math]::Round((Get-Random -Min 75 -Max 98) / 100.0, 2); timestamp=(Get-Date).ToString("o")
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # --- Image Gen ---
    if ($Path -eq "/api/image" -and $Method -eq "POST") {
        try {
            if ($quotaExceeded) { Send-Error $Stream 429 "quota exceeded"; return $true }
            $req = $Body | ConvertFrom-Json
            if ($req.prompt) { $prompt = [string]$req.prompt } else { $prompt = "abstract art" }
            $svg = New-SvgImage $prompt
            Invoke-RecordStat -Model "zb-image-v1" -Tokens $prompt.Length -Endpoint "image"
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                id="img_$(Get-Random -Min 100000 -Max 999999)"; prompt=$prompt; svg=$svg;
                url="/api/image/view/$($prompt.Length)"; timestamp=(Get-Date).ToString("o")
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # --- Sessions CRUD ---
    if ($Path -eq "/api/sessions" -and $Method -eq "GET") {
        $sessions = @(Load-Sessions $auth.sub)
        $summary = @()
        foreach ($s in $sessions) {
            $summary += [pscustomobject]@{ id=$s.id; title=$s.title; messages_count=$s.messages.Count; created_at=$s.created_at; updated_at=$s.updated_at }
        }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ sessions=$summary }; return $true
    }
    if ($Path -eq "/api/sessions" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            if ($req.title) { $title = [string]$req.title } else { $title = "New Chat" }
            $sid = "sess_$(Get-Random -Min 100000 -Max 999999)"
            $sess = [pscustomobject]@{ id=$sid; title=$title; messages=@(); created_at=(Get-Date).ToString("o"); updated_at=(Get-Date).ToString("o") }
            Save-Session $auth.sub $sess
            Send-Json -Stream $Stream -StatusCode 201 -Data $sess
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }
    if ($Path -match "^/api/sessions/(.+)$" -and $Method -eq "GET") {
        $sid = $Matches[1]
        $sessions = @(Load-Sessions $auth.sub)
        $sess = $sessions | Where-Object { $_.id -eq $sid } | Select-Object -First 1
        if (-not $sess) { Send-Error $Stream 404 "session not found"; return $true }
        Send-Json -Stream $Stream -StatusCode 200 -Data $sess; return $true
    }
    if ($Path -match "^/api/sessions/(.+)$" -and $Method -eq "PUT") {
        try {
            $sid = $Matches[1]; $req = $Body | ConvertFrom-Json
            $sessions = @(Load-Sessions $auth.sub)
            $sess = $sessions | Where-Object { $_.id -eq $sid } | Select-Object -First 1
            if (-not $sess) { Send-Error $Stream 404 "session not found"; return $true }
            if ($req.title) { $sess.title = [string]$req.title }
            $sess.updated_at = (Get-Date).ToString("o")
            Save-Session $auth.sub $sess
            Send-Json -Stream $Stream -StatusCode 200 -Data $sess
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }
    if ($Path -match "^/api/sessions/(.+)$" -and $Method -eq "DELETE") {
        $sid = $Matches[1]; $null = Delete-Session $auth.sub $sid
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ deleted=$sid }; return $true
    }

    # --- Admin ---
    if ($Path -match "^/api/admin" -and $auth.role -ne "admin") { Send-Error $Stream 403 "admin only"; return $true }
    if ($Path -eq "/api/admin/stats") {
        $stats = Get-Content $STATS_FILE -Raw | ConvertFrom-Json
        $users = Load-Users
        $stats | Add-Member -NotePropertyName total_users -NotePropertyValue $users.Count
        $stats | Add-Member -NotePropertyName non_admin_users -NotePropertyValue @($users | Where-Object { $_.role -ne "admin" }).Count
        Send-Json -Stream $Stream -StatusCode 200 -Data $stats; return $true
    }
    if ($Path -eq "/api/admin/users") {
        $users = Load-Users
        $safe = @()
        foreach ($u in $users) { $safe += [pscustomobject]@{ username=$u.username; role=$u.role; email=$u.email; api_key=$u.api_key; quota_tokens=$u.quota_tokens; created_at=$u.created_at } }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ users=$safe; total=$safe.Count }; return $true
    }
    if ($Path -match "^/api/admin/users/(.+)/quota$" -and $Method -eq "POST") {
        try {
            $tgt = $Matches[1]; $req = $Body | ConvertFrom-Json
            $newQuota = [int]$req.quota_tokens
            $users = Load-Users
            $updated = $false
            foreach ($u in $users) { if ($u.username -eq $tgt) { $u.quota_tokens = $newQuota; $updated = $true } }
            if (-not $updated) { Send-Error $Stream 404 "user not found"; return $true }
            Save-Users $users
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ username=$tgt; quota_tokens=$newQuota }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # ================================================================
    # --- ZBpay Payment System ---
    # ================================================================

    # Public: product catalog
    if ($Path -eq "/api/pay/pricing" -and $Method -eq "GET") {
        $products = @()
        foreach ($p in $PAY_PRODUCTS) {
            $products += [pscustomobject]@{
                id=$p.id; name=$p.name; amount=$p.amount; quota_tokens=$p.quota;
                interval=$p.interval; tag=$p.tag; description=$p.desc
            }
        }
        # ZBpay 充值档位（轨道科普 & 通用）
        $depositPlans = @(
            [pscustomobject]@{ id="deposit_10";  amount=10;  bonus=0;   label="¥10"  },
            [pscustomobject]@{ id="deposit_50";  amount=50;  bonus=2;   label="¥50 送¥2"  },
            [pscustomobject]@{ id="deposit_100"; amount=100; bonus=8;   label="¥100 送¥8" },
            [pscustomobject]@{ id="deposit_300"; amount=300; bonus=30;  label="¥300 送¥30" },
            [pscustomobject]@{ id="deposit_500"; amount=500; bonus=60;  label="¥500 送¥60" },
            [pscustomobject]@{ id="deposit_1000";amount=1000; bonus=150; label="¥1000 送¥150" }
        )
        Send-Json -Stream $Stream -StatusCode 200 -Data @{
            products=$products; yuan_per_1000_tokens=0.001
            zbpay_deposit_plans=$depositPlans
            zbpay_account_name=$PAYEE_BANK.account_name
            zbpay_bank_name=$PAYEE_BANK.bank_name
        }
        return $true
    }

    # Auth-aware helper (inline)
    $payAuth = Get-BasicAuth $AuthHeader
    function Require-PayAuth([System.Net.Sockets.NetworkStream]$S,[object]$A) {
        if (-not $A) { Send-Error $S 401 "authentication required"; return $null }
        return $A
    }

    # Create order (auth)
    if ($Path -eq "/api/pay/orders" -and $Method -eq "POST") {
        $A = Require-PayAuth $Stream $payAuth; if (-not $A) { return $true }
        try {
            $req = $Body | ConvertFrom-Json
            $prodId = [string]$req.product
            if ([string]::IsNullOrWhiteSpace($prodId)) { Send-Error $Stream 400 "product id required"; return $true }
            $product = Get-Product $prodId
            if (-not $product) { Send-Error $Stream 404 "product not found"; return $true }
            $orderId = "ord_$(Get-Random -Min 10000000 -Max 99999999)"
            $orders = Load-Orders
            $orders += [pscustomobject]@{
                order_id=$orderId; username=$A.sub; product_id=$product.id; product_name=$product.name;
                amount=$product.amount; quota_tokens=$product.quota; status="pending";
                created_at=(Get-Date).ToString("o");
                expires_at=([DateTimeOffset]::UtcNow.AddMinutes(30).ToString("o"));
                paid_at=$null; paid_method=$null
            }
            Save-Orders $orders
            Send-Json -Stream $Stream -StatusCode 201 -Data @{
                order_id=$orderId; product=$product; amount=$product.amount;
                status="pending"; expires_at=([DateTimeOffset]::UtcNow.AddMinutes(30).ToString("o"));
                checkout_url="/api/pay/mock-pay?order_id=$orderId"
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # List my orders
    if ($Path -eq "/api/pay/orders" -and $Method -eq "GET") {
        $A = Require-PayAuth $Stream $payAuth; if (-not $A) { return $true }
        $all = Load-Orders
        $mine = @($all | Where-Object { $_.username -eq $A.sub })
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ orders=$mine; total=$mine.Count }
        return $true
    }

    # Get single order
    if ($Path -match "^/api/pay/orders/(\S+)$" -and $Method -eq "GET") {
        $A = Require-PayAuth $Stream $payAuth; if (-not $A) { return $true }
        $oid = $Matches[1]
        $order = @(Load-Orders | Where-Object { $_.order_id -eq $oid })[0]
        if (-not $order) { Send-Error $Stream 404 "order not found"; return $true }
        if ($order.username -ne $A.sub -and $A.role -ne "admin") { Send-Error $Stream 403 "forbidden"; return $true }
        Send-Json -Stream $Stream -StatusCode 200 -Data $order
        return $true
    }

    # Simulate payment (demo)
    if ($Path -eq "/api/pay/mock-pay" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            $oid = [string]$req.order_id
            if ([string]::IsNullOrWhiteSpace($oid)) { Send-Error $Stream 400 "order_id required"; return $true }
            $orders = Load-Orders
            $idx = -1; for ($i=0;$i -lt $orders.Count;$i++) { if ($orders[$i].order_id -eq $oid) { $idx=$i; break } }
            if ($idx -lt 0) { Send-Error $Stream 404 "order not found"; return $true }
            if ($orders[$idx].status -ne "pending") { Send-Error $Stream 400 "order not payable ($($orders[$idx].status))"; return $true }
            $orders[$idx].status = "paid"
            $orders[$idx].paid_at = (Get-Date).ToString("o")
            $orders[$idx].paid_method = "mock_alipay"
            Save-Orders $orders
            Add-UserQuota -Username $orders[$idx].username -Delta ([int]$orders[$idx].quota_tokens) -Reason "pay" | Out-Null
            New-Txn -Username $orders[$idx].username -Type "pay" -Amount ([int]$orders[$idx].amount) -Quota ([int]$orders[$idx].quota_tokens) -Ref $oid -Note "ZhiBei AI pay success"
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                order_id=$oid; status="paid"; quota_credited=$orders[$idx].quota_tokens;
                username=$orders[$idx].username; paid_at=(Get-Date).ToString("o")
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # Webhook (public, simulated)
    if ($Path -eq "/api/pay/webhook" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            if ($req.order_id) { $oid = [string]$req.order_id } else { $oid = [string]$req.out_trade_no }
            if ([string]::IsNullOrWhiteSpace($oid)) { Send-Error $Stream 400 "order_id required"; return $true }
            $orders = Load-Orders
            $idx = -1; for ($i=0;$i -lt $orders.Count;$i++) { if ($orders[$i].order_id -eq $oid) { $idx=$i; break } }
            if ($idx -lt 0) { Send-Error $Stream 404 "order not found"; return $true }
            if ($orders[$idx].status -ne "pending") { Send-Json -Stream $Stream 200 -Data @{ received=$oid; already_processed=$true }; return $true }
            $orders[$idx].status = "paid"
            $orders[$idx].paid_at = (Get-Date).ToString("o")
            $orders[$idx].paid_method = [string]($req.pay_method)
            Save-Orders $orders
            Add-UserQuota -Username $orders[$idx].username -Delta ([int]$orders[$idx].quota_tokens) -Reason "webhook" | Out-Null
            New-Txn -Username $orders[$idx].username -Type "pay" -Amount ([int]$orders[$idx].amount) -Quota ([int]$orders[$idx].quota_tokens) -Ref $oid -Note "Webhook callback"
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ received=$oid; status="ok" }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # Recharge log
    if ($Path -eq "/api/pay/recharge-log" -and $Method -eq "GET") {
        $A = Require-PayAuth $Stream $payAuth; if (-not $A) { return $true }
        $txns = @(Load-Transactions | Where-Object { $_.username -eq $A.sub } | Sort-Object created_at -Descending)
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ transactions=$txns; total=$txns.Count }
        return $true
    }

    # Refund
    if ($Path -match "^/api/pay/orders/(\S+)/refund$" -and $Method -eq "POST") {
        $A = Require-PayAuth $Stream $payAuth; if (-not $A) { return $true }
        $oid = $Matches[1]
        $orders = Load-Orders
        $idx = -1; for ($i=0;$i -lt $orders.Count;$i++) { if ($orders[$i].order_id -eq $oid) { $idx=$i; break } }
        if ($idx -lt 0) { Send-Error $Stream 404 "order not found"; return $true }
        if ($orders[$idx].username -ne $A.sub -and $A.role -ne "admin") { Send-Error $Stream 403 "forbidden"; return $true }
        if ($orders[$idx].status -ne "paid") { Send-Error $Stream 400 "only paid orders can be refunded"; return $true }
        $orders[$idx].status = "refunded"
        Save-Orders $orders
        Add-UserQuota -Username $orders[$idx].username -Delta (-[int]$orders[$idx].quota_tokens) -Reason "refund" | Out-Null
        New-Txn -Username $orders[$idx].username -Type "refund" -Amount (-[int]$orders[$idx].amount) -Quota (-[int]$orders[$idx].quota_tokens) -Ref $oid -Note "User refund"
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ order_id=$oid; status="refunded"; quota_deducted=$orders[$idx].quota_tokens }
        return $true
    }

    # --- Admin Rail Activation Codes ---
    if ($Path -match "^/api/admin/rail/codes") {
        if ($auth.role -ne "admin") { Send-Error $Stream 403 "admin only"; return $true }
        $codesData = Load-RailCodes

        # GET 列表 + 统计
        if ($Path -eq "/api/admin/rail/codes") {
            $all = @($codesData.codes)
            $avail = @($all | Where-Object { $_.status -eq "available" }).Count
            $sold  = @($all | Where-Object { $_.status -eq "sold" }).Count
            $used  = @($all | Where-Object { $_.status -eq "used" }).Count
            # 分页/搜索参数
            if ($Query.ContainsKey("status")) { $filter = $Query["status"] } else { $filter = $null }
            if ($Query.ContainsKey("q")) { $keyword = $Query["q"].ToString().ToUpper() } else { $keyword = $null }
            if ($Query.ContainsKey("page")) { $page = [int]$Query["page"] } else { $page = 1 }
            if ($Query.ContainsKey("size")) { $pageSize = [int]$Query["size"] } else { $pageSize = 50 }
            $filtered = $all
            if ($filter) { $filtered = @($filtered | Where-Object { $_.status -eq $filter }) }
            if ($keyword) { $filtered = @($filtered | Where-Object { $_.code -like "*$keyword*" -or $_.batch -like "*$keyword*" -or $_.used_by -like "*$keyword*" }) }
            $total = $filtered.Count
            $paged = @($filtered | Select-Object -First $pageSize -Skip (($page-1)*$pageSize))
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                total=$codesData.total; version=$codesData.version
                stats=[pscustomobject]@{ available=$avail; sold=$sold; used=$used }
                filtered_total=$total; page=$page; page_size=$pageSize
                codes=$paged
            }
            return $true
        }

        # POST 批量导入（admin 粘贴）
        if ($Path -eq "/api/admin/rail/codes/import" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $rawList = [string]$req.codes_text
                $batchTag = [string]$req.batch  # 批次标签
                if ([string]::IsNullOrWhiteSpace($rawList)) { Send-Error $Stream 400 "codes_text 不能为空"; return $true }
                $lines = $rawList -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' }
                $priceMap = @{ "unit"=89; "part"=9; "lesson"=1 }
                if ([string]::IsNullOrWhiteSpace($batchTag)) { $batchTag = "admin-import-" + (Get-Date -Format "yyyyMMddHHmm") }
                $added = 0; $skipped = 0
                foreach($line in $lines){
                    $code = ($line -replace '\s+','' -replace '[:\-]+','').ToUpper()
                    if (-not $code.StartsWith("ZB-")) { $code = "ZB-" + $code }
                    # Skip duplicates
                    $dup = @($codesData.codes | Where-Object { $_.code -eq $code })
                    if ($dup.Count -gt 0) { $skipped++; continue }
                    if ($req.price) { $importPrice = [int]$req.price } else { $importPrice = $null }
                    $codesData.codes += [pscustomobject]@{
                        code=$code; status="available"; target_kind=$null; target_id=$null
                        price=$importPrice
                    }
                    $added++
                }
                $codesData.total = @($codesData.codes).Count
                Save-RailCodes $codesData
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ added=$added; skipped=$skipped; batch=$batchTag }
                return $true
            } catch { Send-Error $Stream 400 "import failed: $($_.Exception.Message)"; return $true }
        }

        # POST 标记已售
        if ($Path -match '^/api/admin/rail/codes/mark-sold$' -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $code = [string]$req.code
                if ([string]::IsNullOrWhiteSpace($code)) { Send-Error $Stream 400 "code required"; return $true }
                $code = ($code -replace '\s+','' -replace '[:\-]+','').ToUpper()
                if (-not $code.StartsWith("ZB-")) { $code = "ZB-" + $code }
                $found = $false
                foreach($c in @($codesData.codes)){ if($c.code -eq $code){ $c.status="sold"; $found=$true; break } }
                if (-not $found) { Send-Error $Stream 404 "激活码不存在"; return $true }
                Save-RailCodes $codesData
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; code=$code; new_status="sold" }
                return $true
            } catch { Send-Error $Stream 400 "$($_.Exception.Message)"; return $true }
        }

        # POST 重置为 available（used/sold → available，used_by 清空）
        if ($Path -match '^/api/admin/rail/codes/reset$' -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $code = [string]$req.code
                $code = ($code -replace '\s+','' -replace '[:\-]+','').ToUpper()
                if (-not $code.StartsWith("ZB-")) { $code = "ZB-" + $code }
                $found = $false
                foreach($c in @($codesData.codes)){
                    if($c.code -eq $code){
                        $c.status="available"; $c.used_by=$null; $c.used_at=$null; $found=$true; break
                    }
                }
                if (-not $found) { Send-Error $Stream 404 "激活码不存在"; return $true }
                Save-RailCodes $codesData
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; code=$code; new_status="available" }
                return $true
            } catch { Send-Error $Stream 400 "$($_.Exception.Message)"; return $true }
        }

        # POST 标记目标（admin 指定激活码解锁什么）
        if ($Path -match '^/api/admin/rail/codes/set-target$' -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $code = [string]$req.code
                $code = ($code -replace '\s+','' -replace '[:\-]+','').ToUpper()
                if (-not $code.StartsWith("ZB-")) { $code = "ZB-" + $code }
                $tk = [string]$req.target_kind
                $tid = [string]$req.target_id
                if ($req.price) { $price = [int]$req.price } else { $price = 0 }
                $found = $false
                foreach($c in @($codesData.codes)){
                    if($c.code -eq $code){
                        $c.target_kind=$tk; $c.target_id=$tid; $c.price=$price; $found=$true; break
                    }
                }
                if (-not $found) { Send-Error $Stream 404 "激活码不存在"; return $true }
                Save-RailCodes $codesData
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; code=$code; target_kind=$tk; target_id=$tid; price=$price }
                return $true
            } catch { Send-Error $Stream 400 "$($_.Exception.Message)"; return $true }
        }

        # POST 删除激活码（只能手动）
        if ($Path -match '^/api/admin/rail/codes/delete$' -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $code = [string]$req.code
                $code = ($code -replace '\s+','' -replace '[:\-]+','').ToUpper()
                if (-not $code.StartsWith("ZB-")) { $code = "ZB-" + $code }
                $before = @($codesData.codes).Count
                $codesData.codes = @($codesData.codes | Where-Object { $_.code -ne $code })
                $after = @($codesData.codes).Count
                $codesData.total = $after
                if ($before -eq $after) { Send-Error $Stream 404 "激活码不存在"; return $true }
                Save-RailCodes $codesData
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; deleted=$code; remaining=$after }
                return $true
            } catch { Send-Error $Stream 400 "$($_.Exception.Message)"; return $true }
        }

        # GET 激活码详情（单条）
        if ($Path -match '^/api/admin/rail/codes/([A-Z0-9\-]+)$') {
            $code = $Matches[1].ToUpper()
            $entry = Get-RailCode $code $codesData
            if (-not $entry) { Send-Error $Stream 404 "激活码不存在"; return $true }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ code=$entry }
            return $true
        }

        Send-Error $Stream 404 "admin rail code endpoint not found"
        return $true
    }

    # --- Admin Code Management ---
    if ($Path -match "^/api/admin/code") {
        if ($auth.role -ne "admin") { Send-Error $Stream 403 "admin only"; return $true }

        # ========== 1. Code Templates CRUD ==========
        if ($Path -eq "/api/admin/code/templates" -and $Method -eq "GET") {
            $data = Load-CodeTemplates
            if ($Query.ContainsKey("language")) { $filter = $Query["language"] } else { $filter = $null }
            $list = @($data.templates)
            if ($filter) { $list = @($list | Where-Object { $_.language -eq $filter }) }
            $languages = @($data.templates | ForEach-Object { $_.language } | Sort-Object -Unique)
            $categories = @($data.templates | ForEach-Object { $_.category } | Sort-Object -Unique)
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ templates=$list; total=$list.Count; languages=$languages; categories=$categories }
            return $true
        }
        if ($Path -eq "/api/admin/code/templates" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                if ($req.id) { $tplId = [string]$req.id } else { $tplId = $null }
                if ($req.description) { $tplDesc = [string]$req.description } else { $tplDesc = $null }
                if ($req.category) { $tplCat = [string]$req.category } else { $tplCat = $null }
                $tpl = [pscustomobject]@{
                    id=$tplId; name=[string]$req.name; language=[string]$req.language
                    description=$tplDesc; category=$tplCat
                    code = [string]$req.code
                    updated_at = (Get-Date).ToString("o")
                }
                $data = Load-CodeTemplates
                $data.templates = @($data.templates)
                # check duplicate id
                foreach ($t in $data.templates) { if ($t.id -eq $tpl.id) { Send-Error $Stream 409 "template id exists"; return $true } }
                $data.templates += $tpl
                Save-CodeTemplates $data
                Send-Json -Stream $Stream -StatusCode 201 -Data $tpl
                return $true
            } catch { Send-Error $Stream 400 "template create failed: $($_.Exception.Message)"; return $true }
        }
        if ($Path -match '^/api/admin/code/templates/([^/]+)$' -and $Method -eq "GET") {
            $tid = $Matches[1]
            $data = Load-CodeTemplates
            $tpl = @($data.templates | Where-Object { $_.id -eq $tid } | Select-Object -First 1)
            if (-not $tpl) { Send-Error $Stream 404 "template not found"; return $true }
            Send-Json -Stream $Stream -StatusCode 200 -Data $tpl[0]; return $true
        }
        if ($Path -match '^/api/admin/code/templates/([^/]+)$' -and $Method -eq "PUT") {
            try {
                $tid = $Matches[1]; $req = $Body | ConvertFrom-Json
                $data = Load-CodeTemplates; $found = $false
                foreach ($t in @($data.templates)) {
                    if ($t.id -eq $tid) {
                        if ($req.name) { $t.name = [string]$req.name }
                        if ($req.language) { $t.language = [string]$req.language }
                        if ($null -ne $req.description) { $t.description = [string]$req.description }
                        if ($req.category) { $t.category = [string]$req.category }
                        if ($req.code) { $t.code = [string]$req.code }
                        $t.updated_at = (Get-Date).ToString("o")
                        $found = $true; break
                    }
                }
                if (-not $found) { Send-Error $Stream 404 "template not found"; return $true }
                Save-CodeTemplates $data
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; id=$tid }
                return $true
            } catch { Send-Error $Stream 400 "$($_.Exception.Message)"; return $true }
        }
        if ($Path -match '^/api/admin/code/templates/([^/]+)$' -and $Method -eq "DELETE") {
            $tid = $Matches[1]
            $data = Load-CodeTemplates
            $before = @($data.templates).Count
            $data.templates = @($data.templates | Where-Object { $_.id -ne $tid })
            if (@($data.templates).Count -eq $before) { Send-Error $Stream 404 "template not found"; return $true }
            Save-CodeTemplates $data
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; deleted=$tid }; return $true
        }

        # ========== 2. Code Generation History ==========
        if ($Path -eq "/api/admin/code/history" -and $Method -eq "GET") {
            $data = Load-CodeHistory
            $all = @($data.history)
            if ($Query.ContainsKey("language")) { $filter = $Query["language"] } else { $filter = $null }
            if ($Query.ContainsKey("user"))     { $userQ = $Query["user"] }     else { $userQ = $null }
            if ($Query.ContainsKey("q"))        { $kwQ = $Query["q"].ToString().ToLower() } else { $kwQ = $null }
            if ($Query.ContainsKey("page"))    { $page = [int]$Query["page"] }    else { $page = 1 }
            if ($Query.ContainsKey("size"))    { $size = [int]$Query["size"] }    else { $size = 20 }
            if ($filter) { $all = @($all | Where-Object { $_.language -eq $filter }) }
            if ($userQ)  { $all = @($all | Where-Object { $_.user -eq $userQ }) }
            if ($kwQ)    { $all = @($all | Where-Object { $_.prompt.ToLower() -like "*$kwQ*" -or $_.id.ToLower() -like "*$kwQ*" }) }
            $total = $all.Count
            $paged = @($all | Select-Object -First $size -Skip (($page-1)*$size))
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                history=$paged; total=$total; page=$page; page_size=$size
                languages=@($data.history | ForEach-Object { $_.language } | Sort-Object -Unique)
                users=@($data.history | ForEach-Object { $_.user } | Sort-Object -Unique)
            }
            return $true
        }
        if ($Path -eq "/api/admin/code/history/bulk-delete" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $ids = @($req.ids)
                if ($ids.Count -eq 0) { Send-Error $Stream 400 "ids array required"; return $true }
                $data = Load-CodeHistory
                $before = @($data.history).Count
                $data.history = @($data.history | Where-Object { $ids -notcontains $_.id })
                Save-CodeHistory $data
                $removed = $before - @($data.history).Count
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; removed=$removed }
                return $true
            } catch { Send-Error $Stream 400 "$($_.Exception.Message)"; return $true }
        }
        if ($Path -match '^/api/admin/code/history/([A-Za-z0-9_\-]+)$' -and $Method -eq "DELETE") {
            $hid = $Matches[1]; $data = Load-CodeHistory
            $before = @($data.history).Count
            $data.history = @($data.history | Where-Object { $_.id -ne $hid })
            Save-CodeHistory $data
            if (@($data.history).Count -eq $before) { Send-Error $Stream 404 "history entry not found"; return $true }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok" }; return $true
        }

        # ========== 3. Code Sandbox Exec ==========
        if ($Path -eq "/api/admin/code/exec" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $lang = [string]$req.language
                $code = [string]$req.code
                if ([string]::IsNullOrWhiteSpace($code)) { Send-Error $Stream 400 "code required"; return $true }
                if ([string]::IsNullOrWhiteSpace($lang)) { $lang = "powershell" }
                $elapsed = [math]::Round(((Get-Date).Ticks - [datetime]'2026-11-01').TotalMilliseconds)
                $result = Invoke-CodeSandbox -Language $lang -Code $code
                if (-not $result) { $result = [pscustomobject]@{ exit_code=-3; stdout=""; stderr="Invoke-CodeSandbox returned null"; elapsed_ms=0 } }
                Send-Json -Stream $Stream -StatusCode 200 -Data @{
                    exit_code=$result.exit_code; stdout=$result.stdout; stderr=$result.stderr
                    elapsed_ms=$result.elapsed_ms; language=$lang
                    sandbox = [pscustomobject]@{
                        powershell = [bool](Get-Command powershell -EA SilentlyContinue)
                        python     = [bool](Get-Command python -EA SilentlyContinue -or (Get-Command python3 -EA SilentlyContinue))
                        node       = [bool](Get-Command node -EA SilentlyContinue)
                    }
                }
                return $true
            } catch { Send-Error $Stream 400 "exec failed: $($_.Exception.Message)"; return $true }
        }

        # ========== 4. System File Browser (安全限制 workspace) ==========
        if ($Path -eq "/api/admin/code/files" -and $Method -eq "GET") {
            try {
                if ($Query.ContainsKey("path")) { $rel = [string]$Query["path"] } else { $rel = "" }
                # 安全：规范化路径，禁止 .. 跳出 workspace
                $full = Join-Path $SCRIPT_ROOT $rel
                $norm = [System.IO.Path]::GetFullPath($full)
                $root = [System.IO.Path]::GetFullPath($SCRIPT_ROOT)
                if (-not $norm.StartsWith($root)) { Send-Error $Stream 403 "path escapes workspace"; return $true }
                if (-not (Test-Path $norm)) { Send-Error $Stream 404 "not found"; return $true }
                if ((Get-Item $norm).PSIsContainer) {
                    $items = Get-ChildItem $norm -Force | Select-Object Name, FullName, PSIsContainer, Length, LastWriteTime
                    $data = @($items | ForEach-Object {
                        if ($_.PSIsContainer) { $fsize = $null } else { $fsize = $_.Length }
                        [pscustomobject]@{
                            size=$fsize
                            modified=$_.LastWriteTime.ToString("o")
                        }
                    })
                    if ($rel) { $dirPath = $rel; $dirParent = [IO.Path]::GetDirectoryName($rel) } else { $dirPath = $null; $dirParent = $null }
                    Send-Json -Stream $Stream -StatusCode 200 -Data @{
                        path=$dirPath; parent=$dirParent
                        items=$data; total=$data.Count; is_dir=$true
                    }
                } else {
                    $content = [IO.File]::ReadAllText($norm)
                    $lines = ($content -split "`r?`n").Count
                    $ext = [IO.Path]::GetExtension($norm).TrimStart(".")
                    $size = (Get-Item $norm).Length
                    if ($rel) { $fPath = $rel } else { $fPath = $null }
                    Send-Json -Stream $Stream -StatusCode 200 -Data @{
                        path=$fPath
                        name=[IO.Path]::GetFileName($norm); ext=$ext; size=$size; lines=$lines
                        content=$content; is_dir=$false
                    }
                }
                return $true
            } catch { Send-Error $Stream 400 "$($_.Exception.Message)"; return $true }
        }
        if ($Path -eq "/api/admin/code/save" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $rel = [string]$req.path; $content = [string]$req.content
                if ([string]::IsNullOrWhiteSpace($rel)) { Send-Error $Stream 400 "path required"; return $true }
                $full = Join-Path $SCRIPT_ROOT $rel
                $norm = [System.IO.Path]::GetFullPath($full)
                $root = [System.IO.Path]::GetFullPath($SCRIPT_ROOT)
                if (-not $norm.StartsWith($root)) { Send-Error $Stream 403 "path escapes workspace"; return $true }
                # 禁止保存到 data 目录和 .git 目录（保护敏感数据）
                $dataDir = Join-Path $root "data"; $gitDir = Join-Path $root ".git"
                if ($norm.StartsWith([System.IO.Path]::GetFullPath($dataDir)) -or $norm.StartsWith([System.IO.Path]::GetFullPath($gitDir))) {
                    Send-Error $Stream 403 "cannot save to data/ or .git/ directory"; return $true
                }
                $enc = New-Object System.Text.UTF8Encoding($true)  # 带 BOM
                [IO.File]::WriteAllText($norm, $content, $enc)
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; path=$rel; size=$content.Length; saved_at=(Get-Date).ToString("o") }
                return $true
            } catch { Send-Error $Stream 400 "save failed: $($_.Exception.Message)"; return $true }
        }

        Send-Error $Stream 404 "admin code endpoint not found"
        return $true
    }

    # --- Admin Mock Whitelist (SMS/Email MOCK authorization) ---
    if ($Path -match "^/api/admin/mock-whitelist") {
        if ($auth.role -ne "admin") { Send-Error $Stream 403 "admin only"; return $true }
        if ($Path -eq "/api/admin/mock-whitelist" -and $Method -eq "GET") {
            $myIPs = @(Get-MyIPs)
            $enabledIPs = @($myIPs + $script:MOCK_WHITELIST | Select-Object -Unique)
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                whitelist = @($script:MOCK_WHITELIST)
                local_ips = $myIPs
                enabled_ips = $enabledIPs
                mock_enabled = $true
                note = "MOCK SMS/Email requires client IP in local_ips OR admin whitelist. Local IPs auto-allowed."
            }
            return $true
        }
        if ($Path -match '^/api/admin/mock-whitelist/add$' -and $Method -eq "POST") {
            $req = $Body | ConvertFrom-Json
            $ip = [string]$req.ip
            if (-not $ip) { Send-Error $Stream 400 "ip required"; return $true }
            # Simple IP validation
            if ($ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                Send-Error $Stream 400 "invalid IP format"; return $true
            }
            if ($script:MOCK_WHITELIST -notcontains $ip) {
                $script:MOCK_WHITELIST += $ip
                Save-MockWhitelist
            }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ whitelist = @($script:MOCK_WHITELIST); added=$ip }
            return $true
        }
        if ($Path -match '^/api/admin/mock-whitelist/remove$' -and $Method -eq "POST") {
            $req = $Body | ConvertFrom-Json
            $ip = [string]$req.ip
            if (-not $ip) { Send-Error $Stream 400 "ip required"; return $true }
            $script:MOCK_WHITELIST = @($script:MOCK_WHITELIST | Where-Object { $_ -ne $ip })
            Save-MockWhitelist
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ whitelist = @($script:MOCK_WHITELIST); removed=$ip }
            return $true
        }
        Send-Error $Stream 404 "mock-whitelist endpoint not found"
        return $true
    }

    # --- Admin Pay ---
    if ($Path -match "^/api/pay/admin" -and $payAuth.role -ne "admin") { Send-Error $Stream 403 "admin only"; return $true }
    if ($Path -eq "/api/pay/admin/all-orders") {
        $all = Load-Orders
        $all = @($all | Sort-Object created_at -Descending)
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ orders=$all; total=$all.Count }
        return $true
    }
    if ($Path -eq "/api/pay/admin/revenue") {
        $all = Load-Orders
        $paid = @($all | Where-Object { $_.status -eq "paid" })
        $refunded = @($all | Where-Object { $_.status -eq "refunded" })
        $pending = @($all | Where-Object { $_.status -eq "pending" })
        $totalRev = 0; foreach ($o in $paid) { $totalRev += [int]$o.amount }
        $refundRev = 0; foreach ($o in $refunded) { $refundRev += [int]$o.amount }
        $byProduct = @{}
        foreach ($o in $paid) {
            if (-not $byProduct.ContainsKey($o.product_id)) { $byProduct[$o.product_id] = [pscustomobject]@{ product_id=$o.product_id; count=0; revenue=0; quota=0 } }
            $byProduct[$o.product_id].count++
            $byProduct[$o.product_id].revenue += [int]$o.amount
            $byProduct[$o.product_id].quota += [int]$o.quota_tokens
        }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{
            total_revenue=$totalRev; refunded_revenue=$refundRev; net_revenue=($totalRev-$refundRev);
            orders=@{ paid=$paid.Count; refunded=$refunded.Count; pending=$pending.Count; total=$all.Count }
            by_product=@($byProduct.Values)
        }
        return $true
    }
    if ($Path -eq "/api/pay/admin/manual-credit" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            $target = [string]$req.username; $quota = [int]$req.quota_tokens;if ($req.note) { $note = [string]$req.note } else { $note = "admin manual credit" }
            if ([string]::IsNullOrWhiteSpace($target) -or $quota -eq 0) { Send-Error $Stream 400 "username and non-zero quota_tokens required"; return $true }
            $ok = Add-UserQuota -Username $target -Delta $quota -Reason "admin"
            if (-not $ok) { Send-Error $Stream 404 "user not found"; return $true }
            New-Txn -Username $target -Type "admin_credit" -Amount 0 -Quota $quota -Ref "admin_$(Get-Random)" -Note $note
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ username=$target; quota_added=$quota }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }

    # --- Enterprise Admin ---
    if ($Path -match "^/api/ent" -and $auth.role -ne "admin") { Send-Error $Stream 403 "admin only"; return $true }

    # Dashboard overview
    if ($Path -eq "/api/ent/dashboard") {
        if (Test-Path $ENT_EMP_FILE) { $em = @((Get-Content $ENT_EMP_FILE -Raw | ConvertFrom-Json).employees) } else { $em = @() }
        if (Test-Path $ENT_DEPT_FILE) { $de = @((Get-Content $ENT_DEPT_FILE -Raw | ConvertFrom-Json).departments) } else { $de = @() }
        if (Test-Path $STATS_FILE) { $st = Get-Content $STATS_FILE -Raw | ConvertFrom-Json }
        $today = (Get-Date).ToString("yyyy-MM-dd")
        # AI usage trend 7 days
        $trend = @()
        for ($d = 6; $d -ge 0; $d--) {
            $dt = (Get-Date).AddDays(-$d).ToString("yyyy-MM-dd")
if ($st.daily -and $st.daily.PSObject.Properties[$dt]) { $cnt = $st.daily.$dt.calls } else { $cnt = Get-Random -Min 400 -Max 2000 }
            $trend += @{ date=$dt; calls=$cnt }
        }
        # AI model distribution (mocked)
        $models = @(
            @{ name="ZB-Large-v1"; calls=4821; pct=48 },
            @{ name="ZB-Turbo-v1"; calls=2910; pct=29 },
            @{ name="ZB-Code-v1"; calls=1580; pct=16 },
            @{ name="ZB-Image-v1"; calls=756; pct=7 }
        )
        Send-Json -Stream $Stream -StatusCode 200 -Data @{
            company_name="智北智能轨道交通有限公司"
            company_id="F7AZLB6AD03"
            plan_name="Pro Annual"
            plan_version="E3"
            next_billing_date=(Get-Date).AddDays(180).ToString("yyyy-MM-dd")
            active_employees=@($em | Where-Object { $_.status -eq "active" }).Count
            total_employees=$em.Count
            total_departments=$de.Count
            ai_calls_today=1234
            ai_tokens_today=5800000
            ai_usage_trend=$trend
            ai_model_distribution=$models
            token_quota_total=36000000
            token_quota_used=12450000
            token_quota_remaining=23550000
            departments=$de
        }
        return $true
    }

    # Departments
    if ($Path -eq "/api/ent/departments") {if (Test-Path $ENT_DEPT_FILE) { $de = @((Get-Content $ENT_DEPT_FILE -Raw | ConvertFrom-Json).departments) } else { $de = @() }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ departments=$de }
        return $true
    }

    # Employees
    if ($Path -eq "/api/ent/employees") {
        if (Test-Path $ENT_EMP_FILE) { $em = @((Get-Content $ENT_EMP_FILE -Raw | ConvertFrom-Json).employees) } else { $em = @() }
        if (Test-Path $ENT_DEPT_FILE) { $de = @((Get-Content $ENT_DEPT_FILE -Raw | ConvertFrom-Json).departments) } else { $de = @() }
        $lookup = @{}; foreach ($d in $de) { $lookup[$d.id] = $d.name }
        $withDept = @()
        foreach ($e in $em) {
            if ($e.department_id -and $lookup.ContainsKey($e.department_id)) { $dn = $lookup[$e.department_id] } else { $dn = "-" }
            $withDept += [pscustomobject]@{ id=$e.id; name=$e.name; position=$e.position; department=$dn; email=$e.email; phone=$e.phone; status=$e.status; join_date=$e.join_date; role=$e.role }
        }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ employees=$withDept; total=$withDept.Count; active=@($withDept | Where-Object { $_.status -eq "active" }).Count }
        return $true
    }

    # Audit logs
    if ($Path -eq "/api/ent/audit-logs") {if (Test-Path $ENT_LOG_FILE) { $lg = @((Get-Content $ENT_LOG_FILE -Raw | ConvertFrom-Json).logs) } else { $lg = @() }
        $all = @($lg | Sort-Object time -Descending)
        # Pad with some extra demo logs if short
        if ($all.Count -lt 20) {
            for ($i = $all.Count; $i -lt 20; $i++) {
                $actors = @("admin","admin","张明","赵磊","system")
                $actions = @("访问控制台","创建工单","审批流程","查看数据报表","配置AI模型","修改安全策略","导出审计日志","新增应用")
                $actor = $actors[(Get-Random -Min 0 -Max $actors.Count)]
                $act = $actions[(Get-Random -Min 0 -Max $actions.Count)]
                if ($act -match "审批|导出|策略") { $sev = "warning" } else { $sev = "info" }
                $all = @([pscustomobject]@{ id="log_$(Get-Random -Min 1000 -Max 9999)"; time=(Get-Date).AddMinutes(-(Get-Random -Min 10 -Max 1440)).ToString("o"); actor=$actor; action=$act; target="auto_gen_$i"; severity=$sev }) + $all
            }
        }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ logs=$all; total=$all.Count }
        return $true
    }

    # Apps / integrations
    if ($Path -eq "/api/ent/apps") {
        Send-Json -Stream $Stream -StatusCode 200 -Data @{
            apps=@(
                @{ id="a1"; name="飞书协作"; type="IM"; status="enabled"; users=89; last_active="2026-10-31"; icon="💬" },
                @{ id="a2"; name="ZB-AI 大模型"; type="AI"; status="enabled"; users=76; last_active="2026-10-31"; icon="🤖" },
                @{ id="a3"; name="钉钉集成"; type="IM"; status="disabled"; users=0; last_active="2026-09-15"; icon="🔔" },
                @{ id="a4"; name="企业微信"; type="IM"; status="enabled"; users=42; last_active="2026-10-30"; icon="💼" },
                @{ id="a5"; name="智能客服机器人"; type="AI"; status="enabled"; users=12; last_active="2026-10-30"; icon="🎧" },
                @{ id="a6"; name="数据报表中心"; type="BI"; status="enabled"; users=34; last_active="2026-10-31"; icon="📊" },
                @{ id="a7"; name="合同电子签"; type="OA"; status="enabled"; users=18; last_active="2026-10-28"; icon="📝" },
                @{ id="a8"; name="GitHub 代码管理"; type="DevOps"; status="enabled"; users=25; last_active="2026-10-31"; icon="🐙" }
            )
        }
        return $true
    }

    # --- ZhiBei Workbench (工作台) ---
    if ($Path -match "^/api/wb") {
        # All wb endpoints require login
        if (-not $auth -or -not $auth.sub) { Send-Error $Stream 401 "login required"; return $true }

        # 首页总览：todos + schedule + messages + docs
        if ($Path -eq "/api/wb/overview") {
if (Test-Path $WB_TODO_FILE) { $wb = Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json }
if (Test-Path $WB_APP_FILE) { $appsData = Get-Content $WB_APP_FILE -Raw | ConvertFrom-Json }
            $now = Get-Date
            $todayStr = $now.ToString("yyyy-MM-dd")
            $todaySchedule = @($wb.schedule | Where-Object { $_.date -eq $todayStr })
            $pendingTodos = @($wb.todos | Where-Object { $_.status -eq "pending" })
            if ($auth.role) { $wbRole = $auth.role } else { $wbRole = "member" }
            if ($now.Hour -lt 11) { $wbGreet = "早上好" } else { $wbGreet = "晚上好" }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                role=$wbRole; greeting=$wbGreet
                date_str=$now.ToString("yyyy年MM月dd日 dddd", [Globalization.CultureInfo]::GetCultureInfo("zh-CN"))
                unread_count=@($wb.messages | Where-Object { $_.unread }).Count
                pending_count=$pendingTodos.Count
                today_meetings=$todaySchedule.Count
                pending_todos=$pendingTodos
                today_schedule=$todaySchedule
                messages=@($wb.messages)
                recent_docs=@($wb.docs)
                quick_apps=@($appsData.apps | Where-Object { $_.quick })
            }
            return $true
        }

        # 应用中心 + AI 模型列表
        if ($Path -eq "/api/wb/apps") {
if (Test-Path $WB_APP_FILE) { $appsData = Get-Content $WB_APP_FILE -Raw | ConvertFrom-Json }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                apps=@($appsData.apps)
                ai_models=@($appsData.ai_models)
            }
            return $true
        }

        # 我的待办
        if ($Path -eq "/api/wb/todos") {
if (Test-Path $WB_TODO_FILE) { $wb = Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ todos=@($wb.todos); total=@($wb.todos).Count; pending=@($wb.todos | Where-Object { $_.status -eq "pending" }).Count }
            return $true
        }

        # 今日日程
        if ($Path -eq "/api/wb/schedule") {
if (Test-Path $WB_TODO_FILE) { $wb = Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ schedule=@($wb.schedule); total=@($wb.schedule).Count }
            return $true
        }

        # 简单搜索（apps + docs）
        if ($Path -eq "/api/wb/search") {
if (Test-Path $WB_TODO_FILE) { $wb = Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json }
if (Test-Path $WB_APP_FILE) { $appsData = Get-Content $WB_APP_FILE -Raw | ConvertFrom-Json }
            if ($Query.ContainsKey('q')) { $q = [string]$Query['q'] } else { $q = "" }
            if (-not [string]::IsNullOrWhiteSpace($q)) {
                $appsData = @($appsData.apps | Where-Object { $_.name -match [regex]::Escape($q) -or $_.desc -match [regex]::Escape($q) })
                $docMatches = @($wb.docs | Where-Object { $_.name -match [regex]::Escape($q) })
            } else {
                $appsData = @()
                $docMatches = @()
            }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ query=$q; apps=@($appsData); docs=@($docMatches) }
            return $true
        }

        Send-Error $Stream 404 "workbench endpoint not found"
        return $true
    }

    # --- Rail Academy (轨道科普) ---
    if ($Path -match "^/api/rail") {
        # 加载 catalog（公开）和 prog（需要时）和 video-meta（lesson 详情用）
if (Test-Path $RAIL_CAT_FILE) { $cat = Get-Content $RAIL_CAT_FILE -Raw -Encoding UTF8 | ConvertFrom-Json }
if (Test-Path $RAIL_PROG_FILE) { $prog = (Get-Content $RAIL_PROG_FILE -Raw | ConvertFrom-Json) }
if ($auth.sub -and $prog.user_prog.PSObject.Properties[$auth.sub]) { $myProg = $prog.user_prog.$($auth.sub) }
        # video-meta 缓存（脚本级变量，首次加载后复用）
        if (-not $script:zbVideoMeta) {
            if (Test-Path $RAIL_VIDEO_META_FILE) {
                try { $script:zbVideoMeta = Get-Content $RAIL_VIDEO_META_FILE -Raw -Encoding UTF8 | ConvertFrom-Json }
                catch { $script:zbVideoMeta = [pscustomobject]@{} }
            } else { $script:zbVideoMeta = [pscustomobject]@{} }
        }

        # ========== 公开端点（无需登录） ==========

        # 完整目录树
        if ($Path -eq "/api/rail/catalog") {
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ meta=$cat.meta; units=$cat.units; prog=($(if($auth.sub){$myProg}else{$null})) }
            return $true
        }

        # 单个单元详情（含 parts/lessons）
        if ($Path -match '^/api/rail/unit/(\d+)$') {
            $no = [int]$Matches[1]
            $u = @($cat.units | Where-Object { $_.no -eq $no })
            if ($u.Count -eq 0) { Send-Error $Stream 404 "unit not found"; return $true }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ unit=$u[0]; prog=($(if($auth.sub){$myProg}else{$null})) }
            return $true
        }

        # 单个 part 详情
        if ($Path -match '^/api/rail/part/(\w+)$') {
            $partId = $Matches[1]
            foreach($u in $cat.units){
                $p = @($u.parts | Where-Object { $_.id -eq $partId })
                if($p.Count -gt 0){
                    $u2 = [pscustomobject]@{ id=$u.id; no=$u.no; name=$u.name; free=$u.free; icon=$u.icon; tag=$u.tag }
                    Send-Json -Stream $Stream -StatusCode 200 -Data @{ unit=$u2; part=$p[0]; prog=($(if($auth.sub){$myProg}else{$null})) }
                    return $true
                }
            }
            Send-Error $Stream 404 "part not found"; return $true
        }

        # 可用的支付方式列表（公开）
        if ($Path -eq "/api/rail/pay-methods") {
            if ($auth.sub) { $balance = Get-ZbBalance $auth.sub } else { $balance = 0 }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                methods = @($RAIL_PAY_METHODS)
                prices  = @($RAIL_PRICE_MAP.GetEnumerator() | ForEach-Object { @{ kind=$_.Key; amount=$_.Value } })
                zbpay_balance = $balance
                payee_bank = (Get-PayeeBankMasked)
            }
            return $true
        }

        # 视频元数据（公开，大文件，直接原始传输避免 depth 限制）
        if ($Path -eq "/api/rail/video-meta") {
            if (Test-Path $RAIL_VIDEO_META_FILE) {
                $raw = [IO.File]::ReadAllText($RAIL_VIDEO_META_FILE)
                Send-JsonRaw -Stream $Stream -RawText $raw -StatusCode 200
            } else {
                Send-Json -Stream $Stream -StatusCode 200 -Data @{}
            }
            return $true
        }

        # 单个 lesson 详情（含 doc_markdown + free/unlocked）——公开访问，免费单元无需登录
        if ($Path -match '^/api/rail/lesson/(\w+)$') {
            $lid = $Matches[1]
            $videoMeta = $null
            if ($script:zbVideoMeta -and $script:zbVideoMeta.PSObject.Properties[$lid]) { $videoMeta = $script:zbVideoMeta.$lid }
            $hasAuth = ($auth.sub -and ($myProg -ne $null))
            foreach($u in $cat.units){
                foreach($p in $u.parts){
                    $l = @($p.lessons | Where-Object { $_.id -eq $lid })
                    if($l.Count -gt 0){
                        $isFreeLesson = [bool]$l[0].free
                        $isFreeUnit = [bool]$u.free
                        $unlocked = $isFreeLesson -or $isFreeUnit
                        if ($hasAuth) {
                            $unlocked = $unlocked -or
                                ($myProg.unlocked_units -contains $u.no) -or
                                ($myProg.unlocked_parts -contains $p.id) -or
                                ($myProg.unlocked_lessons -contains $l[0].id) -or
                                ($auth.role -eq "admin")
                        }
                        Send-Json -Stream $Stream -StatusCode 200 -Data @{
                            lesson=$l[0]; unit=$u.no; unit_name=$u.name; part=$p.no; part_name=$p.name
                            is_free=[bool]$isFreeLesson; unit_free=[bool]$isFreeUnit; unlocked=[bool]$unlocked
                            meta=$cat.meta; video_meta=$videoMeta
                        }
                        return $true
                    }
                }
            }
            Send-Error $Stream 404 "lesson not found"; return $true
        }

        # ========== 以下端点需要登录 ==========
        if (-not $auth.sub) { Send-Error $Stream 401 "login required"; return $true }

        # 我的进度（解锁状态）
        if ($Path -eq "/api/rail/progress") {
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ user=$auth.sub; prog=$myProg; role=$auth.role }
            return $true
        }

        # ========== 完整收款银行卡号 —— 已禁用，任何人都无法查看 ==========
        # 所有接口统一返回只含前 4 位的掩码，完整号仅存在于服务器私有配置中
        if ($Path -eq "/api/rail/bank-reveal-token" -or $Path -eq "/api/rail/bank-card") {
            Send-Error $Stream 403 "出于资金安全考虑，完整卡号不再通过接口暴露，请联系官方客服"; return $true
        }

        # ========== 激活码 Redeem（轨道科普解锁统一入口） ==========
        if ($Path -eq "/api/rail/redeem" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $code = [string]$req.code
                if ([string]::IsNullOrWhiteSpace($code)) { Send-Error $Stream 400 "请输入激活码"; return $true }
                $code = Normalize-RailCode $code

                $err = Redeem-RailCode -Code $code -User $auth.sub
                if ($err) { Send-Error $Stream 400 $err; return $true }

                # 刷新 prog
if (Test-Path $RAIL_PROG_FILE) { $prog2 = (Get-Content $RAIL_PROG_FILE -Raw | ConvertFrom-Json) }
if ($prog2.user_prog.PSObject.Properties[$auth.sub]) { $myProg2 = $prog2.user_prog.$($auth.sub) }
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; code=$code; prog=$myProg2 }
                return $true
            } catch { Send-Error $Stream 400 "redeem failed: $($_.Exception.Message)"; return $true }
        }

        # ========== 轨道课程在线支付订单系列 ==========

        # POST /api/rail/orders — 创建订单
        if ($Path -eq "/api/rail/orders" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $kind = [string]$req.kind             # unit|part|lesson
                $targetId = [string]$req.target_id    # u3 / u3p5 / u3p5l7
                $payMethod = [string]$req.pay_method  # alipay|wechat|bank|zbpay|google|apple

                if (-not @("unit","part","lesson") -contains $kind) { Send-Error $Stream 400 "kind must be unit|part|lesson"; return $true }
                if ([string]::IsNullOrWhiteSpace($targetId)) { Send-Error $Stream 400 "target_id required"; return $true }
                $validIds = @($RAIL_PAY_METHODS | ForEach-Object { $_.id })
                if (-not ($payMethod -in $validIds)) { Send-Error $Stream 400 "invalid pay_method"; return $true }

                # ZBpay 余额：扣余额，立即完成
                $amount = Get-Price $kind
                $orderId = New-OrderId

                if ($payMethod -eq "zbpay") {
                    $bal = Get-ZbBalance $auth.sub
                    if ($bal -lt $amount) { Send-Error $Stream 400 "ZBpay 余额不足，当前 ¥$bal，需 ¥$amount"; return $true }
                    $ok = Deduct-ZbBalance $auth.sub $amount $orderId
                    if (-not $ok) { Send-Error $Stream 400 "余额扣减失败"; return $true }
                }

                # 写订单
                $orders = Load-RailOrders
                $entry = [pscustomobject]@{
                    order_id = $orderId
                    username = $auth.sub
                    kind = $kind
                    target_id = $targetId
                    amount = $amount
                    pay_method = $payMethod
                    status = $(if($payMethod -eq "zbpay"){"paid"}else{"pending"})
                    created_at = (Get-Date).ToString("o")
                    paid_at = $(if($payMethod -eq "zbpay"){(Get-Date).ToString("o")}else{$null})
                    transaction_id = $(if($payMethod -eq "zbpay"){"ZB-$orderId"}else{$null})
                }
                $orders.orders = @($entry) + @($orders.orders)
                Save-RailOrders $orders

                # 如果是 zbpay：立即解锁，返回 complete 状态
                if ($payMethod -eq "zbpay") {
                    Complete-RailOrder -OrderId $orderId -PayMethod "zbpay" -TransactionId "ZB-$orderId" -User $auth.sub | Out-Null
if (Test-Path $RAIL_PROG_FILE) { $prog2 = (Get-Content $RAIL_PROG_FILE -Raw | ConvertFrom-Json) }
if ($prog2.user_prog.PSObject.Properties[$auth.sub]) { $myProg2 = $prog2.user_prog.$($auth.sub) }
                    Send-Json -Stream $Stream -StatusCode 201 -Data @{
                        order_id=$orderId; amount=$amount; pay_method=$payMethod; status="paid"
                        checkout_info=@{ method="zbpay"; balance_before=($bal+$amount); balance_after=$bal }
                        prog=$myProg2; just_unlocked=$true
                    }
                    return $true
                }

                # 其他方式：构造 checkout_info 供前端展示
                $methodMeta = @($RAIL_PAY_METHODS | Where-Object { $_.id -eq $payMethod })[0]
                # 真实 QR 码（根据支付方式生成不同协议 + 更真实的视觉效果）
                $qrUrl = $null; $scheme = $null
                if ($payMethod -eq "alipay") {
                    $qrUrl = New-AlipayQr -OrderId $orderId -Amount $amount -Note "智北轨道科普"
                    $scheme = "alipays://"
                } elseif ($payMethod -eq "wechat") {
                    $qrUrl = New-WechatQr -OrderId $orderId -Amount $amount -Note "智北轨道科普"
                    $scheme = "weixin://"
                } elseif ([bool]$methodMeta.needs_qr) {
                    $qrUrl = New-BankTransferQr -OrderId $orderId -Amount $amount
                }
                $checkoutInfo = @{
                    method = $payMethod
                    needs_qr = [bool]$methodMeta.needs_qr
                    qr_url  = $qrUrl
                    qr_scheme = $scheme
                    direct_url = "ZBBIZ://pay?order=$orderId&method=$payMethod"
                    zb_deposit = [bool]$methodMeta.zbdeposit
                    amount = $amount
                    order_id = $orderId
                    expires_at = (Get-Date).AddMinutes(15).ToString("o")
                    expires_in_seconds = 900
                    payee_bank = (Get-PayeeBankMasked)
                    hint = $(
                        if ($payMethod -eq "bank")   { "请向下方统一收款账户转账 ¥$amount，备注订单号 $orderId" }
                        elseif ($payMethod -eq "google") { "Google Pay 暂未对接，请改用支付宝/微信/ZBpay 充值" }
                        elseif ($payMethod -eq "apple")  { "Apple Pay 暂未对接，请改用支付宝/微信/ZBpay 充值" }
                        elseif ($payMethod -eq "alipay") { "📱 打开支付宝 → 扫一扫 → 确认支付 ¥$amount（订单号 $orderId）" }
                        elseif ($payMethod -eq "wechat") { "💬 打开微信 → 扫一扫 → 确认支付 ¥$amount（订单号 $orderId）" }
                        else { "请完成支付 ¥$amount（订单号 $orderId）" }
                    )
                }

                Send-Json -Stream $Stream -StatusCode 201 -Data @{
                    order_id=$orderId; amount=$amount; pay_method=$payMethod; status="pending"
                    checkout_info=$checkoutInfo
                    poll_url="/api/rail/orders/$orderId"
                }
                return $true
            } catch {
                $stack = $_.ScriptStackTrace
                Write-Host "[ERROR] create order failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  Stack: $stack" -ForegroundColor Red
                Send-Error $Stream 400 "create order failed: $($_.Exception.Message)"
                return $true
            }
        }

        # GET /api/rail/orders — 我的订单列表
        if ($Path -eq "/api/rail/orders") {
            $orders = Load-RailOrders
            $mine = @($orders.orders | Where-Object { $_.username -eq $auth.sub } | Select-Object -First 50)
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ orders=$mine; total=@($orders.orders | Where-Object { $_.username -eq $auth.sub }).Count }
            return $true
        }

        # GET /api/rail/orders/:id — 订单详情
        if ($Path -match '^/api/rail/orders/(ZO-[A-Z0-9]+)$') {
            $oid = $Matches[1]
            $orders = Load-RailOrders
            $o = @($orders.orders | Where-Object { $_.order_id -eq $oid -and $_.username -eq $auth.sub })
            if ($o.Count -eq 0) { Send-Error $Stream 404 "order not found"; return $true }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ order=$o[0] }
            return $true
        }

        # POST /api/rail/orders/:id/complete — 模拟完成支付（前端确认或 ZBpay Webhook 触发）
        if ($Path -match '^/api/rail/orders/(ZO-[A-Z0-9]+)/complete$' -and $Method -eq "POST") {
            try {
                $oid = $Matches[1]
                $req = $Body | ConvertFrom-Json
                if ($req.pay_method) { $payMethod = [string]$req.pay_method } else { $payMethod = "mock" }
                if ($req.transaction_id) { $txnId = [string]$req.transaction_id } else { $txnId = $null }

                $err = Complete-RailOrder -OrderId $oid -PayMethod $payMethod -TransactionId $txnId -User $auth.sub
                if ($err) { Send-Error $Stream 400 $err; return $true }

                # 完整返回
                $orders = Load-RailOrders
                $o = @($orders.orders | Where-Object { $_.order_id -eq $oid })[0]
if (Test-Path $RAIL_PROG_FILE) { $prog2 = (Get-Content $RAIL_PROG_FILE -Raw | ConvertFrom-Json) }
if ($prog2.user_prog.PSObject.Properties[$auth.sub]) { $myProg2 = $prog2.user_prog.$($auth.sub) }
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; order=$o; prog=$myProg2 }
                return $true
            } catch { Send-Error $Stream 400 "complete order failed: $($_.Exception.Message)"; return $true }
        }

        # POST /api/rail/deposit — 给 ZBpay 余额充值（mock 模式，方便测试）
        if ($Path -eq "/api/rail/deposit" -and $Method -eq "POST") {
            try {
                $req = $Body | ConvertFrom-Json
                $amount = [double]$req.amount
                if ($amount -le 0 -or $amount -gt 10000) { Send-Error $Stream 400 "amount must be 0-10000"; return $true }
                if ($req.channel) { $channel = [string]$req.channel } else { $channel = "mock" }
                Add-ZbBalance -User $auth.sub -Amount $amount -Ref "DEPOSIT-$(Get-Random)"
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; amount=$amount; channel=$channel; balance=(Get-ZbBalance $auth.sub) }
                return $true
            } catch { Send-Error $Stream 400 "deposit failed: $($_.Exception.Message)"; return $true }
        }

        Send-Error $Stream 404 "rail endpoint not found"
        return $true
    }

    return $false
}

# -------- Main Loop --------
$endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $Port)
$tcp = New-Object System.Net.Sockets.TcpListener($endpoint)
$tcp.Start()
$localIP = "127.0.0.1"
try { $ips = Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1; if ($ips) { $localIP = $ips.IPAddress } } catch {}

# --- Init Mock Whitelist ---
Load-MockWhitelist
$myIPs = Get-MyIPs
Write-Host "  MOCK Whitelist: $(if($script:MOCK_WHITELIST.Count -gt 0){$script:MOCK_WHITELIST -join ','}else{'(empty)'})" -ForegroundColor Magenta
Write-Host "  MOCK Auto-allowed (local): $($myIPs -join ', ')" -ForegroundColor Magenta

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ZhiBei Tech AI API Server v4 (ZBpay)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Website:   http://localhost:${Port}" -ForegroundColor Green
Write-Host "  Admin:     http://localhost:${Port}/admin.html" -ForegroundColor Green
Write-Host "  API Docs:  http://localhost:${Port}/api-docs.html" -ForegroundColor Green
Write-Host "  API Base:  http://localhost:${Port}/api" -ForegroundColor Green
Write-Host "  Network:   http://${localIP}:${Port}" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Admin Login: admin / CSFXlhy14" -ForegroundColor Red
Write-Host ""
Write-Host "  Endpoints: auth, chat, generate, code, analyze," -ForegroundColor Gray
Write-Host "             image, sessions, admin/*, pay/*" -ForegroundColor Gray
Write-Host ""
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

try {
    while ($true) {
        $client = $tcp.AcceptTcpClient(); $stream = $client.GetStream()
        try {
            $buffer = New-Object byte[] 262144  # 256KB
            $totalRead = 0
            while ($totalRead -lt $buffer.Length) {
                $toRead = [Math]::Min(8192, $buffer.Length - $totalRead)
                $read = $stream.Read($buffer, $totalRead, $toRead)
                if ($read -le 0) { break }
                $totalRead += $read
                # 找 header 结束标记
                $hdrEnd = -1
                for ($j = 0; $j -lt $totalRead - 3; $j++) {
                    if ($buffer[$j] -eq 13 -and $buffer[$j+1] -eq 10 -and $buffer[$j+2] -eq 13 -and $buffer[$j+3] -eq 10) { $hdrEnd = $j; break }
                }
                if ($hdrEnd -ge 0) {
                    $hdrStr = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $hdrEnd)
                    $cl = [regex]::Match($hdrStr, 'Content-Length:\s*(\d+)', 'IgnoreCase')
                    if ($cl.Success) { $need = [int]$cl.Groups[1].Value } else { $need = 0 }
                    $have = $totalRead - ($hdrEnd + 4)
                    if ($have -ge $need) { break }
                    if ($need -gt 0 -and ($totalRead + ($need - $have)) -gt $buffer.Length) { break }
                }
            }
            $bytesRead = $totalRead
            if ($bytesRead -le 0) { continue }
            $requestText = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
            $lines = $requestText -split "`r`n"
            $requestLine = $lines[0]; $parts = $requestLine -split " "
            if ($parts.Length -lt 2) { continue }
            $method = $parts[0]; $rawPath = $parts[1]; $pathOnly = ($rawPath -split "\?")[0]
            if ($pathOnly -match "\.\.") { Send-Error $stream 403 "forbidden"; continue }
            # Extract headers
            $headerEndIdx = -1
            for ($i = 0; $i -lt $bytesRead - 3; $i++) {
                if ($buffer[$i] -eq 13 -and $buffer[$i+1] -eq 10 -and $buffer[$i+2] -eq 13 -and $buffer[$i+3] -eq 10) { $headerEndIdx = $i; break }
            }
            $body = ""; $authHeader = ""
            foreach ($line in $lines) {
                if ($line -match '^Authorization:\s*(.+)$') { $authHeader = $Matches[1].Trim() }
            }
            # Extract client IP
            $clientIP = ""
            try { $clientIP = ($client.Client.RemoteEndPoint.ToString() -split ":")[0] } catch {}
            foreach ($line in $lines) {
                if ($line -match '^X-Forwarded-For:\s*(.+)$') { $xff = $Matches[1].Split(",")[0].Trim(); if ($xff) { $clientIP = $xff } }
            }
            if ($method -eq "POST" -and $headerEndIdx -ge 0) {
                $bodyStart = $headerEndIdx + 4
                if ($bodyStart -lt $bytesRead) {
                    $bodyBytes = New-Object byte[] ($bytesRead - $bodyStart)
                    [Array]::Copy($buffer, $bodyStart, $bodyBytes, 0, $bytesRead - $bodyStart)
                    $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                }
            }
            $ts = Get-Date -Format "HH:mm:ss"
            if ($pathOnly -match "^/api/") {
                $handled = Handle-API -Path $rawPath -Method $method -Body $body -AuthHeader $authHeader -Stream $stream -ClientIP $clientIP
                if ($handled) { Write-Host "  [$ts] API $method $pathOnly" -ForegroundColor DarkCyan }
                else { Send-Error $stream 404 "endpoint not found"; Write-Host "  [$ts] API 404 $method $pathOnly" -ForegroundColor Red }
            } else {
                if ($pathOnly -eq "/" -or [string]::IsNullOrEmpty($pathOnly)) { $pathOnly = "/index.html" }
                $relativePath = $pathOnly.TrimStart("/")
                $fullPath = Join-Path $scriptDir $relativePath
                if ((Test-Path $fullPath -PathType Container)) { $fullPath = Join-Path $fullPath "index.html" }
                $sent = Send-File -Stream $stream -FilePath $fullPath
                if ($sent) { Write-Host "  [$ts] 200 $method $pathOnly" -ForegroundColor DarkGray }
                else { Send-Error $stream 404 "not found"; Write-Host "  [$ts] 404 $method $pathOnly" -ForegroundColor Red }
            }
        } catch {
            Write-Host "  Error: $_" -ForegroundColor Red
            try { Send-Error $stream 500 "internal error" } catch {}
        } finally {
            try { $stream.Close() } catch {}; try { $client.Close() } catch {}
        }
    }
} finally { $tcp.Stop(); Write-Host ""; Write-Host "Server stopped." -ForegroundColor Yellow }
