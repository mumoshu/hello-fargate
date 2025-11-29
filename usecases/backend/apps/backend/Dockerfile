FROM golang:1.23-alpine AS builder

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -installsuffix cgo -o /go-app .

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /go-app .

EXPOSE 8080

CMD ["./go-app"]
