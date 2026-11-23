"""Snapshot Git worktrees into a navigable, offline file and declaration tree."""
from __future__ import annotations

import argparse
import ast
from collections import Counter
from datetime import datetime, timedelta, timezone
from functools import lru_cache
import io
import json
from pathlib import Path
import re
import subprocess
import tokenize

from tree_sitter_language_pack import get_parser

from media import write_sheets
from purpose import EXCLUSION_RULES, exclusion, purpose

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LANG = {
    '.gd': 'gdscript', '.cs': 'csharp', '.js': 'javascript', '.mjs': 'javascript',
    '.gdshader': 'glsl', '.gdshaderinc': 'glsl', '.glsl': 'glsl', '.fx': 'hlsl',
    '.c': 'c', '.h': 'c', '.cpp': 'cpp', '.cc': 'cpp', '.sh': 'bash',
    '.adb': 'ada', '.ads': 'ada', '.pas': 'pascal', '.sql': 'sql',
    '.htm': 'html', '.html': 'html', '.svg': 'html', '.tscn': 'scene', '.tres': 'scene',
    '.py': 'python', '.ps1': 'powershell', '.awk': 'awk', '.scss': 'scss',
    '.asm': 'assembly', '.s': 'assembly', '.bat': 'batch',
}
TYPES = {
    'class_definition': 'class', 'class_declaration': 'class', 'class': 'class',
    'struct_declaration': 'struct', 'struct_specifier': 'struct', 'class_specifier': 'class',
    'interface_declaration': 'interface', 'record_declaration': 'record',
    'namespace_declaration': 'namespace', 'file_scoped_namespace_declaration': 'namespace',
    'namespace_definition': 'namespace', 'property_declaration': 'property',
    'indexer_declaration': 'property', 'event_declaration': 'event', 'setget': 'property',
}
CALLS = {
    'function_definition': 'function', 'function_declaration': 'function',
    'generator_function_declaration': 'generator', 'generator_function': 'generator',
    'function_expression': 'function', 'arrow_function': 'lambda', 'lambda': 'lambda',
    'lambda_expression': 'lambda', 'anonymous_method_expression': 'lambda',
    'method_definition': 'method', 'method_declaration': 'method',
    'constructor_definition': 'constructor', 'get_body': 'accessor', 'set_body': 'accessor',
    'constructor_declaration': 'constructor', 'destructor_declaration': 'destructor',
    'local_function_statement': 'local function', 'operator_declaration': 'operator',
    'conversion_operator_declaration': 'operator', 'accessor_declaration': 'accessor',
    'delegate_declaration': 'delegate', 'preproc_function_def': 'macro',
    'create_function': 'function', 'create_procedure': 'procedure',
    'defFunc': 'function', 'defProc': 'procedure', 'declFunc': 'function', 'declProc': 'procedure',
    'subprogram_body': 'subprogram', 'subprogram_declaration': 'subprogram',
}
GROUPS = set(TYPES.values())


def git(base, *args):
    return subprocess.check_output(['git', '-C', str(base), *args]).decode('utf-8')


def entries(base, prefix='', repo_id='.'):
    changes = {}
    for s in git(base, 'status', '--porcelain=v1', '-z', '--no-renames', '--untracked-files=all',
                 '--ignore-submodules=none').split('\0'):
        if s:
            changes[s[3:]] = s[:2].strip()
    links = {}
    tracked = set()
    for s in git(base, 'ls-files', '-s', '-z').split('\0'):
        if s:
            meta, name = s.split('\t', 1)
            mode, sha, _ = meta.split()
            if mode == '160000':
                links[name] = sha
            else:
                tracked.add(name)
    extra = set(git(base, 'ls-files', '-o', '--exclude-standard', '-z').split('\0')) - {''}
    files, repos, absent = [], [], []
    for f in sorted(tracked | extra):
        p = base / f
        # The index lists symlinks themselves, never the files behind them.
        if p.is_symlink() or p.is_file():
            files.append(dict(path=prefix + f, repo=repo_id, status=changes.get(f, ''),
                              kind='symlink' if p.is_symlink() else 'file'))
        else:
            absent.append(prefix + f)
    for f, sha in links.items():
        p = base / f
        node = dict(path=prefix + f, repo=repo_id, status=changes.get(f, ''), kind='gitlink', commit=sha)
        files.append(node)
        node['initialized'] = (p / '.git').exists()
        if node['initialized']:
            nested, subrepos, subabsent = entries(p, prefix + f + '/', prefix + f)
            files.extend(nested)
            repos.extend(subrepos)
            absent.extend(subabsent)
    repos.insert(0, dict(path=repo_id, commit=git(base, 'rev-parse', 'HEAD').strip()))
    return files, repos, absent


