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


def run_webview():
    """打开 pywebview 桌面窗口"""
    url = f"http://localhost:{PORT}"
    local_ip = find_local_ip()

    # 创建主窗口
    window = webview.create_window(
        title=WINDOW_TITLE,
        url=url,
        width=1280,
        height=800,
        min_size=(1024, 640),
        text_select=True,
    )

    # 启动
    print("[INFO] Opening desktop window ...")
    webview.start(debug=False)
    print("[INFO] Desktop window closed.")


def main():
    print("=" * 50)
    print("  智北科技 · 桌面端启动器")
    print("=" * 50)

    headless = "--headless" in sys.argv

    # Step 1: 检测 / 启动服务器
    if is_server_alive():
        print("[INFO] Server already running on port", PORT)
    else:
        print("[INFO] Starting server.ps1 ...")
        start_server()
        if not wait_for_server(timeout=20):
            print("[FATAL] Server failed to start within 20s.")
            print("        Try running:  powershell -File server.ps1")
            input("Press Enter to exit ...")
            sys.exit(1)

    show_tray_info()

    # Step 2: 打开桌面窗口
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
        # fallback: 用系统浏览器打开
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

    run_webview()


if __name__ == "__main__":
    main()
