﻿# ============================================
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
$JWT_SECRET  = "zb-secret-2026-zhibei-tech-inner"
$ADMIN_USER  = "admin"
$ADMIN_PASS  = "CSFXlhy14"

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

# -------- Rail Academy Seed (20 units × 10 parts × 10 lessons = 2000) --------
if (-not (Test-Path $RAIL_CAT_FILE)) {
    $railUnits = @(
        "轨道交通概览与发展历程","城市地铁系统基础架构","轻轨与有轨电车技术",
        "高铁动车组原理与结构","轨道信号与列控系统（CBTC）","车站设计与换乘枢纽",
        "牵引供电系统（接触网/第三轨）","车辆机械结构与车体","转向架与轮对技术",
        "制动系统原理","空调与内饰设计","通信与乘客信息系统（PIS）",
        "屏蔽门与安全门系统","轨道交通车辆制造工艺","车辆运营与调度管理",
        "轨道工程与道岔技术","电力系统与变电所","城市轨道交通投融资与运营",
        "智能运维与预测性维护","智北 AI 在轨道交通中的应用"
    )
    $partNames = @("入门导引","核心概念","系统架构","关键技术","实战案例","进阶原理","对比分析","常见问题","行业趋势","单元总结")
    $partIcons = @("🌱","📘","🏗️","⚙️","🛠️","🔬","⚖️","❓","📈","✅")
    $lessonVerbs = @("认识","理解","掌握","分析","对比","设计","调试","优化","评估","总结")
    $lessonNouns = @("概念","原理","架构","接口","流程","部件","算法","规范","案例","体系")
    $unitsOut = @()
    for($u=0;$u -lt 20;$u++){
        $uid = "u$($u+1)"; $uName = $railUnits[$u]
        $isFree = ($u -eq 0)  # 第 1 单元全部免费
        $partsOut = @()
        for($p=0;$p -lt 10;$p++){
            $partId = "$($uid)p$($p+1)"; $pName = $partNames[$p]
            $lessonsOut = @()
            for($l=0;$l -lt 10;$l++){
                $lid = "$($partId)l$($l+1)"
                $title = "$($lessonVerbs[$l])$($lessonNouns[$l])：$($pName)之$($lessonVerbs[$l])$($lessonNouns[$l])"
                $lessonsOut += [pscustomobject]@{
                    id=$lid; no=($l+1)
                    title=$title
                    duration=110+($u*3+($p*$l)%25)  # ~2min with variation
                    free=$isFree  # 第 1 单元全部免费
                    doc_markdown=("### $title`n`n**所属**：第 $($u+1) 单元 · 第 $($p+1) 部分`n`n#### 一、学习目标`n在本小结中，我们将围绕「$($uName)」主题下的「$($pName)」模块，系统讲解其核心知识与实践要点。通过视频 + 配套文档的双轨学习，你将建立完整的知识体系。`n`n#### 二、核心内容`n1. 基本定义与概念边界`n2. 工作原理与机制剖析`n3. 典型应用场景与案例`n4. 常见误区与正确姿势`n`n#### 三、学习建议`n- 建议先完整观看视频一遍，再阅读文档做笔记`n- 关键技术点可以暂停回看，配合示意图解加深理解`n- 如遇疑问，可在评论区留言或在智北工作台 AI 助手处提问`n`n#### 四、延伸阅读`n- 行业标准与规范（GB、TB 系列）`n- 相关国际学术论文与会议报告`n- 智北科技公开技术白皮书")
                }
            }
            $partsOut += [pscustomobject]@{
                id=$partId; no=($p+1); name=$pName; icon=$partIcons[$p]
                lessons=$lessonsOut; total=10
            }
        }
        $unitsOut += [pscustomobject]@{
            id=$uid; no=($u+1); name=$uName; icon=@("🚆","🚇","🚉","🚄","📡","🏛️","⚡","🚋","🔧","🛑","❄️","📣","🚪","🏭","🗺️","🛤️","🔋","💰","🔍","🤖")[$u]
            free=$isFree; tag=if($isFree){"全部免费"}else{"¥89/单元"}
            parts=$partsOut; total_parts=10; total_lessons=100
        }
    }
    @{
        meta=@{version="1.0"; generated=(Get-Date).ToString("o"); units=20; parts_per_unit=10; lessons_per_part=10; price_lesson=1; price_part=9; price_unit=89; free_unit=1}
        units=$unitsOut
    } | ConvertTo-Json -Depth 8 | Out-File -FilePath $RAIL_CAT_FILE -Encoding utf8
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
    if (Test-Path $file) { $existing = (Get-Content $file -Raw | ConvertFrom-Json) }
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
    # Prompt text overlay
    $shortPrompt = if ($Prompt.Length -gt 40) { $Prompt.Substring(0,37) + "..." } else { $Prompt }
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

# -------- API Handler --------
function Handle-API {
    param([string]$Path,[string]$Method,[string]$Body,[string]$AuthHeader,[System.Net.Sockets.NetworkStream]$Stream)

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

    # --- Auth endpoints ---
    if ($Path -eq "/api/register" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            $un = [string]$req.username; $pw = [string]$req.password; $em = if ($req.email) { [string]$req.email } else { "" }
            if ([string]::IsNullOrWhiteSpace($un) -or [string]::IsNullOrWhiteSpace($pw)) { Send-Error $Stream 400 "username and password required"; return $true }
            if ($un.Length -lt 3) { Send-Error $Stream 400 "username min 3 chars"; return $true }
            if ($pw.Length -lt 6) { Send-Error $Stream 400 "password min 6 chars"; return $true }
            $existing = Load-UserByName $un
            if ($existing) { Send-Error $Stream 400 "username already exists"; return $true }
            $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pw))).Replace("-","")
            $users = Load-Users
            $users += [pscustomobject]@{
                username=$un; password_hash=$hash; role="user"; email=$em;
                created_at=(Get-Date).ToString("o"); api_key="zb-$(Get-Random -Min 100000 -Max 999999)"; quota_tokens=100000
            }
            Save-Users $users
            $token = New-Token $un "user"
            Send-Json -Stream $Stream -StatusCode 201 -Data @{
                token=$token; username=$un; role="user"; api_key=($users[-1].api_key);
                quota_tokens=100000; message="registration successful"
            }
        } catch { Send-Error $Stream 400 $_.Exception.Message }
        return $true
    }
    if ($Path -eq "/api/login" -and $Method -eq "POST") {
        try {
            $req = $Body | ConvertFrom-Json
            $un = [string]$req.username; $pw = [string]$req.password
            $user = Load-UserByName $un
            if (-not $user) { Send-Error $Stream 401 "invalid credentials"; return $true }
            $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pw))).Replace("-","")
            if ($user.password_hash -ne $hash) { Send-Error $Stream 401 "invalid credentials"; return $true }
            $token = New-Token $un $user.role
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                token=$token; username=$un; role=$user.role; api_key=$user.api_key;
                quota_tokens=$user.quota_tokens; email=$user.email; message="login successful"
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

    # --- Chat endpoints (work without auth too, but with auth tracks user) ---
    $userForQuota = if ($auth) { Load-UserByName $auth.sub } else { $null }
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
            $model = if ($req.model) { [string]$req.model } else { "zb-large-v1" }
            $sid = if ($req.session_id) { [string]$req.session_id } else { $null }
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
            $prompt = if ($req.prompt) { [string]$req.prompt } else { "" }
            if ([string]::IsNullOrWhiteSpace($prompt)) { Send-Error $Stream 400 "prompt required"; return $true }
            $model = if ($req.model) { [string]$req.model } else { "zb-large-v1" }
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
            $prompt = if ($req.prompt) { [string]$req.prompt } else { "" }
            $language = if ($req.language) { [string]$req.language } else { "python" }
            if ([string]::IsNullOrWhiteSpace($prompt)) { Send-Error $Stream 400 "prompt required"; return $true }
            $code = Get-AIResponse -Prompt "code $language : $prompt"
            Invoke-RecordStat -Model "zb-code-v1" -Tokens $code.Length -Endpoint "code"
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
            $task = if ($req.task) { [string]$req.task } else { "general" }
            $desc = if ($req.data_description) { [string]$req.data_description } else { "" }
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
            $prompt = if ($req.prompt) { [string]$req.prompt } else { "abstract art" }
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
            $title = if ($req.title) { [string]$req.title } else { "New Chat" }
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
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ products=$products; yuan_per_1000_tokens=0.001 }
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
            $oid = if ($req.order_id) { [string]$req.order_id } else { [string]$req.out_trade_no }
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
            $filter = if ($Query.ContainsKey("status")) { $Query["status"] } else { $null }
            $keyword = if ($Query.ContainsKey("q")) { $Query["q"].ToString().ToUpper() } else { $null }
            $page = if ($Query.ContainsKey("page")) { [int]$Query["page"] } else { 1 }
            $pageSize = if ($Query.ContainsKey("size")) { [int]$Query["size"] } else { 50 }
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
                    $codesData.codes += [pscustomobject]@{
                        code=$code; status="available"; target_kind=$null; target_id=$null
                        price=if($req.price){[int]$req.price}else{0}; used_by=$null; used_at=$null; batch=$batchTag
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
                $price = if($req.price){[int]$req.price}else{0}
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
            $target = [string]$req.username; $quota = [int]$req.quota_tokens; $note = if ($req.note) { [string]$req.note } else { "admin manual credit" }
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
        $em = if (Test-Path $ENT_EMP_FILE) { @((Get-Content $ENT_EMP_FILE -Raw | ConvertFrom-Json).employees) } else { @() }
        $de = if (Test-Path $ENT_DEPT_FILE) { @((Get-Content $ENT_DEPT_FILE -Raw | ConvertFrom-Json).departments) } else { @() }
        $st = if (Test-Path $STATS_FILE) { Get-Content $STATS_FILE -Raw | ConvertFrom-Json } else { @{ daily=@{} } }
        $today = (Get-Date).ToString("yyyy-MM-dd")
        # AI usage trend 7 days
        $trend = @()
        for ($d = 6; $d -ge 0; $d--) {
            $dt = (Get-Date).AddDays(-$d).ToString("yyyy-MM-dd")
            $cnt = if ($st.daily -and $st.daily.PSObject.Properties[$dt]) { $st.daily.$dt.calls } else { if ($d -eq 0) { 1234 } else { Get-Random -Min 400 -Max 2000 } }
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
    if ($Path -eq "/api/ent/departments") {
        $de = if (Test-Path $ENT_DEPT_FILE) { @((Get-Content $ENT_DEPT_FILE -Raw | ConvertFrom-Json).departments) } else { @() }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ departments=$de }
        return $true
    }

    # Employees
    if ($Path -eq "/api/ent/employees") {
        $em = if (Test-Path $ENT_EMP_FILE) { @((Get-Content $ENT_EMP_FILE -Raw | ConvertFrom-Json).employees) } else { @() }
        $de = if (Test-Path $ENT_DEPT_FILE) { @((Get-Content $ENT_DEPT_FILE -Raw | ConvertFrom-Json).departments) } else { @() }
        $lookup = @{}; foreach ($d in $de) { $lookup[$d.id] = $d.name }
        $withDept = @()
        foreach ($e in $em) {
            $dn = if ($e.department_id -and $lookup.ContainsKey($e.department_id)) { $lookup[$e.department_id] } else { "-" }
            $withDept += [pscustomobject]@{ id=$e.id; name=$e.name; position=$e.position; department=$dn; email=$e.email; phone=$e.phone; status=$e.status; join_date=$e.join_date; role=$e.role }
        }
        Send-Json -Stream $Stream -StatusCode 200 -Data @{ employees=$withDept; total=$withDept.Count; active=@($withDept | Where-Object { $_.status -eq "active" }).Count }
        return $true
    }

    # Audit logs
    if ($Path -eq "/api/ent/audit-logs") {
        $lg = if (Test-Path $ENT_LOG_FILE) { @((Get-Content $ENT_LOG_FILE -Raw | ConvertFrom-Json).logs) } else { @() }
        $all = @($lg | Sort-Object time -Descending)
        # Pad with some extra demo logs if short
        if ($all.Count -lt 20) {
            for ($i = $all.Count; $i -lt 20; $i++) {
                $actors = @("admin","admin","张明","赵磊","system")
                $actions = @("访问控制台","创建工单","审批流程","查看数据报表","配置AI模型","修改安全策略","导出审计日志","新增应用")
                $actor = $actors[(Get-Random -Min 0 -Max $actors.Count)]
                $act = $actions[(Get-Random -Min 0 -Max $actions.Count)]
                $sev = if ($act -match "审批|导出|策略") { "warning" } else { "info" }
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
            $wb = if (Test-Path $WB_TODO_FILE) { Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json } else { @{ todos=@(); schedule=@(); messages=@(); docs=@() } }
            $appsData = if (Test-Path $WB_APP_FILE) { Get-Content $WB_APP_FILE -Raw | ConvertFrom-Json } else { @{ apps=@(); ai_models=@() } }
            $now = Get-Date
            $todayStr = $now.ToString("yyyy-MM-dd")
            $todaySchedule = @($wb.schedule | Where-Object { $_.date -eq $todayStr })
            $pendingTodos = @($wb.todos | Where-Object { $_.status -eq "pending" })
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                user=@{ name=$auth.sub; role=if($auth.role){$auth.role}else{"member"}; avatar=$auth.sub.Substring(0,1).ToUpper() }
                greeting=if($now.Hour -lt 11){"早上好"}elseif($now.Hour -lt 14){"中午好"}elseif($now.Hour -lt 18){"下午好"}else{"晚上好"}
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
            $appsData = if (Test-Path $WB_APP_FILE) { Get-Content $WB_APP_FILE -Raw | ConvertFrom-Json } else { @{ apps=@(); ai_models=@() } }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{
                apps=@($appsData.apps)
                ai_models=@($appsData.ai_models)
            }
            return $true
        }

        # 我的待办
        if ($Path -eq "/api/wb/todos") {
            $wb = if (Test-Path $WB_TODO_FILE) { Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json } else { @{ todos=@() } }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ todos=@($wb.todos); total=@($wb.todos).Count; pending=@($wb.todos | Where-Object { $_.status -eq "pending" }).Count }
            return $true
        }

        # 今日日程
        if ($Path -eq "/api/wb/schedule") {
            $wb = if (Test-Path $WB_TODO_FILE) { Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json } else { @{ schedule=@() } }
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ schedule=@($wb.schedule); total=@($wb.schedule).Count }
            return $true
        }

        # 简单搜索（apps + docs）
        if ($Path -eq "/api/wb/search") {
            $wb = if (Test-Path $WB_TODO_FILE) { Get-Content $WB_TODO_FILE -Raw | ConvertFrom-Json } else { @{ docs=@() } }
            $appsData = if (Test-Path $WB_APP_FILE) { Get-Content $WB_APP_FILE -Raw | ConvertFrom-Json } else { @{ apps=@() } }
            $q = if ($Query.ContainsKey('q')) { [string]$Query['q'] } else { "" }
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
        # 加载 catalog（公开）和 prog（需要时）
        $cat = if (Test-Path $RAIL_CAT_FILE) { Get-Content $RAIL_CAT_FILE -Raw | ConvertFrom-Json } else { [pscustomobject]@{ meta=[pscustomobject]@{}; units=@() } }
        $prog = if (Test-Path $RAIL_PROG_FILE) { (Get-Content $RAIL_PROG_FILE -Raw | ConvertFrom-Json) } else { [pscustomobject]@{ user_prog=[pscustomobject]@{} } }
        $myProg = if ($auth.sub -and $prog.user_prog.PSObject.Properties[$auth.sub]) { $prog.user_prog.$($auth.sub) } else { [pscustomobject]@{ unlocked_units=@(); unlocked_parts=@(); unlocked_lessons=@(); paid_total=0 } }

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

        # ========== 以下端点需要登录 ==========
        if (-not $auth.sub) { Send-Error $Stream 401 "login required"; return $true }

        # 单个 lesson 详情（含 doc_markdown + video meta + free/unlocked）
        if ($Path -match '^/api/rail/lesson/(\w+)$') {
            $lid = $Matches[1]
            foreach($u in $cat.units){
                foreach($p in $u.parts){
                    $l = @($p.lessons | Where-Object { $_.id -eq $lid })
                    if($l.Count -gt 0){
                        $isFreeLesson = [bool]$l[0].free
                        $isFreeUnit = [bool]$u.free
                        $unlocked = $isFreeLesson -or $isFreeUnit -or
                                    ($myProg.unlocked_units -contains $u.no) -or
                                    ($myProg.unlocked_parts -contains $p.id) -or
                                    ($myProg.unlocked_lessons -contains $l[0].id) -or
                                    ($auth.role -eq "admin")
                        Send-Json -Stream $Stream -StatusCode 200 -Data @{
                            lesson=$l[0]; unit=$u.no; unit_name=$u.name; part=$p.no; part_name=$p.name
                            is_free=[bool]$isFreeLesson; unit_free=[bool]$isFreeUnit; unlocked=[bool]$unlocked
                            meta=$cat.meta
                        }
                        return $true
                    }
                }
            }
            Send-Error $Stream 404 "lesson not found"; return $true
        }

        # 我的进度（解锁状态）
        if ($Path -eq "/api/rail/progress") {
            Send-Json -Stream $Stream -StatusCode 200 -Data @{ user=$auth.sub; prog=$myProg; role=$auth.role }
            return $true
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
                $prog2 = if (Test-Path $RAIL_PROG_FILE) { (Get-Content $RAIL_PROG_FILE -Raw | ConvertFrom-Json) } else { [pscustomobject]@{ user_prog=[pscustomobject]@{} } }
                $myProg2 = if ($prog2.user_prog.PSObject.Properties[$auth.sub]) { $prog2.user_prog.$($auth.sub) } else { [pscustomobject]@{ unlocked_units=@(); unlocked_parts=@(); unlocked_lessons=@(); paid_total=0 } }
                Send-Json -Stream $Stream -StatusCode 200 -Data @{ status="ok"; code=$code; prog=$myProg2 }
                return $true
            } catch { Send-Error $Stream 400 "redeem failed: $($_.Exception.Message)"; return $true }
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
            $buffer = New-Object byte[] 65536
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
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
                $handled = Handle-API -Path $rawPath -Method $method -Body $body -AuthHeader $authHeader -Stream $stream
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
