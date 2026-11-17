import html
import ast
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXTENSIONS = {'.gd', '.cs', '.py', '.js', '.ts', '.tscn', '.csproj', '.ps1', '.sh'}
EXCLUDED = {'.git', '.godot', '.runtime', 'artifacts', 'outputs', 'output', 'node_modules'}


def main():
    files = []
    for base in ROOT.iterdir():
        if base.name in EXCLUDED:
            continue
        candidates = base.rglob('*') if base.is_dir() else [base]
        files.extend(p for p in candidates if p.is_file() and p.suffix.lower() in EXTENSIONS and not EXCLUDED.intersection(p.relative_to(ROOT).parts))
    files.sort()
    paths = {p.relative_to(ROOT).as_posix(): p for p in files}
    contents = {name: path.read_text(encoding='utf-8-sig', errors='replace') for name, path in paths.items()}
    classes = {}
    modules = {}
    for name, source in contents.items():
        if name.endswith('.cs'):
            for match in re.finditer(r'\b(?:class|interface|struct|enum|record)\s+(\w+)', source):
                classes.setdefault(match.group(1), set()).add(name)
        if name.endswith('.py'):
            modules.setdefault(Path(name).stem, set()).add(name)
    edges = set()
    for name, source in contents.items():
        for match in re.finditer(r'res://([^"\'\s)]+)', source):
            target = match.group(1)
            if target in paths and target != name:
                edges.add((name, target, '资源路径'))
        if name.endswith('.py'):
            for match in re.finditer(r'^\s*(?:from\s+([\w.]+)\s+import|import\s+([\w.]+))', source, re.M):
                module = (match.group(1) or match.group(2)).split('.')[-1]
                candidates = modules.get(module, set())
                for target in candidates:
                    if target != name:
                        edges.add((name, target, 'Python 导入候选'))
        if name.endswith('.cs'):
            for word in set(re.findall(r'\b[A-Z]\w+\b', source)):
                candidates = classes.get(word, set())
                if len(candidates) == 1:
                    target = next(iter(candidates))
                    if target != name:
                        edges.add((name, target, 'C# 类型名候选'))
        if name.endswith('.csproj'):
            for match in re.finditer(r'<ProjectReference\s+Include="([^"]+)"', source):
                target = (Path(name).parent / match.group(1).replace('\\', '/')).as_posix()
                if target in paths:
                    edges.add((name, target, '项目引用'))
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    functions = []
    for name, source in contents.items():
        lines = source.splitlines()
        definitions = []
        if name.endswith('.py'):
            try:
                tree = ast.parse(source)
                definitions = [(node.lineno, node.end_lineno, node.name) for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))]
            except SyntaxError:
                pass
        elif name.endswith('.gd'):
            matches = list(re.finditer(r'^(?:static\s+)?func\s+(\w+)\s*\(', source, re.M))
            definitions = [(source.count('\n', 0, match.start()) + 1, source.count('\n', 0, matches[index + 1].start()) if index + 1 < len(matches) else len(lines), match.group(1)) for index, match in enumerate(matches)]
        elif name.endswith('.cs'):
            matches = list(re.finditer(r'^\s*(?:(?:public|private|protected|internal|static|async|virtual|override|sealed|partial|new|extern)\s+)+(?:[\w<>,?\[\].]+\s+)+(\w+)\s*\([^;\n]*\)', source, re.M))
            definitions = [(source.count('\n', 0, match.start()) + 1, source.count('\n', 0, matches[index + 1].start()) if index + 1 < len(matches) else len(lines), match.group(1)) for index, match in enumerate(matches)]
        for start, end, func in definitions:
            body = '\n'.join(lines[start:end])
            calls = sorted(set(re.findall(r'\b([A-Za-z_]\w*)\s*\(', body)) - {func, 'if', 'for', 'while', 'match', 'return', 'await', 'assert'})
            functions.append([name, start, func, calls])
    payload = json.dumps({'files': list(paths), 'edges': sorted(edges), 'functions': functions, 'revision': revision}, ensure_ascii=False).replace('</', '<\\/')
    page = TEMPLATE.replace('/*DATA*/', payload)
    page = page.replace('<a href="#flow">主线数据流</a>', '<a href="#guide">从这里开始</a><a href="#functions">函数检索</a><a href="#flow">主线数据流</a>')
    page = page.replace('<section id="flow">', GUIDE + '<section id="flow">')
    page = page.replace('<section id="inventory">', FUNCTION_SECTION + '<section id="inventory">')
    page = page.replace('render();\n+</script>', 'render();\n+</script>')
    page = page.replace('</script></body></html>', FUNCTION_SCRIPT + '</script></body></html>')
    (ROOT / 'project-map.html').write_text(page, encoding='utf-8')
    print(f'{len(files)} files, {len(edges)} edges, {len(functions)} functions')


