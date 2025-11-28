FROM golang:1.23-alpine AS builder

WORKDIR /app

COPY go.mod go.sum* ./
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

# Run the binary
CMD ["./go-app"]
