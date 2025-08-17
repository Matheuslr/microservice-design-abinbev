# ===========================================
# Multi-stage Dockerfile for Go Microservice
# ===========================================

# Stage 1: Dependencies
FROM golang:1.21-alpine AS dependencies
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# Stage 2: Build
FROM golang:1.21-alpine AS builder
WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Copy dependencies from previous stage
COPY --from=dependencies /go/pkg /go/pkg
COPY go.mod go.sum ./
COPY . .

# Build arguments for versioning
ARG VERSION=unknown
ARG COMMIT=unknown
ARG BUILD_TIME=unknown

# Build the binary with optimizations
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s -X main.Version=${VERSION} -X main.Commit=${COMMIT} -X main.BuildTime=${BUILD_TIME}" \
    -a -installsuffix cgo \
    -o /app/bin/api ./cmd/api

# Stage 3: Runtime
FROM scratch

# Copy timezone data and CA certificates
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy the binary
COPY --from=builder /app/bin/api /api

# Create non-root user
USER 10001:10001

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/api", "health"]

# Expose port
EXPOSE 8080

# Run the binary
ENTRYPOINT ["/api"]