GUIDE = r'''<section id="guide"><h2>先看这一条线</h2><p>把项目想成一场演出：<b>启动器</b>打开标题，<b>主控</b>创建游戏，<b>规则</b>保存与更新状态，<b>演出组件</b>把状态变成画面和互动。需要追查时，再打开下面的函数索引。</p><div class="flow"><div class="node"><b>1 · 进入标题</b><br><code>Boot._ready()</code> → <code>Main._ready()</code> → <code>Main._title_setup()</code></div><span class="arrow">→</span><div class="node"><b>2 · 创建新局</b><br>标题按钮信号 → <code>Main.open_dual_world()</code> → <code>DualWorldMain._ready()</code></div><span class="arrow">→</span><div class="node"><b>3 · 开场交互</b><br><code>_start_opening()</code> → <code>WakeOpening.begin()</code> → 卧室调查 → <code>start_gathering()</code></div></div><p class="muted">第一遍只需读这三张卡片；其余内容在需要追查时展开。</p></section>'''

FUNCTION_SECTION = r'''<section id="functions"><h2>函数检索</h2><p>先选择一个文件，再输入函数名称。展开后查看该函数里的调用名称；点击名称可搜索项目中的同名定义。</p><select id="function-file"><option value="">先选择代码文件</option></select> <input id="function-query" placeholder="筛选函数名称，例如 _ready"><div id="function-count" class="muted"></div><div id="function-results"></div><p class="muted">函数边是源码中的调用名称候选，包含引擎和内置调用。同名函数、信号回调、动态调用及 C# 重载需要结合源码判断；Python 采用语法树提取定义，GDScript 与 C# 采用静态模式提取。</p></section>'''

FUNCTION_SCRIPT = r'''
const fnFile=document.querySelector('#function-file'),fnQuery=document.querySelector('#function-query'),fnResults=document.querySelector('#function-results');
for(const p of [...new Set(data.functions.map(f=>f[0]))].sort()){const o=document.createElement('option');o.value=p;o.textContent=p;fnFile.append(o)}
function showFunctions(){const path=fnFile.value,q=fnQuery.value.toLowerCase();if(!path&&!q){fnResults.innerHTML='';document.querySelector('#function-count').textContent=`共索引 ${data.functions.length} 个函数；选择文件或搜索后显示。`;return}const found=data.functions.filter(f=>(!path||f[0]===path)&&(!q||f[2].toLowerCase().includes(q)));document.querySelector('#function-count').textContent=`找到 ${found.length} 个函数，最多显示前 100 个`;fnResults.innerHTML=found.slice(0,100).map(([p,line,name,calls])=>`<details><summary><code>${esc(name)}()</code> <span class="muted">${esc(p)}:${line}</span></summary><p>调用名称：${calls.length?calls.map(c=>`<button type="button" class="call-search" data-name="${esc(c)}">${esc(c)}()</button>`).join(' '):'未识别到调用'}</p></details>`).join('')}
fnResults.addEventListener('click',e=>{const button=e.target.closest('.call-search');if(button){fnFile.value='';fnQuery.value=button.dataset.name;showFunctions();document.querySelector('#functions').scrollIntoView()}});fnFile.addEventListener('change',showFunctions);fnQuery.addEventListener('input',showFunctions);showFunctions();
'''