def sym(name, kind, start, end, signature='', col=1, endcol=1):
    return dict(name=name, kind=kind, line=start, end=end, col=col, endcol=endcol,
                signature=' '.join(signature.split()))


def python_symbols(raw):
    text = raw.decode(tokenize.detect_encoding(io.BytesIO(raw).readline)[0])
    def visit(node):
        children = []
        for child in ast.iter_child_nodes(node):
            children.extend(visit(child))
        children.sort(key=lambda s: (s['line'], s['col']))
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda, ast.ClassDef)):
            if isinstance(node, ast.ClassDef):
                name, kind, signature = node.name, 'class', ''
            else:
                name = getattr(node, 'name', '<lambda>')
                kind = {ast.Lambda: 'lambda', ast.AsyncFunctionDef: 'async function'}.get(type(node), 'function')
                signature = '(' + ast.unparse(node.args) + ')'
                if getattr(node, 'returns', None) is not None:
                    signature += ' -> ' + ast.unparse(node.returns)
            s = sym(name, kind, node.lineno, node.end_lineno, signature, node.col_offset+1, node.end_col_offset+1)
            s['children'] = children
            return [s]
        return children
    return visit(ast.parse(text))


@lru_cache(None)
def parser(language):
    return get_parser(language)


def ts_symbols(raw, language, offset=0):
    tree = parser(language).parse(raw)
    issues = []
    def text(n):
        return raw[n.start_byte:n.end_byte].decode('utf-8', errors='replace') if n is not None else ''
    def field(n, *keys):
        for k in keys:
            v = n.child_by_field_name(k)
            if v is not None:
                return v
        return None
    def inspect(n, parent):
        typ = n.type
        kind = TYPES.get(typ) or CALLS.get(typ)
        if typ in ('declProc', 'declFunc') and parent is not None and parent.type in ('defProc', 'defFunc'):
            kind = None
        start = n.start_point.row + 1 + offset
        if n.is_error or n.is_missing:
            issues.append(f'{language} L{start}:{n.start_point.column+1}: {typ}' + (' (missing)' if n.is_missing else ''))
        if typ == 'script_element' and language == 'html':
            body = next((x for x in n.named_children if x.type == 'raw_text'), None)
            tag = text(n.named_children[0])
            if body and not re.search(r'type\s*=\s*[\"\']?(?!(?:module|(?:application|text)/(?:java|ecma)script)\b)[\w/+-]+', tag, re.I):
                embedded, errors = ts_symbols(b' ' * body.start_point.column + body.text, 'javascript', body.start_point.row + offset)
                issues.extend(errors)
                return embedded
        if not kind and not n.named_child_count and not n.has_error:
            return []
        children = []
        for child in n.children if n.has_error else n.named_children:
            if child.is_named or child.is_missing:
                children.extend(inspect(child, n))
        if not kind:
            return children
        header = field(n, 'header')
        if typ.startswith('subprogram_'):
            header = next((c for c in n.named_children if c.type.endswith('_specification')), None)
        target = header if header is not None else n
        name = text(field(target, 'name', 'operator'))
        params = field(target, 'parameters', 'parameter', 'arguments')
        if params is None:
            params = next((x for x in target.named_children if x.type in ('function_arguments', 'formal_part')), None)
        if not name and typ in ('create_function', 'create_procedure'):
            name = next((text(x) for x in n.named_children if x.type == 'object_reference'), '')
        decl = field(n, 'declarator')
        if not name and decl is not None:
            cursor = decl
            while cursor is not None:
                if cursor.type in ('identifier', 'field_identifier', 'qualified_identifier', 'destructor_name', 'operator_name'):
                    name = text(cursor)
                    break
                if params is None:
                    params = field(cursor, 'parameters')
                cursor = field(cursor, 'declarator')
        if typ == 'constructor_definition' and language == 'gdscript':
            name = '_init'
        if typ in ('get_body', 'set_body'):
            name = typ.split('_')[0]
        if typ == 'setget' and parent is not None:
            name = text(field(parent, 'name'))
        if typ == 'accessor_declaration':
            name = n.children[0].type if n.children[0].type in ('get','set','init','add','remove') else text(field(n, 'name'))
            if not name:
                name = next((x.type for x in n.children if x.type in ('get','set','init','add','remove')), '')
        if typ == 'conversion_operator_declaration':
            name = 'operator ' + text(field(n, 'type'))
        if typ == 'indexer_declaration':
            name = 'this[]'
        if not name and parent is not None and parent.type in ('variable_declarator', 'variable_statement', 'pair', 'assignment_expression', 'field_definition'):
            name = text(field(parent, 'name', 'key', 'left', 'property'))
        if typ == 'method_definition' and name == 'constructor':
            kind = 'constructor'
        elif typ == 'function_definition' and parent is not None and parent.type in ('class_body', 'field_declaration_list'):
            kind = 'method'
        if not name and kind in GROUPS and not children:
            return []
        sig = text(params)
        returns = text(field(n, 'return_type', 'returns'))
        if returns:
            sig += ' -> ' + returns
        end = n.end_point.row + 1 + offset - (1 if n.end_point.column == 0 and n.end_point.row > n.start_point.row else 0)
        s = sym(name or f'<{kind}>', kind, start, end, sig, n.start_point.column+1, n.end_point.column+1)
        s['children'] = children
        return [s]
    symbols = inspect(tree.root_node, None)
    if any(n.type == 'file_scoped_namespace_declaration' for n in tree.root_node.named_children):
        i = next((i for i, s in enumerate(symbols) if s['kind'] == 'namespace'), None)
        if i is not None:
            symbols[i]['children'].extend(symbols[i+1:])
            symbols = symbols[:i+1]
    return symbols, list(dict.fromkeys(issues))


