# syntax=docker/dockerfile:1
FROM node:20-alpine

# Install SQLite for backups
RUN apk add --no-cache sqlite

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Create directories
RUN mkdir -p /app/data /app/logs

# Copy app source
COPY server.js ./

# Set permissions
RUN chown -R node:node /app/data /app/logs

# Switch to non-root user
USER node

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --spider -q http://localhost:3000/api/health || exit 1

# Start application
CMD ["node", "server.js"]
