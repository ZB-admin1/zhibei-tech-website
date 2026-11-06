# -*- coding: utf-8 -*-
"""
智北科技 · 桌面端启动器
======================
功能：
  1. 自动检测 server.ps1 是否已启动（检查 8080 端口）
  2. 未启动则后台拉起 server.ps1
  3. 等待健康接口就绪（最多 15 秒超时）
  4. 打开 pywebview 桌面窗口加载官网

用法：
  python app.py            # 启动桌面窗口
  python app.py --headless # 只启动服务器不打开窗口

局域网访问：
  启动后其他设备可通过 http://<本机IP>:8080 访问
"""

import sys
import os
import subprocess
import time
import threading
import socket
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.abspath(__file__))
SERVER_PS1 = os.path.join(ROOT, "server.ps1")
PORT = 8080
WINDOW_TITLE = "智北科技 · AI API 与轨道科普"

# pywebview 可能因为 WebView2 / pythonnet 问题导入失败
try:
    import webview
    WEBVIEW_OK = True
except Exception as e:
    WEBVIEW_OK = False
    WEBVIEW_ERR = str(e)


def is_server_alive():
    """检查 server 是否在 8080 端口监听 + 健康接口 OK"""
    try:
        # 先查端口
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        result = sock.connect_ex(("127.0.0.1", PORT))
        sock.close()
        if result != 0:
            return False
        # 再查健康接口
        req = urllib.request.Request(f"http://localhost:{PORT}/api/health")
        resp = urllib.request.urlopen(req, timeout=2)
        return resp.status == 200
    except Exception:
        return False