def mask_comments(text):
    return re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'',
                  lambda m: re.sub(r'[^\n]', ' ', m[0]), text)


def lexical(text, pattern, kind):
    out = []
    for m in re.finditer(pattern, mask_comments(text), re.M):
        name = m[1]
        line = text.count('\n', 0, m.start(1)) + 1
        out.append(sym(name, kind, line, line, col=m.start(1)-text.rfind('\n', 0, m.start(1))))
    return out


def parse_source(path, language, ps):
    if language == 'powershell':
        row = ps[str(path)]
        stack, result = [], []
        for name, kind, a, b, sig, c, d in sorted(row['symbols'], key=lambda s: (s[2], s[5], -s[3], -s[6])):
            while stack and (a,c) >= (stack[-1]['end'],stack[-1]['endcol']):
                stack.pop()
            s = sym(name, kind, a, b, sig, c, d)
            s['children'] = []
            (stack[-1]['children'] if stack else result).append(s)
            stack.append(s)
        return result, row['issues'], 'PowerShell AST'
    raw = path.read_bytes()
    if language == 'python':
        return python_symbols(raw), [], 'Python AST'
    if language in ('assembly', 'batch', 'awk', 'scss'):
        patterns = {'assembly': (r'^\s*([.\w$@?]+)\s*(?::|\bPROC\b)', 'label'),
                    'batch': (r'^[ \t]*:(?!:)([\w.\-]+)', 'label'),
                    'awk': (r'^[ \t]*function\s+(\w+)\s*\(', 'function'),
                    'scss': (r'^[ \t]*@function\s+([\w-]+)\s*\(', 'function')}
        return lexical(raw.decode('utf-8-sig', errors='replace'), *patterns[language]), [], 'lexical'
    raw = raw.removeprefix(b'\xef\xbb\xbf')
    if language == 'scene':
        result, issues = [], []
        for m in re.finditer(rb'(?m)^script/source\s*=\s*"((?:[^"\\]|\\[\s\S])*)"', raw):
            unescaped = re.sub(rb'\\(["\\])', rb'\1', m[1])
            symbols, errors = ts_symbols(unescaped, 'gdscript', raw.count(b'\n', 0, m.start(1)))
            result.extend(symbols)
            issues.extend(errors)
        return result, issues, 'embedded GDScript' if result or issues else ''
    if language == 'glsl':
        raw = re.sub(rb'(?m)^#\[(?:compute|vertex|fragment)\][ \t]*', lambda m: b' ' * len(m[0]), raw)
    if language == 'glsl' and path.suffix.startswith('.gdshader'):
        # Godot-only directives and uniform hints are not GLSL; blank them while preserving coordinates.
        blank = lambda m: re.sub(rb'[^\n]', b' ', m[0])
        raw = re.sub(rb'(?m)^[ \t]*(?:shader_type|render_mode|group_uniforms)\b[^;]*;', blank, raw)
        raw = re.sub(rb'(?m)^(?P<prefix>[ \t]*(?:(?:global|instance)\s+)?uniform\b[^;=\n]*?)(:[^;=\n]*)',
                     lambda m: m['prefix'] + b' ' * len(m[2]), raw)
        raw = re.sub(rb'\b(?:global|instance)(?=\s+uniform\b)', blank, raw)
    if language == 'html' and not re.search(rb'<script\b', raw, re.I):
        return [], [], ''
    symbols, issues = ts_symbols(raw, language)
    return symbols, issues, f'Tree-sitter/{language}'


