FROM docker.io/golang:alpine3.23 AS builder

WORKDIR /src

COPY go.mod go.sum ./

RUN go mod download

COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o coolify-acme-json-certs-map main.go

FROM scratch

COPY --from=builder /src/coolify-acme-json-certs-map .

CMD ["/coolify-acme-json-certs-map"]
