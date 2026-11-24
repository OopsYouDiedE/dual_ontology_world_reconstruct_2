"""Loopback-only human ballot. Start from the repository with python -B."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sqlite3
from queue_review import DEFAULT, HERE, connect, report, select, vote


def serve(root,port):
    host=f'127.0.0.1:{port}'
    class Handler(BaseHTTPRequestHandler):
        def reply(self,data,typ='application/json; charset=utf-8',status=200):
            if not isinstance(data,bytes):data=json.dumps(data,ensure_ascii=False).encode()
            self.send_response(status);self.send_header('Content-Type',typ);self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.send_header('X-Frame-Options','DENY');self.end_headers();self.wfile.write(data)
        def do_GET(self):
            if self.headers.get('Host')!=host:return self.reply('invalid host',status=403)
            try:
                if self.path=='/':return self.reply((HERE/'queue.html').read_bytes(),'text/html; charset=utf-8')
                with connect(root) as db:
                    if self.path=='/state':
                        db.execute('BEGIN IMMEDIATE');data=dict(card=select(db,root),report=report(db));db.commit();return self.reply(data)
                    if self.path.startswith('/media/'):
                        row=db.execute('SELECT card FROM trials WHERE id=?',(self.path[7:],)).fetchone()
                        if row:
                            f=root/json.loads(row[0])['media'];return self.reply(f.read_bytes(),{'.png':'image/png','.jpg':'image/jpeg','.mp4':'video/mp4'}[f.suffix])
                self.reply('not found',status=404)
            except (KeyError,OSError,ValueError,sqlite3.Error) as e:self.reply(str(e),status=409)
        def do_POST(self):
            if self.path!='/vote' or self.headers.get('Host')!=host or self.headers.get('Origin')!='http://'+host or self.headers.get('Content-Type')!='application/json':return self.reply('invalid request',status=403)
            try:
                size=int(self.headers.get('Content-Length','0'))
                if not 0<size<=8192:raise ValueError('invalid body size')
                v=json.loads(self.rfile.read(size))
                with connect(root) as db:
                    db.execute('BEGIN IMMEDIATE');vote(db,root,v['id'],v['choice'],v.get('note',''))
                self.reply('saved')
            except (TypeError,KeyError,ValueError,OSError,sqlite3.Error) as e:self.reply(str(e),status=409)
    ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()


if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,default=DEFAULT);ap.add_argument('--port',type=int,default=18764);a=ap.parse_args();serve(a.root,a.port)