def walk_symbols(symbols):
    for s in symbols:
        yield s
        yield from walk_symbols(s.get('children', ()))


def collect(include_vendored=True):
    files, repositories, absent = entries(ROOT)
    if not include_vendored:
        files = [f for f in files if f['repo'] == '.']
        repositories = repositories[:1]
        absent = [f for f in absent if not f.startswith('vendor/')]
    excluded = Counter()
    kept = []
    for f in files:
        reason = exclusion(f['path'], ROOT) if f['kind'] != 'gitlink' else ''
        if reason:
            excluded[reason] += 1
        else:
            kept.append(f)
    files = sorted(kept, key=lambda f: (f['path'].casefold(), f['path']))
    absent = [p for p in absent if not exclusion(p, ROOT)]
    ps_paths = [str(ROOT / f['path']) for f in files if f['kind'] == 'file' and f['path'].lower().endswith('.ps1')]
    ps = {}
    if ps_paths:
        ps = json.loads(subprocess.check_output(
            ['pwsh', '-NoProfile', '-File', str(HERE / 'powershell_ast.ps1')],
            input=json.dumps(ps_paths).encode('ascii')).decode('utf-8-sig'))
    for f in files:
        p = ROOT / f['path']
        lang = LANG.get(p.suffix.lower())
        f.update(symbols=[], issues=[], parser='', count=0)
        if f['kind'] == 'file' and lang:
            try:
                f['symbols'], f['issues'], f['parser'] = parse_source(p, lang, ps)
            except (LookupError, OSError, SyntaxError, UnicodeError, ValueError) as ex:
                f['issues'] = [f'{lang}: {ex}']
                f['parser'] = f'{lang}/failed'
            f['count'] = sum(s['kind'] not in GROUPS and s['kind'] != 'label' for s in walk_symbols(f['symbols']))
        if not f['count'] and f['kind'] != 'gitlink':
            f['purpose'] = purpose(f['path'], ROOT, f['kind'])
    totals = {}
    for key, selection in [('project', [f for f in files if f['repo'] == '.']),
                           ('vendor', [f for f in files if f['repo'] != '.'])]:
        totals[key] = dict(files=sum(f['kind'] != 'gitlink' for f in selection),
                           functions=sum(f['count'] for f in selection),
                           issues=sum(bool(f['issues']) for f in selection),
                           parsers=dict(Counter(f['parser'] for f in selection if f['parser'])))
    return dict(root=ROOT.name, created=datetime.now(timezone(timedelta(hours=8))).isoformat(timespec='seconds'),
                exclusions=dict(rules=EXCLUSION_RULES, counts=dict(excluded)),
                repositories=repositories, absent=sorted(absent), totals=totals, files=files)


