# -*- coding: utf-8 -*-
"""智北轨道科普 · 视频元数据生成器 v2.0
从 RAIL_CATALOG.json 提取真实高铁知识，生成最高质量（1920×1080 FHD）的 RAIL_VIDEO_META.json。
每套主题色：Unit1 和谐号蓝 / Unit2 复兴号红金 / Unit3 工程橙。
"""
import json, os, re

BASE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(BASE, "data", "RAIL_CATALOG.json")
OUT = os.path.join(BASE, "data", "RAIL_VIDEO_META.json")

# 三套主题色（最高质量深色系）
UNIT_THEMES = {
    1: {  # 和谐号 · 深海蓝
        "bg_from": "#0b1628", "bg_to": "#0a2540",
        "accent": "#1e90ff", "title": "#ffd700", "subtitle": "#e0e0e0"
    },
    2: {  # 复兴号 · 红金
        "bg_from": "#1a0a0a", "bg_to": "#2d1810",
        "accent": "#c8102e", "title": "#ffd700", "subtitle": "#f0e6d0"
    },
    3: {  # 高铁工程 · 地质橙
        "bg_from": "#1a1000", "bg_to": "#2a1a00",
        "accent": "#ff6b35", "title": "#ffd700", "subtitle": "#f5e6c8"
    },
}

# 单元 emoji 映射
UNIT_ICONS = {1: "🚆", 2: "🚄", 3: "🛤️"}

def clean_md(s):
    """清理 markdown 格式（去粗体/行内代码）"""
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    s = re.sub(r"__(.+?)__", r"\1", s)
    s = re.sub(r"`([^`]+)`", r"\1", s)
    return s.strip()

def strip_section_label(s):
    """专门用于解说句：清除行首小标题标签
    例: '技术特点：以瑞典...' → '以瑞典...'"""
    s = clean_md(s)
    s = re.sub(r"^[^\s]{2,8}[：:]\s*", "", s)
    return s.strip()

# 要跳过的表头词（只在表格第一行出现，不应作为要点）
HEADER_KEYS = {
    "阶段", "代表车型", "最高速度", "年代", "技术来源",
    "项目", "参数", "对比项", "系列", "设计速度", "厂商", "投产",
    "和谐号 CRH", "复兴号 CR400", "车种", "车号", "备注", "编号"
}

# 要跳过的粗体小标题（不是真实知识点，是段落标题）
BOLD_BLACKLIST = {
    "基本参数", "核心参数", "主要参数", "技术参数",
    "技术特点", "技术改进", "技术特色", "技术指标",
    "运营", "运营情况", "运营现状", "运营数据",
    "原型", "产量", "研制背景", "车站", "桥梁占比",
    "发展历程", "历史背景", "国产化", "自主创新",
}

def extract_keywords(md, max_kw=6):
    """从 markdown 表格和段落里提取真实知识点
    修复：label 长度放宽到 2+ 字，按表头行内容跳过，clean_md 后置"""
    kws = []
    lines = md.split("\n")
    in_table = False
    table_header_skipped = False
    header_cells = set()  # 记录当前表格的表头词

    for ln in lines:
        if "|" in ln:
            cells = [c.strip() for c in ln.split("|")]
            cells = [c for c in cells if c]
            if not cells:
                continue
            # 分隔符行：|---|---|
            if all(set(c) <= {"-", ":", " "} for c in cells):
                table_header_skipped = True
                in_table = True
                continue
            if not table_header_skipped:
                # 表头行，记录所有 cell 内容
                header_cells = {clean_md(c) for c in cells}
                table_header_skipped = True
                in_table = True
                continue
            if in_table and len(cells) >= 2:
                label = clean_md(cells[0])
                value = clean_md(cells[1])
                # 只跳过真正的表头词（出现在表头行里的）
                # 同时安全网：跳过一些全局不可能是参数 label 的词
                if label in header_cells and label != value:
                    continue
                # 跳过 label/value 过长的（描述性文字不是参数）
                # 允许 2 字 label（如 编组/定员/车长/车宽/车高/轴重）
                if 1 < len(label) < 40 and 0 < len(value) < 100:
                    kws.append(f"{label}：{value}")
        else:
            # 非表格行且非空：重置表格状态
            if ln.strip():
                in_table = False
                table_header_skipped = False
                header_cells = set()

    # 提取段落里的 **粗体** 短语（作为独立要点，跳过小标题）
    for m in re.finditer(r"\*\*(.+?)\*\*", md):
        v = clean_md(m.group(1))
        if (3 < len(v) < 50
                and not v.startswith("第")
                and not v.endswith("等")
                and v not in BOLD_BLACKLIST):
            kws.append(v)

    # 去重（最后统一 clean_md 已在前面做了）
    seen = set()
    result = []
    for k in kws:
        if k and k not in seen:
            seen.add(k)
            result.append(k)
    return result[:max_kw]

