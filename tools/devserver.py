#!/usr/bin/env python3
"""本地联调服务器：静态托管 web/，并把 /cgi-bin/pulse 交给真正的 ucode 采集器执行
（数据来自 router/test 下的假根目录，计数器随时间增长）。用于在没有路由器时测试「实时模式」整条链路。
用法：python3 tools/devserver.py [端口]   需要先编译 ucode（见 README「开发」一节）"""
import http.server, os, subprocess, sys, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA19 = os.environ.get('PULSE_COLLECTOR') == 'lua19'   # lua19 = 测试 19.07 的 Lua 采集器
TEST = os.path.join(ROOT, 'router19' if LUA19 else 'router', 'test')
U = os.environ.get('UCODE_BUILD', '/tmp/ucode-src/build')
START = time.time()
TICK = os.environ.get('PULSE_DEV_TICK') == '1'   # 1 = 每个请求算 1 秒（配合无头 Chrome 的虚拟时间截图）
N = [0]

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=os.path.join(ROOT, 'web'), **k)
    def log_message(self, *a): pass
    def do_GET(self):
        if not self.path.startswith('/cgi-bin/pulse'): return super().do_GET()
        N[0] += 1
        t = N[0] if TICK else int(time.time() - START)
        subprocess.run([os.path.join(TEST, 'make-fixture.sh'), str(t)], stdout=subprocess.DEVNULL, check=True)
        env = dict(os.environ, PATH=os.path.join(TEST, 'bin') + ':' + os.environ['PATH'], PULSE_ROOT=os.path.join(TEST, 'root'),
                   LD_LIBRARY_PATH=U, QUERY_STRING=self.path.partition('?')[2], REQUEST_METHOD='GET',
                   HTTP_X_PULSE_TOKEN=self.headers.get('X-Pulse-Token', ''))
        if TICK: env['PULSE_FAKE_TS'] = str(int(START * 1000) + t * 1000); env['PULSE_FAKE_MONO'] = str(t * 1000)
        if LUA19:
            env['PULSE_STATE'] = os.path.join(TEST, 'state-dev')
            out = subprocess.run(['lua5.1', os.path.join(ROOT, 'router19', 'files', 'www', 'cgi-bin', 'pulse')], env=env, capture_output=True).stdout
        else:
            out = subprocess.run([os.path.join(U, 'ucode'), '-L', U + '/*.so', '-L', TEST + '/lib/*.uc', '-S',
                                  os.path.join(ROOT, 'router', 'files', 'www', 'cgi-bin', 'pulse')], env=env, capture_output=True).stdout
        head, _, body = out.partition(b'\r\n\r\n')
        status = 200
        lines = head.decode().split('\r\n')
        if lines and lines[0].startswith('Status:'): status = int(lines.pop(0).split()[1])
        self.send_response(status)
        for l in lines:
            k, _, v = l.partition(':'); self.send_header(k.strip(), v.strip())
        self.end_headers(); self.wfile.write(body)

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8780
print(f'http://127.0.0.1:{port}/  (实时模式，数据来自假根目录)')
http.server.ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
