#!/usr/bin/env node
/**
 * FRIDAY API Server - FREE TIER VERSION
 * Optimized for Render Free tier with SQLite
 * 
 * COLD START BEHAVIOR:
 * - Render Free tier spins down after 15 min of inactivity
 * - First request after spin-down triggers cold start (~30-60 seconds)
 * - Subsequent requests are fast while instance is awake
 * - SQLite data persists across restarts (stored on Render Disk)
 * 
 * MITIGATION STRATEGIES:
 * 1. UptimeRobot pings /api/health every 14 minutes (keeps warm)
 * 2. Leaderboard submissions are queued and retry on 503
 * 3. Static content served from Cloudflare Pages (always fast)
 */

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;
const START_TIME = Date.now();

// Configuration
const config = {
  env: process.env.NODE_ENV || 'development',
  version: process.env.APP_VERSION || '1.0.0',
  adminToken: process.env.ADMIN_TOKEN,
  apiKey: process.env.API_KEY,
  rateLimitWindow: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000,
  rateLimitMax: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
  leaderboardRateLimit: parseInt(process.env.LEADERBOARD_RATE_LIMIT) || 10,
  enableLeaderboard: process.env.ENABLE_LEADERBOARD !== 'false',
  enableAnalytics: process.env.ENABLE_ANALYTICS !== 'false',
  enablePublicStats: process.env.ENABLE_PUBLIC_STATS !== 'false',
  corsOrigins: (process.env.CORS_ORIGINS || 'https://friday-boi.pages.dev').split(',')
};

// Ensure data directory exists
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Database setup with connection pooling for SQLite
const DB_PATH = process.env.DATABASE_URL?.replace('sqlite:', '') || path.join(DATA_DIR, 'leaderboard.db');
let db;

try {
  db = new Database(DB_PATH);
  db.pragma('journal_mode = WAL');  // Write-ahead logging for better concurrency
  db.pragma('synchronous = NORMAL');
  console.log(`[${new Date().toISOString()}] Database connected: ${DB_PATH}`);
} catch (error) {
  console.error(`[${new Date().toISOString()}] Database connection failed:`, error);
  process.exit(1);
}

// Create tables (base schema - migrations add new columns)
db.exec(`
  CREATE TABLE IF NOT EXISTS submissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    instance_id TEXT UNIQUE NOT NULL,
    score INTEGER NOT NULL,
    os TEXT,
    arch TEXT,
    timestamp TEXT NOT NULL,
    network_score INTEGER DEFAULT 0,
    perm_score INTEGER DEFAULT 0,
    gateway_score INTEGER DEFAULT 0,
    channel_score INTEGER DEFAULT 0,
    ip_address TEXT,
    user_agent TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_submissions_score ON submissions(score DESC);
  CREATE INDEX IF NOT EXISTS idx_submissions_timestamp ON submissions(timestamp);
  CREATE INDEX IF NOT EXISTS idx_submissions_instance ON submissions(instance_id);
`);

// Migrations - add new columns if they don't exist
const migrations = [
  { col: 'handle', sql: 'ALTER TABLE submissions ADD COLUMN handle TEXT' },
  { col: 'skill_score', sql: 'ALTER TABLE submissions ADD COLUMN skill_score INTEGER DEFAULT 0' }
];

for (const m of migrations) {
  try {
    db.exec(m.sql);
    console.log(`[${new Date().toISOString()}] Migration: added ${m.col} column`);
  } catch (e) { 
    // Column already exists - that's fine
  }
}

// Create indexes for new columns (after migrations)
try {
  db.exec(`CREATE INDEX IF NOT EXISTS idx_submissions_handle ON submissions(handle)`);
} catch (e) { /* index exists */ }