TEMPLATE = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>项目代码、主线与测试地图</title>
<style>
:root{color-scheme:dark;--bg:#101820;--card:#1a2833;--line:#405868;--ink:#e8f0ec;--muted:#a9bbc0;--accent:#8ee0be;--gold:#eac987}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 system-ui,'Microsoft YaHei',sans-serif}header,main{max-width:1400px;margin:auto;padding:28px}header{padding-top:48px}h1{font-size:clamp(29px,4vw,48px);margin:0}h2{margin-top:0}a{color:var(--accent)}nav{display:flex;gap:20px;flex-wrap:wrap;margin-top:20px}.intro,.muted{color:var(--muted)}section{background:var(--card);border:1px solid #2d414b;border-radius:14px;padding:24px;margin:0 0 18px}.stats,.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px}.stat,.card{padding:15px;background:#12202a;border-radius:9px}.stat strong{font-size:25px;color:var(--gold);display:block}.flow{display:flex;flex-wrap:wrap;align-items:stretch;gap:8px}.node{background:#12202a;border:1px solid var(--line);border-radius:8px;padding:12px;flex:1 1 170px}.arrow{align-self:center;color:var(--gold);font-size:22px}.tag{font-size:12px;color:var(--gold)}code{color:#bce6d5;overflow-wrap:anywhere}input,select{background:#101b23;color:var(--ink);border:1px solid #526b75;border-radius:7px;padding:10px;font:inherit}input{width:min(600px,100%)}button{background:#295f51;color:white;border:0;border-radius:6px;padding:7px 11px;cursor:pointer}table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:left;border-bottom:1px solid #344954;padding:8px;vertical-align:top}th{color:var(--gold)}.scroll{overflow:auto;max-height:650px}details{margin:10px 0}summary{cursor:pointer;color:var(--accent)}.badge{color:var(--gold)}footer{color:var(--muted);padding:20px} @media(max-width:650px){header,main{padding:16px}.arrow{display:none}}
</style></head><body><header><div class="tag">DUAL ONTOLOGY · PROJECT ATLAS</div><h1>项目代码、主线与测试地图</h1><p class="intro">代码清单、可检索的文件引用、开场实机轨迹与开发测试入口。数据来自当前工作区及项目内留存的录制。</p><nav><a href="#flow">主线数据流</a><a href="#evidence">实机记录</a><a href="#branches">测试旁支</a><a href="#inventory">全部代码文件</a><a href="#method">阅读方法</a></nav></header><main>
<section><div class="stats"><div class="stat"><strong id="file-count"></strong>代码与场景文件</div><div class="stat"><strong id="edge-count"></strong>识别出的文件关系</div><div class="stat"><strong>125.21 s</strong>开场连续录制</div><div class="stat"><strong>6 项</strong>录制中的卧室调查</div></div><p class="muted">工作区基准提交：<code id="revision"></code>；包含生成时存在的未提交修改。文件清单不包含运行时、生成物和证据目录。</p></section>
<section id="flow"><h2>正式主线：启动到开场</h2><p>箭头表示场景切换、实例化或状态传递；下方的阶段顺序由开场录制覆盖报告提供。</p><div class="flow"><div class="node"><b>Godot 启动</b><br><code>project.godot</code><br>注册音频、设置与 MCP 自动加载项</div><span class="arrow">→</span><div class="node"><b>启动检查</b><br><code>Boot.tscn → Boot.gd</code><br>检查 .NET 桥接；快照参数可直达游戏</div><span class="arrow">→</span><div class="node"><b>标题与菜单</b><br><code>Main.tscn → Main.gd → TitleUI</code><br>正式新局信号进入双本体场景</div><span class="arrow">→</span><div class="node"><b>游戏状态</b><br><code>DualWorldMain.gd</code><br>装配 DualData、DualEngine、房间、交互和开场组件</div><span class="arrow">→</span><div class="node"><b>画面与输入</b><br><code>WakeOpening / InteractionDirector</code><br>角色、房间、字幕、调查与状态更新</div></div><p>游戏状态经自动存档／手动存档写入 <code>user://dual_world/</code>；隔离槽位通过 <code>--dv-save-slot</code> 选择。推演与证物结果由游戏状态驱动界面与后续事件。</p></section>
<section id="evidence"><h2>实机轨迹与数据来源</h2><div class="flow"><div class="node"><b>卧室醒来</b><br>black → fade → lie → sit → look → talk → getup → free<br><span class="tag">11 句台词 · 15 个字幕片段</span></div><span class="arrow">→</span><div class="node"><b>卧室调查</b><br>bed · lamp · desk · window · wardrobe · wash<br><span class="tag">记录中完成 6 项</span></div><span class="arrow">→</span><div class="node"><b>走廊会合</b><br>fadeout → exit → hear → approach → join → talk → card → free<br><span class="tag">10 句台词</span></div></div><p>录制于 2026-11-16，宿主 PID 38364，录制版本 <code>5413448a39189c90f1e518818477999055e1318c</code>。覆盖报告标记开发录制，验收资格为 false；其音频信号为 false。当前工作区版本见页首，代码关系与历史录制分别取自各自来源。</p><p><a href="artifacts/acceptance/opening-complete-20261116-v1/complete.mp4">观看连续录制</a> · <a href="artifacts/acceptance/opening-complete-20261116-v1/coverage.json">覆盖报告</a> · <a href="artifacts/acceptance/opening-complete-20261116-v1/sequence.json">逐帧事件</a> · <a href="artifacts/acceptance/opening-complete-20261116-v1/launch.json">启动记录</a> · <a href="artifacts/story-capture-20261114-terra/timeline.json">五日实机时间线</a></p><p class="muted">五日记录的覆盖统计为 113 个原生快照、274 条事件；末份状态到第 5 日 <code>d5_end</code>。录制中的读档回访及选择见原始覆盖报告。</p></section>
<section id="branches"><h2>测试与工具旁支</h2><div class="cards"><div class="card"><b>章节与房间快检</b><p><code>mcp/evaluation/</code> 与 <code>scenes/components/testing/</code>：chapter1_ui、chapter1_flow、room_fast、kitchen_click、scenario；快照用于开发定位。</p></div><div class="card"><b>剧情和交互回归</b><p><code>tools/test/</code>：flow、kitchen、checkpoint、动作、寻路、截图和 UI 合约等脚本。</p></div><div class="card"><b>采集与评审</b><p><code>tools/testing/</code> 与 <code>mcp/review/</code>：录制、覆盖验证、盲读材料、评分和 HTML 导出；验收证据另行标识。</p></div><div class="card"><b>生活模拟 / CLI</b><p><code>mcp/game/</code> 与 <code>core/</code>：C# DV、推理、运行时，自动运行及输入客户端；标题可进入生活测试场景。</p></div><div class="card"><b>建筑与角色工具</b><p><code>tools/building_construction/</code>、<code>mcp/building/</code>、角色和动画探针：建筑编辑、组件工厂及资源诊断。</p></div><div class="card"><b>构建与环境</b><p><code>tools/build/</code>、项目文件和解决方案：构建 .NET 桥接、打开编辑器及准备宿主。</p></div></div><p>下方文件清单可按 <code>tools/test</code>、<code>mcp</code> 或具体名称筛选，逐一查看旁支文件及其识别出的关系。</p></section>
<section id="inventory"><h2>全部代码文件与相互依赖</h2><p>输入路径、文件名或类型名筛选；点击文件查看入边与出边。关系方向为「引用方 → 被引用方」。</p><input id="search" placeholder="例如 DualEngine、tools/test、.cs"><select id="kind"><option value="">所有目录</option></select><div id="count" class="muted"></div><div class="scroll"><table><thead><tr><th>文件</th><th>出边</th><th>入边</th><th>关系明细</th></tr></thead><tbody id="rows"></tbody></table></div></section>
<section id="method"><h2>阅读方法与范围</h2><p>收录工作区内 <code>.gd .cs .py .js .ts .tscn .csproj .ps1 .sh</code> 文件，包含当前未跟踪文件；排除 Git、Godot 缓存、运行时、输出和证据目录。资源路径依据源码中的 <code>res://</code> 字面量，C# 根据唯一类型名匹配，Python 根据模块名匹配；后两者标为候选。</p><p>动态拼接路径、反射、信号、运行时生成对象、引擎内置调用、DV 数据、外部包与脚本间的隐式调用需要结合源码和运行记录继续追踪。无边文件仍保留在清单中；图中的关系是可检索的静态线索。</p></section><footer>依据项目工作区生成 · 本页为本地离线 HTML</footer></main>
<script>
const data=/*DATA*/;const byFrom=new Map(),byTo=new Map();for(const [a,b,t] of data.edges){if(!byFrom.has(a))byFrom.set(a,[]);if(!byTo.has(b))byTo.set(b,[]);byFrom.get(a).push([b,t]);byTo.get(b).push([a,t])}const esc=s=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));document.querySelector('#file-count').textContent=data.files.length;document.querySelector('#edge-count').textContent=data.edges.length;document.querySelector('#revision').textContent=data.revision;const kind=document.querySelector('#kind');for(const x of [...new Set(data.files.map(p=>p.split('/')[0]))].sort()){const o=document.createElement('option');o.value=x;o.textContent=x;kind.append(o)}function render(){const q=document.querySelector('#search').value.toLowerCase(),k=kind.value;const found=data.files.filter(f=>f.toLowerCase().includes(q)&&(!k||f.split('/')[0]===k));document.querySelector('#count').textContent=`显示 ${found.length} / ${data.files.length} 个文件`;document.querySelector('#rows').innerHTML=found.map(f=>{const out=byFrom.get(f)||[],inc=byTo.get(f)||[];const list=(xs)=>xs.length?xs.map(([p,t])=>`<li><code>${esc(p)}</code> <span class="muted">${esc(t)}</span></li>`).join(''):'<li>未识别到静态关系</li>';return `<tr><td><a href="${encodeURI(f)}"><code>${esc(f)}</code></a></td><td>${out.length}</td><td>${inc.length}</td><td><details><summary>展开</summary><b>引用</b><ul>${list(out)}</ul><b>被引用</b><ul>${list(inc)}</ul></details></td></tr>`}).join('')}document.querySelector('#search').addEventListener('input',render);kind.addEventListener('change',render);render();
</script></body></html>'''


if __name__ == '__main__':
    main()
