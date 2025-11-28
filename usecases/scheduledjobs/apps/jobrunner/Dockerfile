FROM golang:1.23-alpine AS builder

WORKDIR /app

# We intentionally not copy go.sum for now, because our go.mod have zero deps so go.sum is not created.
COPY go.mod ./
# Download dependencies
RUN go mod download

# Copy the source code
COPY . .

# Build the Go app statically
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -a -installsuffix cgo -o /go-app .

# --- Final Stage ---
FROM alpine:latest

WORKDIR /root/

# Copy the static binary from the builder stage
COPY --from=builder /go-app .

# (Optional) Add any necessary certificates or files
# COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Run the binary
CMD ["./go-app"]