def find_local_ip():
    """获取本机局域网 IP"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def start_server():
    """后台启动 server.ps1"""
    if not os.path.exists(SERVER_PS1):
        print(f"[ERROR] server.ps1 not found at {SERVER_PS1}")
        return False

    # 用 PowerShell 后台启动，不阻塞
    CREATE_NO_WINDOW = 0x08000000
    try:
        subprocess.Popen(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SERVER_PS1],
            cwd=ROOT,
            creationflags=CREATE_NO_WINDOW if os.name == "nt" else 0,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
        return True
    except Exception as e:
        print(f"[ERROR] Failed to start server: {e}")
        return False


def wait_for_server(timeout=15):
    """等待服务器就绪"""
    print(f"[INFO] Waiting for server on port {PORT} ...")
    for i in range(timeout * 2):
        if is_server_alive():
            return True
        time.sleep(0.5)
    return False


def show_tray_info():
    """打印可访问地址（即使没有 pywebview 也有用）"""
    local_ip = find_local_ip()
    print("\n" + "=" * 50)
    print(f"  智北科技 · 桌面端服务器已启动")
    print("=" * 50)
    print(f"  本机访问:  http://localhost:{PORT}")
    print(f"  局域网访问: http://{local_ip}:{PORT}")
    print(f"  管理后台:  http://localhost:{PORT}/admin.html")
    print(f"  轨道科普:  http://localhost:{PORT}/rail-academy.html")
    print(f"  管理员:    admin / CSFXlhy14")
    print("=" * 50 + "\n")


def _build_splash_html():
    """构建内嵌的等待页 HTML（智北官网正在启动）"""
    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>智北科技 · 启动中</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{height:100%;width:100%;overflow:hidden}
  body{
    background:#05060a;
    color:#e5e7eb;
    font-family:"Microsoft YaHei","PingFang SC",sans-serif;
    display:flex;align-items:center;justify-content:center;
    position:relative;
  }
  /* 背景网格 */
  body::before{
    content:"";position:absolute;inset:0;
    background-image:
      linear-gradient(rgba(0,240,255,0.04) 1px,transparent 1px),
      linear-gradient(90deg,rgba(0,240,255,0.04) 1px,transparent 1px);
    background-size:40px 40px;
    mask-image:radial-gradient(ellipse at center,black 30%,transparent 80%);
  }
  /* 发光球 */
  .glow{position:absolute;width:600px;height:600px;border-radius:50%;
    background:radial-gradient(circle,rgba(0,240,255,0.15),transparent 70%);
    filter:blur(40px);animation:pulse 3s ease-in-out infinite;}
  @keyframes pulse{0%,100%{opacity:.5;transform:scale(1)}50%{opacity:.8;transform:scale(1.1)}}

  .center{position:relative;z-index:1;text-align:center;padding:40px}

  /* Logo */
  .logo{
    width:120px;height:120px;
    margin:0 auto 32px;
    background:linear-gradient(135deg,#00f0ff,#a855f7);
    border-radius:28px;
    display:flex;align-items:center;justify-content:center;
    font-weight:900;font-size:56px;color:#05060a;
    box-shadow:0 0 60px rgba(0,240,255,0.4),0 0 100px rgba(168,85,247,0.2);
    animation:float 3s ease-in-out infinite;
  }
  @keyframes float{0%,100%{transform:translateY(0)}50%{transform:translateY(-8px)}}

  h1{font-size:28px;font-weight:700;margin-bottom:12px;
    background:linear-gradient(90deg,#00f0ff,#a855f7);
    -webkit-background-clip:text;background-clip:text;color:transparent;
    letter-spacing:2px;}
  .sub{color:#94a3b8;font-size:14px;margin-bottom:40px;letter-spacing:1px}

  /* 加载环 */
  .ring{
    width:48px;height:48px;margin:0 auto 24px;
    border:3px solid rgba(0,240,255,0.15);
    border-top-color:#00f0ff;border-right-color:#a855f7;
    border-radius:50%;
    animation:spin 1s linear infinite;
  }
  @keyframes spin{to{transform:rotate(360deg)}}

  .step{font-size:13px;color:#64748b;font-family:Consolas,monospace;
    min-height:20px;transition:color .3s}
  .step.active{color:#00f0ff}
  .step.done{color:#4ade80}

  /* 进度条 */
  .bar{width:260px;height:3px;margin:20px auto 0;
    background:rgba(255,255,255,0.08);border-radius:2px;overflow:hidden;}
  .bar-fill{height:100%;width:0%;
    background:linear-gradient(90deg,#00f0ff,#a855f7);
    border-radius:2px;transition:width .4s ease;}
</style>
</head>
<body>
  <div class="glow"></div>
  <div class="center">
    <div class="logo">智</div>
    <h1>智北官网正在启动</h1>
    <div class="sub">ZHIBEI TECH · AI PLATFORM</div>
    <div class="ring"></div>
    <div class="bar"><div class="bar-fill" id="bar"></div></div>
    <div class="step active" id="step">🔧 正在初始化服务...</div>
  </div>
<script>
  const steps = [
    {t:"🔧 正在初始化服务...", p:25},
    {t:"🌐 正在启动网络服务...", p:55},
    {t:"🗄️ 正在加载数据模块...", p:80},
    {t:"✅ 即将就绪...", p:95},
  ];
  let i=0;
  const el=document.getElementById("step"), bar=document.getElementById("bar");
  const iv=setInterval(()=>{
    if(i>=steps.length){clearInterval(iv);return;}
    el.className="step";
    setTimeout(()=>{
      el.textContent=steps[i].t;
      el.className="step active";
      bar.style.width=steps[i].p+"%";
      i++;
    },150);
  },1400);
  window.updateStep = function(text, percent){
    el.textContent = text;
    el.className = "step done";
    if(percent) bar.style.width = percent + "%";
  };
  window._ready = false;
  window.markReady = function(){
    window._ready = true;
    el.textContent="✅ 服务就绪，正在跳转...";
    el.className="step done";
    bar.style.width="100%";
  };
</script>
</body>
</html>
"""


