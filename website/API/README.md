# AI中转服务平台 (AI Relay Platform)

一个基于 Go 语言开发的高性能、功能完善的 AI 中转服务平台。

## 核心特性

### 后台管理
- AI服务管理：可视化配置多家AI服务（OpenAI、Anthropic、自定义等）
- 用户管理：完整的用户生命周期管理与消费记录追踪
- 系统配置：SMTP、限流、支付网关的可视化配置
- 财务管理：交易流水、充值消费统计、财务报表导出

### 用户功能
- 注册登录：邮箱验证、密码重置、JWT认证
- 在线充值：支持支付宝、微信、Stripe 等多种支付方式
- API调用：标准化接口，实时扣费，透明计费
- 密钥管理：可生成多个API Key，支持权限控制和密钥轮换

### 安全与性能
- AES-256-GCM 加密存储 API Key 等敏感信息
- HMAC-SHA256 请求签名验证
- 多级限流：全局、IP、用户三个维度
- 防DDoS攻击：自动检测异常流量并封禁
- 异常检测：全链路日志、异常行为记录与告警

## 技术栈

- **后端**: Go 1.21 + Gin + GORM
- **数据库**: MySQL / PostgreSQL / SQLite
- **认证**: JWT + API Key 双模式
- **缓存**: Redis（可选）
- **部署**: Docker + Docker Compose + Nginx

## 快速开始

### 方式一：直接运行

```bash
# 1. 克隆项目
cd d:/AIchat/website/API

# 2. 下载依赖
go mod tidy

# 3. 修改配置
# 编辑 config/config.yaml

# 4. 启动（默认使用SQLite数据库）
go run main.go

# 服务将运行在 http://localhost:8080
# 默认管理员: admin / Admin@123
```

### 方式二：Docker 部署

```bash
# 1. 构建并启动所有服务
docker-compose up -d

# 2. 查看日志
docker-compose logs -f api

# 3. 停止服务
docker-compose down
```

## 目录结构

```
API/
├── main.go                 # 程序入口
├── go.mod                  # 依赖管理
├── config/                 # 配置文件
│   └── config.yaml
├── internal/
│   ├── config/            # 配置加载
│   ├── database/          # 数据库初始化
│   ├── models/            # 数据模型
│   ├── middleware/        # 中间件（认证、限流、日志、防DDoS、签名）
│   ├── handlers/          # HTTP处理器
│   ├── services/          # 业务服务（邮件、支付、AI代理、加密）
│   ├── utils/             # 工具函数
│   └── router/            # 路由配置
├── Dockerfile
├── docker-compose.yml
└── nginx.conf
```

## API 接口

### 公开接口
- `POST /api/v1/auth/register` 用户注册
- `POST /api/v1/auth/login` 用户登录
- `POST /api/v1/auth/send-code` 发送验证码
- `POST /api/v1/auth/reset-password` 重置密码
- `GET  /api/v1/services` AI服务列表
- `GET  /api/v1/services/:code` AI服务详情
- `POST /api/v1/services/:code/estimate` 费用估算
- `GET  /api/v1/recharge/packages` 充值套餐
- `GET  /api/v1/site/info` 站点信息

### 用户接口（需登录）
- `GET  /api/v1/user/me` 当前用户信息
- `PUT  /api/v1/user/profile` 更新资料
- `POST /api/v1/user/change-password` 修改密码
- `GET  /api/v1/account/balance` 账户余额
- `GET  /api/v1/account/transactions` 交易记录
- `POST /api/v1/recharge/create` 创建充值订单
- `GET  /api/v1/recharge/order/:order_no` 查询订单
- `GET  /api/v1/keys` API Key 列表
- `POST /api/v1/keys` 创建 API Key
- `POST /api/v1/keys/:id/rotate` 轮换密钥
- `DELETE /api/v1/keys/:id` 删除