// Prepared statements
const statements = {
  insertSubmission: db.prepare(`
    INSERT INTO submissions 
    (instance_id, handle, score, os, arch, timestamp, network_score, perm_score, gateway_score, channel_score, skill_score, ip_address, user_agent)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `),
  updateByHandle: db.prepare(`
    UPDATE submissions 
    SET instance_id = ?, score = ?, os = ?, arch = ?, timestamp = ?, 
        network_score = ?, perm_score = ?, gateway_score = ?, channel_score = ?, skill_score = ?,
        ip_address = ?, user_agent = ?
    WHERE handle = ?
  `),
  updateByInstance: db.prepare(`
    UPDATE submissions 
    SET handle = ?, score = ?, os = ?, arch = ?, timestamp = ?, 
        network_score = ?, perm_score = ?, gateway_score = ?, channel_score = ?, skill_score = ?,
        ip_address = ?, user_agent = ?
    WHERE instance_id = ?
  `),
  getByHandle: db.prepare('SELECT * FROM submissions WHERE handle = ?'),
  getRank: db.prepare(`
    SELECT COUNT(*) + 1 as rank FROM submissions WHERE score > ?
  `),
  getTotal: db.prepare('SELECT COUNT(*) as count FROM submissions'),
  getStats: db.prepare(`
    SELECT 
      COUNT(*) as total_submissions,
      AVG(score) as avg_score,
      MAX(score) as max_score,
      MIN(score) as min_score,
      COUNT(DISTINCT os) as unique_os,
      COUNT(DISTINCT arch) as unique_arch
    FROM submissions
  `),
  getLeaderboard: db.prepare(`
    SELECT 
      instance_id,
      handle,
      score,
      os,
      arch,
      timestamp,
      network_score,
      perm_score,
      gateway_score,
      channel_score,
      skill_score,
      ROW_NUMBER() OVER (ORDER BY score DESC) as rank
    FROM submissions
    ORDER BY score DESC
    LIMIT ? OFFSET ?
  `),
  getByInstance: db.prepare('SELECT * FROM submissions WHERE instance_id = ?'),
  getRecent: db.prepare(`
    SELECT * FROM submissions 
    WHERE timestamp > datetime('now', '-1 hour')
    AND ip_address = ?
  `)
};

// Middleware
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false
}));

// CORS - allow frontend origins
app.use(cors({
  origin: true,  // Reflect request origin (allows all origins with credentials support)
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));

app.use(compression());
app.use(express.json({ limit: '10kb' }));

// Rate limiting
const generalLimiter = rateLimit({
  windowMs: config.rateLimitWindow,
  max: config.rateLimitMax,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.ip
});

const leaderboardLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: config.leaderboardRateLimit,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.body?.instance_id || req.ip
});

app.use(generalLimiter);

// Request logging with cold start indicator
app.use((req, res, next) => {
  const start = Date.now();
  const uptime = Math.floor((Date.now() - START_TIME) / 1000);
  const isColdStart = uptime < 5;  // First 5 seconds considered cold start
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    const coldIndicator = isColdStart ? '[COLD]' : '[WARM]';
    console.log(`${new Date().toISOString()} ${coldIndicator} ${req.method} ${req.path} - ${res.statusCode} - ${duration}ms`);
  });
  next();
});

// Health check - includes cold start info
app.get('/api/health', (req, res) => {
  const uptime = Math.floor((Date.now() - START_TIME) / 1000);
  const dbSize = fs.existsSync(DB_PATH) ? fs.statSync(DB_PATH).size : 0;
  
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: config.version,
    environment: config.env,
    database: 'connected',
    databaseSize: dbSize,
    uptime: uptime,
    coldStart: uptime < 5,
    instanceId: process.env.RENDER_INSTANCE_ID || 'local'
  });
});

// Get leaderboard
app.get('/api/leaderboard', (req, res) => {
  if (!config.enableLeaderboard) {
    return res.status(503).json({ 
      error: 'Leaderboard temporarily unavailable',
      retryAfter: 60
    });
  }

  const limit = Math.min(parseInt(req.query.limit) || 50, 100);
  const offset = parseInt(req.query.offset) || 0;

  try {
    const entries = statements.getLeaderboard.all(limit, offset);
    const { total_submissions } = statements.getTotal.get();

    res.json({
      entries,
      pagination: {
        total: total_submissions,
        limit,
        offset,
        hasMore: offset + entries.length < total_submissions
      }
    });
  } catch (error) {
    console.error('Leaderboard error:', error);
    res.status(500).json({ error: 'Failed to fetch leaderboard' });
  }
});