def split_sections(md):
    """把 markdown 按 ##/### 标题切成段落"""
    lines = md.strip().split("\n")
    sections = []
    cur_title = ""
    cur_body = []
    for ln in lines:
        h = re.match(r"^#{1,4}\s+(.+)", ln)
        if h:
            if cur_body:
                sections.append((cur_title, "\n".join(cur_body).strip()))
            cur_title = h.group(1).strip()
            cur_body = []
        elif ln.strip():
            cur_body.append(ln)
    if cur_body:
        sections.append((cur_title, "\n".join(cur_body).strip()))
    return sections

def extract_narration_sentences(md, max_sents=4):
    """从非表格段落中提取有信息量的解说句（用于视频口播）
    排除表格行、列表标记、过长/过短/纯小标题"""
    sents = []
    secs = split_sections(md)
    for sec_title, body in secs:
        for ln in body.split("\n"):
            ln = ln.strip()
            if not ln:
                continue
            # 跳过表格行
            if ln.startswith("|") or all(set(c) <= {"-", ":", "|"} for c in ln):
                continue
            # 跳过纯列表标记/纯小标题
            ln = ln.strip("-*").strip()
            if len(ln) < 8:
                continue
            if len(ln) > 120:  # 太长的句子截断
                ln = ln[:115] + "…"
            # 用 strip_section_label 清理（去小标题前缀 + markdown）
            ln_clean = strip_section_label(ln)
            if ln_clean in BOLD_BLACKLIST:
                continue
            # 排除纯参数行（label: value 格式）
            if re.match(r"^[\u4e00-\u9fa5A-Za-z]+[：:]\s*[\d]", ln_clean):
                continue
            # 排除纯列表罗列（逗号/顿号超过 4 个 = 站名/清单）
            punct_count = ln_clean.count("、") + ln_clean.count("，") + ln_clean.count(",")
            if punct_count > 4:
                continue
            # 排除纯数字开头（"81.5%..."、"2017 年..." 这种）
            if re.match(r"^[\d\.]+\s*[%年公里km]", ln_clean):
                continue
            sents.append(ln_clean)
    # 去重
    seen = set()
    out = []
    for s in sents:
        if s not in seen:
            seen.add(s)
            out.append(s)
    return out[:max_sents]

def _keyword_to_spoken(kw):
    """把 'label：value' 格式的知识点变成口播体
    例: '最高设计速度：250 km/h' -> '最高设计速度达到 250 km/h'"""
    if "：" in kw:
        label, value = kw.split("：", 1)
        value = value.strip()
        # label -> 不同口播前缀（避免 value 开头的重复词）
        spoken_prefixes = {
            "最高设计速度": "最高设计速度达到",
            "设计速度": "设计速度为",
            "最高运营速度": "最高运营速度可达",
            "最高试验速度": "最高试验速度创下",
            "试验速度": "试验速度达到",
            "编组": "采用的编组方式是",
            "定员": "最大定员人数为",
            "车长": "车身总长度",
            "车宽": "车身宽度为",
            "车高": "车身高度为",
            "轴重": "轴重控制在",
            "牵引功率": "牵引功率达到",
            "生产厂商": "由",
            "投产": "投产于",
            "产量": "累计产量达到",
            "线路全长": "线路全长达到",
            "运营时间": "正式投入运营是在",
            "全程时间": "全程最快只需",
            "年客流量": "年客流量超过",
            "总投资": "项目总投资约",
        }
        prefix = spoken_prefixes.get(label, label + "是")
        # 避免重复词：只要 prefix 里已包含 value 开头的词就切掉
        # "全程最快只需" + "最快 4h 18min" → "全程最快只需 4h 18min"
        # "年客流量超过" + "超 2 亿人次" → "年客流量超过 2 亿人次"
        # "项目总投资约" + "约 2209 亿元" → "项目总投资约 2209 亿元"
        if "最快" in prefix and value.startswith("最快"):
            value = value[2:].strip()
        elif "超过" in prefix and value.startswith("超"):
            value = value[1:].strip()
        elif "约" in prefix and value.startswith("约"):
            value = value[1:].strip()
        return f"{prefix} {value}"
    return kw

def build_subtitle_lines(lesson, unit_name, part_name):
    """生成视频字幕：标题 + 参数要点 + 解说金句 + 引导"""
    title = lesson["title"]
    md = lesson.get("doc_markdown", "")
    kws = extract_keywords(md, max_kw=5)
    narrations = extract_narration_sentences(md, max_sents=2)

    lines = []
    lines.append(f"📌 {title} — 本节核心知识点")
    for kw in kws[:4]:
        lines.append(f"• {clean_md(kw)}")
    # 穿插一条解说金句
    if narrations:
        lines.append(f"💬 {narrations[0]}")
    hints = [
        "💡 建议先完整看完，再对照文档做笔记",
        "💡 关键参数可以暂停截图保存",
        "💡 有疑问可在智北工作台 AI 助手提问",
    ]
    h_idx = abs(hash(title)) % 3
    lines.append(hints[h_idx])
    return lines[:8]