def text_tree(data):
    tree = {}
    for f in data['files']:
        parts = f['path'].split('/')
        node = tree
        for p in parts:
            node = node.setdefault(p, {'children': {}})['children']
        node[None] = f
    def emit_symbols(symbols, prefix, lines):
        for i, s in enumerate(symbols):
            last = i == len(symbols)-1
            lines.append(f'{prefix}{"└── " if last else "├── "}{s["kind"]} {s["name"]}{s["signature"]}  [L{s["line"]}:{s["col"]}–{s["end"]}]')
            emit_symbols(s.get('children', ()), prefix+('    ' if last else '│   '), lines)
    def emit(node, prefix, lines):
        keys = sorted((k for k in node if k is not None), key=lambda k: (not any(x is not None for x in node[k]['children']),k.casefold(),k))
        for i, key in enumerate(keys):
            last = i == len(keys)-1
            child = node[key]['children']
            f = child.get(None)
            sub = prefix + ('    ' if last else '│   ')
            label = key + ('/' if f is None or f['kind'] == 'gitlink' else '')
            if f:
                if f['kind'] == 'gitlink':
                    label += f' [gitlink {f["commit"]}; {"present" if f["initialized"] else "not initialized"}]'
                elif f['status']:
                    label += f' [{f["status"]}]'
                if f['issues']:
                    label += f' [parse notices: {len(f["issues"])}]'
                if f.get('purpose'):
                    label += ' — ' + f['purpose']
                if f.get('media'):
                    label += f' [{f["media"]["sheet"]} #{f["media"]["card"]:02}]'
            lines.append(prefix+('└── ' if last else '├── ')+label)
            emit(child, sub, lines)
            if f:
                emit_symbols(f['symbols'], sub, lines)
    lines = [data['root'] + '/', f'Git 工作树 · {data["created"]} · {data["repositories"][0]["commit"]}', '排除规则：',
             *('  - '+rule for rule in data['exclusions']['rules']), '']
    emit(tree, '', lines)
    lines.append('\n解析提示：')
    lines.extend(f'{f["path"]}: ' + '; '.join(f['issues']) for f in data['files'] if f['issues'])
    lines.append('\n索引中登记、工作树缺失：')
    lines.extend(data['absent'])
    return '\n'.join(lines)+'\n'


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--project-only', action='store_true', help='keep gitlinks but skip vendor contents')
    args = cli.parse_args()
    data = collect(not args.project_only)
    out = ROOT / '.runtime' / 'project-tree'
    out.mkdir(parents=True, exist_ok=True)
    data['gallery'] = write_sheets(data, ROOT, out)
    blob = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    (out / 'index.json').write_text(blob+'\n', encoding='utf-8')
    (out / 'tree.txt').write_text(text_tree(data), encoding='utf-8')
    template = (HERE / 'viewer.html').read_text(encoding='utf-8')
    (out / 'index.html').write_text(template.replace('<!-- SNAPSHOT -->', blob.replace('<', '\\u003c')), encoding='utf-8')
    print(json.dumps(dict(totals=data['totals'], exclusions=data['exclusions']['counts'],
                          sheets=len(data['gallery'])), indent=2))


if __name__ == '__main__':
    main()