### AI 服务调用（API Key 认证）
```bash
# 标准调用
curl -X POST http://localhost:8080/api/v1/v1/services/gpt-3.5-turbo/call \
  -H "X-API-Key-ID: ak_xxx" \
  -H "X-API-Key-Secret: sk_xxx" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"Hello"}]}'

# 兼容 OpenAI 格式
curl -X POST http://localhost:8080/api/v1/v1/chat/completions \
  -H "Authorization: Bearer ak_xxx:sk_xxx" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"Hello"}]}'

# 带签名验证
curl -X POST http://localhost:8080/api/v1/v1/services/gpt-3.5-turbo/call \
  -H "X-API-Key-ID: ak_xxx" \
  -H "X-API-Key-Secret: sk_xxx" \
  -H "X-Timestamp: 1700000000" \
  -H "X-Nonce: abc123" \
  -H "X-Signature: <hmac-sha256>" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

### 管理后台接口
- `GET  /api/v1/admin/dashboard` 仪表盘统计
- `GET  /api/v1/admin/users` 用户列表
- `PUT  /api/v1/admin/users/:id` 修改用户
- `GET  /api/v1/admin/services` AI服务管理
- `POST /api/v1/admin/services` 创建AI服务
- `GET  /api/v1/admin/finance/transactions` 交易流水
- `GET  /api/v1/admin/finance/stats` 财务统计
- `GET  /api/v1/admin/configs` 系统配置
- `PUT  /api/v1/admin/configs/smtp` SMTP配置
- `GET  /api/v1/admin/logs/operation` 操作日志
- `GET  /api/v1/admin/logs/anomaly` 异常日志

## 签名算法

为防止请求被篡改，AI 服务调用支持 HMAC-SHA256 签名：

1. 构造签名字符串：
   ```
   METHOD\nPATH\nTIMESTAMP\nNONCE\nBODY_SHA256
   ```
   - METHOD: HTTP方法（大写）
   - PATH: 请求路径
   - TIMESTAMP: Unix秒级时间戳
   - NONCE: 随机字符串
   - BODY_SHA256: 请求体的 SHA256 哈希

2. 使用 API Key Secret 作为密钥计算 HMAC-SHA256

3. 发送时通过 `X-Signature` Header 传递

**Python 签名示例**：
```python
import hmac
import hashlib
import time
import uuid

def sign_request(method, path, body, secret):
    timestamp = str(int(time.time()))
    nonce = str(uuid.uuid4())
    body_hash = hashlib.sha256(body.encode()).hexdigest()
    message = f"{method}\n{path}\n{timestamp}\n{nonce}\n{body_hash}"
    signature = hmac.new(secret.encode(), message.encode(), hashlib.sha256).hexdigest()
    return {
        "X-Timestamp": timestamp,
        "X-Nonce": nonce,
        "X-Signature": signature
    }
```

## 计费模式

支持多种计费方式：
- **按次计费 (per_request)**: 每次调用固定价格
- **按Token计费 (per_token)**: 分别计算输入/输出Token价格
- **包月计费 (monthly)**: 订阅制
- **免费 (free)**: 免费调用

## 数据库切换

修改 `config/config.yaml` 中的 `database.driver` 字段：
- `sqlite` (默认，无需额外配置)
- `mysql`
- `postgres`

## 安全建议

1. **生产环境必须修改 JWT secret 和 AES 密钥**
2. 启用 HTTPS，使用 Nginx 反向代理
3. 启用 Redis 进一步提升限流性能
4. 定期备份数据库
5. 监控异常日志和操作日志
6. 配置 IP 白名单限制管理后台访问
7. 启用邮箱验证减少恶意注册

## 性能指标

- 单实例支持 10000+ 并发连接
- API 调用平均延迟 < 100ms（不计上游AI服务）
- 数据库连接池：100 最大 / 20 空闲
- 限流：可配置（默认 1000 全局 RPS、60 用户 RPS、30 IP RPS）

## 许可证

MIT License
