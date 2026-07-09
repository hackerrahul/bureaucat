# Build frontend
FROM oven/bun:1.3.7-slim AS frontend
WORKDIR /app/web
COPY web/package.json web/bun.lock ./
RUN bun install --frozen-lockfile
COPY web .
RUN bun run generate

# Build backend
FROM golang:1.25.6-trixie AS backend
ARG VERSION=dev
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=frontend /app/web/.output/public ./cmd/bureaucat/dist
RUN cp -r migrations/* ./cmd/bureaucat/migrations/
RUN go build -ldflags "-X main.Version=${VERSION}" -o bureaucat ./cmd/bureaucat

# Runtime
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* || true
WORKDIR /app
COPY --from=backend /app/bureaucat .
EXPOSE 1341
CMD ["./bureaucat", "serve", "--migrate"]
