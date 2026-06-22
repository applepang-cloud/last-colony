// Minimal static server for local verification of the release web build.
const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '_localtest');
const port = 8877;
const mime = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.wav': 'audio/wav', '.otf': 'font/otf', '.ttf': 'font/ttf', '.ico': 'image/x-icon',
  '.bin': 'application/octet-stream', '.symbols': 'text/plain',
};

http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p.endsWith('/')) p += 'index.html';
  let file = path.join(root, p);
  if (!file.startsWith(root)) { res.writeHead(403); return res.end('no'); }
  fs.readFile(file, (err, data) => {
    if (err) {
      // SPA fallback to the app's index for unknown paths under /last-colony/
      const idx = path.join(root, 'last-colony', 'index.html');
      return fs.readFile(idx, (e2, d2) => {
        if (e2) { res.writeHead(404); return res.end('404'); }
        res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
        res.end(d2);
      });
    }
    res.writeHead(200, {
      'Content-Type': mime[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    res.end(data);
  });
}).listen(port, '127.0.0.1', () => console.log('serving _localtest on http://127.0.0.1:' + port));
