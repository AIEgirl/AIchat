FROM golang:1.21-alpine AS builder

# 安装构建依赖
RUN apk add --no-cache git gcc musl-dev

WORKDIR /app

# 复制go.mod和go.sum
COPY go.mod go.sum* ./
RUN go mod download

# 复制源代码
COPY . .

# 构建
RUN CGO_ENABLED=1 GOOS=linux go build -a -ldflags="-s -w" -o ai-relay .

# 运行时镜像
FROM alpine:3.18

RUN apk add --no-cache ca-certificates tzdata curl

WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder /app/ai-relay .
COPY --from=builder /app/config ./config

# 创建上传目录
RUN mkdir -p /app/uploads

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["./ai-relay", "-config=config/config.yaml"]
