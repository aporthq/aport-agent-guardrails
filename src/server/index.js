#!/usr/bin/env node
/**
 * APort API Proxy Server
 * 
 * Simple proxy that forwards requests to the agent-passport API server.
 * The evaluation engine runs in agent-passport, not in this repo.
 * 
 * This server is optional - you can call agent-passport API directly.
 */

const http = require('http');
const url = require('url');

const PORT = process.env.PORT || 8788; // Different port to avoid conflict
const APORT_API_BASE = process.env.APORT_API_BASE || 'https://api.aport.io';

const server = http.createServer(async (req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  const parsedUrl = url.parse(req.url, true);
  
  // Proxy all requests to agent-passport API
  const targetUrl = `${APORT_API_BASE}${parsedUrl.pathname}${parsedUrl.search || ''}`;
  
  let body = '';
  req.on('data', chunk => { body += chunk.toString(); });
  req.on('end', () => {
    // Forward request to agent-passport API
    const options = {
      hostname: url.parse(APORT_API_BASE).hostname,
      port: url.parse(APORT_API_BASE).port || (url.parse(APORT_API_BASE).protocol === 'https:' ? 443 : 80),
      path: parsedUrl.pathname + (parsedUrl.search || ''),
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };

    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', (error) => {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        error: 'api_server_unavailable',
        message: `Cannot connect to APort API at ${APORT_API_BASE}. Make sure agent-passport server is running: cd agent-passport && npm run dev`
      }));
    });

    proxyReq.write(body);
    proxyReq.end();
  });
});

server.listen(PORT, () => {
  console.log(`🚀 APort API Proxy Server running on http://localhost:${PORT}`);
  console.log(`📡 Proxying to: ${APORT_API_BASE}`);
  console.log(`\n💡 Note: This is a simple proxy. The evaluation engine runs in agent-passport.`);
  console.log(`   Start agent-passport server: cd agent-passport && npm run dev\n`);
});
