#!/usr/bin/env node
/**
 * Backup script for Render Free tier
 * Exports SQLite database to external storage
 * Runs every 6 hours via Render Cron Job
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const DATA_DIR = process.env.DATA_DIR || '/opt/render/project/src/data';
const DB_PATH = process.env.DATABASE_URL?.replace('sqlite:', '') || path.join(DATA_DIR, 'leaderboard.db');
const RETENTION_DAYS = parseInt(process.env.BACKUP_RETENTION_DAYS) || 7;

// External storage config (optional)
const S3_BUCKET = process.env.S3_BUCKET_NAME;
const AWS_ACCESS_KEY = process.env.AWS_ACCESS_KEY_ID;
const AWS_SECRET_KEY = process.env.AWS_SECRET_ACCESS_KEY;

console.log(`[${new Date().toISOString()}] Starting FRIDAY backup...`);

// Check if database exists
if (!fs.existsSync(DB_PATH)) {
  console.error(`[${new Date().toISOString()}] ERROR: Database not found at ${DB_PATH}`);
  process.exit(1);
}

const date = new Date().toISOString().replace(/[:.]/g, '-');
const backupFile = path.join(DATA_DIR, `leaderboard_backup_${date}.db`);

try {
  // Create backup using SQLite
  console.log(`[${new Date().toISOString()}] Creating database backup...`);
  
  const sqlite3 = require('better-sqlite3');
  const db = new Database(DB_PATH);
  db.backup(backupFile)
    .then(() => {
      console.log(`[${new Date().toISOString()}] Backup created: ${backupFile}`);
      
      // Compress backup
      console.log(`[${new Date().toISOString()}] Compressing backup...`);
      execSync(`gzip -f "${backupFile}"`);
      const compressedFile = `${backupFile}.gz`;
      const stats = fs.statSync(compressedFile);
      console.log(`[${new Date().toISOString()}] Compressed size: ${(stats.size / 1024).toFixed(2)} KB`);
      
      // Upload to S3 if configured
      if (S3_BUCKET && AWS_ACCESS_KEY && AWS_SECRET_KEY) {
        console.log(`[${new Date().toISOString()}] Uploading to S3...`);
        try {
          execSync(`aws s3 cp "${compressedFile}" "s3://${S3_BUCKET}/backups/" --storage-class STANDARD_IA`, {
            env: { ...process.env, AWS_REGION: process.env.AWS_REGION || 'us-east-1' }
          });
          console.log(`[${new Date().toISOString()}] S3 upload complete`);
        } catch (s3Error) {
          console.error(`[${new Date().toISOString()}] S3 upload failed:`, s3Error.message);
        }
      }
      
      // Clean old local backups
      console.log(`[${new Date().toISOString()}] Cleaning old backups (retention: ${RETENTION_DAYS} days)...`);
      const files = fs.readdirSync(DATA_DIR);
      let deletedCount = 0;
      
      files.forEach(file => {
        if (file.startsWith('leaderboard_backup_') && file.endsWith('.gz')) {
          const filePath = path.join(DATA_DIR, file);
          const stats = fs.statSync(filePath);
          const ageDays = (Date.now() - stats.mtime.getTime()) / (1000 * 60 * 60 * 24);
          
          if (ageDays > RETENTION_DAYS) {
            fs.unlinkSync(filePath);
            deletedCount++;
            console.log(`[${new Date().toISOString()}] Deleted old backup: ${file}`);
          }
        }
      });
      
      console.log(`[${new Date().toISOString()}] Backup complete. Deleted ${deletedCount} old backups.`);
      db.close();
    })
    .catch((error) => {
      console.error(`[${new Date().toISOString()}] Backup failed:`, error);
      process.exit(1);
    });
    
} catch (error) {
  console.error(`[${new Date().toISOString()}] Backup error:`, error);
  process.exit(1);
}
