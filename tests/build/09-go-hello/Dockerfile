FROM --platform=linux/amd64 golang:1.24-alpine

WORKDIR /app
COPY go.mod .
COPY main.go .

ENV GOOS=linux
ENV GOARCH=amd64
ENV CGO_ENABLED=0

RUN go build -o test ./

EXPOSE 8080
CMD ["/app/test"]