def build_script_lines(lesson, unit_no, part_no, lesson_no, unit_name, part_name):
    """生成视频的完整口播解说脚本
    结构：开场欢迎 → 主题引入 → 参数讲解 → 亮点解说 → 总结"""
    title = lesson["title"]
    md = lesson.get("doc_markdown", "")
    kws = extract_keywords(md, max_kw=5)
    narrations = extract_narration_sentences(md, max_sents=3)

    s = []
    # 开场
    s.append("【开场】欢迎来到智北轨道科普课堂")
    s.append(f"【引入】今天我们来讲第{unit_no}单元·{part_name}中的：{title}")

    if kws:
        # 用口播体逐个讲解参数
        for i, kw in enumerate(kws[:5], 1):
            spoken = _keyword_to_spoken(kw)
            s.append(f"【讲解{i}】{spoken}")
    else:
        # 没有参数表格时，取解说段首句
        if narrations:
            for i, n in enumerate(narrations[:4], 1):
                s.append(f"【讲解{i}】{n}")
        else:
            s.append("【讲解1】这是一节重要的轨道知识点课程")

    # 亮点解说（从非表格段落）
    if narrations and len(narrations) > 0:
        s.append(f"【亮点】值得一提的是：{narrations[0]}")
    if narrations and len(narrations) > 1:
        s.append(f"【拓展】{narrations[1]}")

    # 结语
    s.append(f"【结语】好，以上就是《{title}》的核心知识点")
    return s

def build_points(lesson):
    """独立的知识点列表（保持原始格式用于前端对比展示）"""
    md = lesson.get("doc_markdown", "")
    kws = extract_keywords(md, max_kw=8)
    if kws:
        return kws
    secs = split_sections(md)
    pts = []
    for _, body in secs:
        for ln in body.split("\n"):
            ln = ln.strip().strip("-*").strip()
            if ln and 10 < len(ln) < 60 and not ln.startswith("|"):
                pts.append(ln)
                break
    return pts[:6]

# ========== 主流程 ==========
with open(CATALOG, "r", encoding="utf-8") as f:
    catalog = json.load(f)

meta = {}
total_lessons = 0

for unit in catalog["units"]:
    u_no = unit["no"]
    u_name = unit["name"]
    u_icon = UNIT_ICONS.get(u_no, "🚆")
    theme = UNIT_THEMES.get(u_no, UNIT_THEMES[1])

    for part in unit["parts"]:
        p_no = part["no"]
        p_name = part["name"]

        for lesson in part["lessons"]:
            lid = lesson["id"]
            l_no = lesson["no"]
            duration = lesson.get("duration", 180)

            subtitle_lines = build_subtitle_lines(lesson, u_name, p_name)
            script_lines = build_script_lines(lesson, u_no, p_no, l_no, u_name, p_name)
            points = build_points(lesson)

            # 根据脚本长度估算实际视频时长
            # 每个脚本行约 15 秒
            est_duration = max(90, min(300, len(script_lines) * 15))

            meta[lid] = {
                "video_type": "canvas",
                "video_mode": "static",
                "theme": theme,
                "icon": u_icon,
                "unit_no": u_no,
                "unit_name": u_name,
                "part_no": p_no,
                "part_name": p_name,
                "lesson_no": l_no,
                "lesson_title": lesson["title"],
                "subtitle_lines": subtitle_lines,
                "subtitle_duration": duration,
                "script_lines": script_lines,
                "points": points,
                "duration": est_duration,
                "resolution": {"w": 1920, "h": 1080},
                "audio": {"enabled": True, "note": "Canvas 渲染 + 实时语音合成解说"},
            }
            total_lessons += 1

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, indent=2)

print(f"✅ RAIL_VIDEO_META.json 生成完成")
print(f"   课程总数: {total_lessons}")
print(f"   分辨率:   1920×1080 (FHD)")
print(f"   主题:     单元1=和谐号蓝 / 单元2=复兴号红金 / 单元3=工程橙")
print(f"   输出:     {OUT}")
print()

# 预览前 3 个
for i, (k, v) in enumerate(list(meta.items())[:3]):
    print(f"[{k}] {v['unit_name']} · {v['part_name']} · L{v['lesson_no']} {v['lesson_title']}")
    print(f"  时长 ~{v['duration']}s  分辨率 {v['resolution']['w']}x{v['resolution']['h']}")
    print(f"  要点数 {len(v['points'])}  脚本行 {len(v['script_lines'])}")
    for pt in v['points'][:3]:
        print(f"    • {pt}")
    print()