def run_webview_with_splash(timeout=25):
    """打开 pywebview 桌面窗口，先显示 splash 等待页，服务器就绪后自动跳转"""
    global WEBVIEW_OK
    if not WEBVIEW_OK:
        return False

    target_url = f"http://localhost:{PORT}"
    splash_html = _build_splash_html()

    # splash 写到临时文件（避免 data URL 在某些 WebView2 版本解析异常）
    import tempfile
    splash_path = os.path.join(tempfile.gettempdir(), "zhibei_splash.html")
    with open(splash_path, "w", encoding="utf-8") as f:
        f.write(splash_html)
    # 构造 file URL（经验教训：Windows 路径必须正斜杠 + URL 编码）
    splash_url = "file:///" + splash_path.replace("\\", "/").replace(" ", "%20")

    try:
        win = webview.create_window(
            title=WINDOW_TITLE,
            url=splash_url,
            width=1280,
            height=800,
            min_size=(1024, 640),
            text_select=True,
        )

        def poll_and_navigate():
            """后台线程：轮询服务器 → 就绪后通知 splash → 跳转官网"""
            print("[INFO] Polling for server (splash screen active) ...")
            for _ in range(timeout * 2):
                if is_server_alive():
                    print("[INFO] Server ready, navigating to website ...")
                    try:
                        win.evaluate_js("markReady();")
                        time.sleep(0.6)
                        win.load_url(target_url)
                    except Exception as e:
                        print("[WARN] Navigation error:", e)
                    return
                time.sleep(0.5)
            print("[WARN] Server not ready within splash timeout. Staying on splash.")

        threading.Thread(target=poll_and_navigate, daemon=True).start()

        print("[INFO] Opening desktop window (splash mode) ...")
        webview.start(debug=False)
        print("[INFO] Desktop window closed.")
        return True
    except Exception as e:
        print("[ERROR] pywebview failed:", e)
        WEBVIEW_OK = False
        return False


def run_webview():
    """打开 pywebview 桌面窗口（旧版：等待服务器就绪后直接加载官网）"""
    url = f"http://localhost:{PORT}"

    window = webview.create_window(
        title=WINDOW_TITLE,
        url=url,
        width=1280,
        height=800,
        min_size=(1024, 640),
        text_select=True,
    )

    print("[INFO] Opening desktop window ...")
    webview.start(debug=False)
    print("[INFO] Desktop window closed.")


def main():
    print("=" * 50)
    print("  智北科技 · 桌面端启动器")
    print("=" * 50)

    headless = "--headless" in sys.argv

    # Step 1: 检测 / 启动服务器（不阻塞，先开窗口显示 splash）
    server_was_alive = is_server_alive()
    if server_was_alive:
        print("[INFO] Server already running on port", PORT)
    else:
        print("[INFO] Starting server.ps1 in background ...")
        start_server()
        # 不再阻塞等待 —— splash 窗口会在后台自动轮询

    show_tray_info()

    # Step 2: --headless 模式只开服务器不开窗口
    if headless:
        print("[INFO] --headless mode: server running, no window.")
        print("[INFO] Press Ctrl+C to exit (but server will keep running).")
        try:
            while True:
                time.sleep(60)
        except KeyboardInterrupt:
            print("\n[INFO] Exiting. Server stays running.")
        return

    if not WEBVIEW_OK:
        print("[WARN] pywebview not available, falling back to browser.")
        print(f"[WARN] Error: {WEBVIEW_ERR}")
        print()
        try:
            import webbrowser
            webbrowser.open(f"http://localhost:{PORT}")
        except Exception:
            pass
        print("[INFO] Server running in background. Close this window to exit.")
        try:
            while True:
                time.sleep(60)
        except KeyboardInterrupt:
            pass
        return

    # Step 3: 打开桌面窗口（splash 等待页 → 就绪后自动跳转官网）
    if server_was_alive:
        # 服务器已就绪，也走 splash 流程（用户体验一致），poll_and_navigate 会很快跳转
        print("[INFO] Using splash mode (server already up, will navigate quickly) ...")
    else:
        print("[INFO] Using splash mode (server starting in background) ...")

    run_webview_with_splash(timeout=25)


if __name__ == "__main__":
    main()
