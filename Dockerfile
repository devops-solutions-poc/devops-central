# --- Build stage ---
# Use buildkit cache for npm
# Requires DOCKER_BUILDKIT=1
FROM node:22-alpine AS builder

# Set working directory
WORKDIR /app

# Install security updates
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache dumb-init

# Copy package files first to leverage cache
COPY package.json package-lock.json ./

# Verify package-lock.json integrity and install dependencies
RUN --mount=type=cache,target=/root/.npm \
    npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# Copy rest of the source code
COPY . .

# Build production assets
RUN npm run build

# Remove source maps for security (optional)
RUN find /app/build -name "*.map" -type f -delete

# --- Runtime stage ---
FROM nginx:1.25-alpine

# Install security updates and dumb-init
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache dumb-init && \
    rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 101 -S nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# Remove default nginx config and create necessary directories
RUN rm -f /etc/nginx/conf.d/default.conf && \
    mkdir -p /var/cache/nginx /var/run/nginx && \
    chown -R nginx:nginx /var/cache/nginx /var/run/nginx /usr/share/nginx/html

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy build output with proper ownership
COPY --from=builder --chown=nginx:nginx /app/build /usr/share/nginx/html

# Switch to non-root user
USER nginx

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget -qO- http://localhost:8080/ > /dev/null 2>&1 || exit 1

# Expose port 8080 (non-privileged port)
EXPOSE 8080

# Use dumb-init to handle signals properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