// Get stats
app.get('/api/leaderboard/stats', (req, res) => {
  if (!config.enablePublicStats) {
    return res.status(503).json({ error: 'Stats temporarily unavailable' });
  }

  try {
    const stats = statements.getStats.get();
    const { count } = statements.getTotal.get();

    // Calculate percentile distribution
    const distribution = db.prepare(`
      SELECT 
        CASE 
          WHEN score >= 90 THEN 'excellent'
          WHEN score >= 70 THEN 'good'
          WHEN score >= 50 THEN 'fair'
          ELSE 'poor'
        END as category,
        COUNT(*) as count
      FROM submissions
      GROUP BY category
    `).all();

    res.json({
      totalSubmissions: count,
      averageScore: Math.round(stats.avg_score * 100) / 100,
      maxScore: stats.max_score,
      minScore: stats.min_score,
      uniqueOS: stats.unique_os,
      uniqueArch: stats.unique_arch,
      distribution: distribution.reduce((acc, row) => {
        acc[row.category] = row.count;
        return acc;
      }, {})
    });
  } catch (error) {
    console.error('Stats error:', error);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// Submit to leaderboard
app.post('/api/leaderboard/submit', leaderboardLimiter, (req, res) => {
  if (!config.enableLeaderboard) {
    return res.status(503).json({ 
      error: 'Leaderboard submissions temporarily unavailable',
      retryAfter: 60
    });
  }

  const { instance_id, handle, score, os, arch, timestamp, network_score, perm_score, gateway_score, channel_score, skill_score } = req.body;

  // Validation
  if (!instance_id || typeof score !== 'number') {
    return res.status(400).json({ error: 'Missing required fields: instance_id, score' });
  }

  if (score < 0 || score > 100) {
    return res.status(400).json({ error: 'Score must be between 0 and 100' });
  }

  // Validate instance_id format (allow friday-XXXXX)
  if (!/^friday-[a-zA-Z0-9]+$/.test(instance_id)) {
    return res.status(400).json({ error: 'Invalid instance_id format' });
  }

  // Clean handle (remove @ if present)
  const cleanHandle = handle ? handle.replace(/^@/, '').trim() : null;

  try {
    // Check for recent submissions from same IP (rate limiting)
    const recentSubmissions = statements.getRecent.all(req.ip);
    if (recentSubmissions.length >= config.leaderboardRateLimit) {
      return res.status(429).json({ 
        error: 'Rate limit exceeded',
        retryAfter: 3600
      });
    }

    let isUpdate = false;

    // Check if handle already exists - if so, update instead of insert
    if (cleanHandle) {
      const existingByHandle = statements.getByHandle.get(cleanHandle);
      if (existingByHandle) {
        // Update existing entry by handle
        statements.updateByHandle.run(
          instance_id,
          score,
          os || 'unknown',
          arch || 'unknown',
          timestamp || new Date().toISOString(),
          network_score || 0,
          perm_score || 0,
          gateway_score || 0,
          channel_score || 0,
          skill_score || 0,
          req.ip,
          req.headers['user-agent'],
          cleanHandle
        );
        isUpdate = true;
      }
    }

    // Check if instance_id already exists
    if (!isUpdate) {
      const existingByInstance = statements.getByInstance.get(instance_id);
      if (existingByInstance) {
        // Update existing entry by instance_id
        statements.updateByInstance.run(
          cleanHandle,
          score,
          os || 'unknown',
          arch || 'unknown',
          timestamp || new Date().toISOString(),
          network_score || 0,
          perm_score || 0,
          gateway_score || 0,
          channel_score || 0,
          skill_score || 0,
          req.ip,
          req.headers['user-agent'],
          instance_id
        );
        isUpdate = true;
      }
    }

    // New submission
    if (!isUpdate) {
      statements.insertSubmission.run(
        instance_id,
        cleanHandle,
        score,
        os || 'unknown',
        arch || 'unknown',
        timestamp || new Date().toISOString(),
        network_score || 0,
        perm_score || 0,
        gateway_score || 0,
        channel_score || 0,
        skill_score || 0,
        req.ip,
        req.headers['user-agent']
      );
    }

    // Get rank
    const { rank } = statements.getRank.get(score);
    const { count: total } = statements.getTotal.get();
    const percentile = Math.round((rank / total) * 100);

    res.json({
      success: true,
      updated: isUpdate,
      rank,
      total_participants: total,
      percentile,
      instance_id,
      handle: cleanHandle
    });
  } catch (error) {
    console.error('Submission error:', error);
    res.status(500).json({ error: 'Failed to submit to leaderboard' });
  }
});

// Get instance details
app.get('/api/instance/:id', (req, res) => {
  const { id } = req.params;
  
  try {
    const instance = statements.getByInstance.get(id);
    if (!instance) {
      return res.status(404).json({ error: 'Instance not found' });
    }

    const { rank } = statements.getRank.get(instance.score);
    const { count: total } = statements.getTotal.get();

    res.json({
      ...instance,
      rank,
      total_participants: total,
      percentile: Math.round((rank / total) * 100)
    });
  } catch (error) {
    console.error('Instance lookup error:', error);
    res.status(500).json({ error: 'Failed to fetch instance' });
  }
});

// Admin endpoints (protected)
const adminAuth = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  
  const token = authHeader.substring(7);
  if (token !== config.adminToken) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  
  next();
};

app.get('/api/admin/submissions', adminAuth, (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 100, 1000);
  const offset = parseInt(req.query.offset) || 0;

  try {
    const submissions = db.prepare(`
      SELECT * FROM submissions 
      ORDER BY created_at DESC 
      LIMIT ? OFFSET ?
    `).all(limit, offset);

    res.json({ submissions });
  } catch (error) {
    console.error('Admin submissions error:', error);
    res.status(500).json({ error: 'Failed to fetch submissions' });
  }
});

// Database backup endpoint (for manual export)
app.get('/api/admin/backup', adminAuth, (req, res) => {
  try {
    const backupPath = path.join(DATA_DIR, `backup_${Date.now()}.db`);
    db.backup(backupPath)
      .then(() => {
        res.download(backupPath, 'friday-leaderboard-backup.db', (err) => {
          if (err) {
            console.error('Download error:', err);
          }
          // Clean up after download
          fs.unlink(backupPath, () => {});
        });
      })
      .catch((err) => {
        console.error('Backup error:', err);
        res.status(500).json({ error: 'Backup failed' });
      });
  } catch (error) {
    console.error('Backup endpoint error:', error);
    res.status(500).json({ error: 'Backup failed' });
  }
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.path });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ 
    error: config.env === 'production' ? 'Internal server error' : err.message 
  });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log(`[${new Date().toISOString()}] SIGTERM received, shutting down gracefully`);
  db.close();
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log(`[${new Date().toISOString()}] SIGINT received, shutting down gracefully`);
  db.close();
  process.exit(0);
});

// Start server
app.listen(PORT, () => {
  const bootTime = Date.now() - START_TIME;
  console.log(`[${new Date().toISOString()}] FRIDAY API v${config.version} running on port ${PORT}`);
  console.log(`[${new Date().toISOString()}] Boot time: ${bootTime}ms`);
  console.log(`[${new Date().toISOString()}] Environment: ${config.env}`);
  console.log(`[${new Date().toISOString()}] Database: ${DB_PATH}`);
  console.log(`[${new Date().toISOString()}] WARNING: Render Free tier sleeps after 15min inactivity`);
  console.log(`[${new Date().toISOString()}] WARNING: First request after sleep will be slow (~30-60s)`);
});
