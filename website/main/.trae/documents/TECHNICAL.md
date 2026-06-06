# 服务商管理系统 - 技术架构文档

## 1. 系统架构概览

### 1.1 整体架构
采用前后端分离的单体应用架构：
```
┌─────────────────────────────────────────┐
│          浏览器 (PC/Mobile)              │
└──────────────┬──────────────────────────┘
               │ HTTPS / JSON
┌──────────────▼──────────────────────────┐
│   静态前端 (HTML5/CSS3/Vanilla JS)        │
│   - 用户端 (user.html)                    │
│   - 管理端 (admin.html)                   │
└──────────────┬──────────────────────────┘
               │ RESTful API
┌──────────────▼──────────────────────────┐
│      Go Backend (Gin)                    │
│   ┌────────────┬─────────────┐           │
│   │ Middleware │  Handlers   │           │
│   │ - Auth     │  - User     │           │
│   │ - CORS     │  - Provider │           │
│   │ - Logger   │  - Category │           │
│   │ - RateLimit│  - Review   │           │
│   │ - DDoS     │  - Stats    │           │
│   └────────────┴─────────────┘           │
│              │ GORM                      │
│   ┌───────────▼──────────────┐            │
│   │ Database                │            │
│   │ SQLite (Dev)            │            │
│   │ MySQL (Prod)            │            │
│   └──────────────────────────┘            │
└─────────────────────────────────────────┘
```

### 1.2 部署架构
- **开发环境**：单机运行，前端通过HTTP请求本地Go服务
- **生产环境**：Nginx反向代理 + Go服务 + MySQL主从

## 2. 技术选型

### 2.1 前端
| 技术 | 用途 | 选型理由 |
|------|------|----------|
| HTML5 | 页面结构 | 标准化、SEO友好 |
| CSS3 | 样式 | 原生支持、变量、动画 |
| Vanilla JavaScript | 交互 | 零依赖、加载快 |
| Chart.js | 数据图表 | CDN引入、轻量 |
| Font Awesome | 图标 | CDN引入、丰富 |

**设计原则**：无构建工具，原生JS实现，CDN加载外部库，最大化加载速度。

### 2.2 后端
| 技术 | 用途 | 选型理由 |
|------|------|----------|
| Go 1.21+ | 主语言 | 高性能、并发友好 |
| Gin | Web框架 | 轻量、生态丰富 |
| GORM | ORM | 主流、功能完整 |
| Viper | 配置 | 支持YAML/ENV |
| JWT | 认证 | 无状态、标准 |
| bcrypt | 密码加密 | 工业标准 |

### 2.3 数据库
- **开发**：SQLite（零配置）
- **生产**：MySQL 8.0
- **缓存**：可选 Redis

## 3. 数据模型设计

### 3.1 核心表结构

#### providers（服务商表）
```sql
CREATE TABLE providers (
    id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    name VARCHAR(128) NOT NULL,
    credit_code VARCHAR(64) COMMENT '统一社会信用代码',
    logo VARCHAR(512),
    description TEXT,
    website VARCHAR(512),
    contact_name VARCHAR(64),
    contact_phone VARCHAR(32),
    contact_email VARCHAR(128),
    address VARCHAR(512),
    region VARCHAR(64) COMMENT '省市区',
    category_id BIGINT UNSIGNED,
    service_scope TEXT COMMENT '服务范围',
    price_min DECIMAL(10,2),
    price_max DECIMAL(10,2),
    cooperation_mode VARCHAR(64) COMMENT '合作模式',
    rating DECIMAL(3,2) DEFAULT 0 COMMENT '综合评分',
    response_score DECIMAL(3,2) DEFAULT 0,
    deal_count INT DEFAULT 0,
    view_count INT DEFAULT 0,
    status TINYINT DEFAULT 0 COMMENT '0:待审核 1:审核中 2:已通过 3:已禁用 4:未通过',
    is_featured BOOLEAN DEFAULT 0 COMMENT '是否推荐',
    sort_order INT DEFAULT 0,
    submit_time DATETIME,
    approved_time DATETIME,
    approved_by BIGINT UNSIGNED,
    created_at DATETIME,
    updated_at DATETIME,
    deleted_at DATETIME,
    INDEX idx_status (status),
    INDEX idx_category (category_id),
    INDEX idx_rating (rating),
    INDEX idx_region (region)
);
```

#### categories（分类表）
```sql
CREATE TABLE categories (
    id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(64) NOT NULL,
    icon VARCHAR(128),
    parent_id BIGINT UNSIGNED DEFAULT 0,
    sort_order INT DEFAULT 0,
    status TINYINT DEFAULT 1,
    created_at DATETIME,
    updated_at DATETIME,
    INDEX idx_parent (parent_id)
);
```

#### qualifications（资质材料表）
```sql
CREATE TABLE qualifications (
    id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    provider_id BIGINT UNSIGNED NOT NULL,
    type VARCHAR(32) COMMENT 'license/certificate/other',
    name VARCHAR(128),
    file_url VARCHAR(512),
    file_type VARCHAR(16),
    expire_date DATE,
    created_at DATETIME,
    INDEX idx_provider (provider_id)
);
```

#### review_logs（审核记录表）
```sql
CREATE TABLE review_logs (
    id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    provider_id BIGINT UNSIGNED NOT NULL,
    reviewer_id BIGINT UNSIGNED,
    reviewer_name VARCHAR(64),
    action VARCHAR(32) COMMENT 'submit/approve/reject/withdraw',
    from_status TINYINT,
    to_status TINYINT,
    comment TEXT,
    created_at DATETIME,
    INDEX idx_provider (provider_id)
);
```

#### admins（管理员表）
```sql
CREATE TABLE admins (
    id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    nickname VARCHAR(64),
    role VARCHAR(32) DEFAULT 'admin' COMMENT 'admin/super_admin',
    status TINYINT DEFAULT 1,
    last_login_at DATETIME,
    last_login_ip VARCHAR(64),
    created_at DATETIME,
    updated_at DATETIME
);
```

### 3.2 ER 关系图
```
categories (1) ──── (N) providers
                          │
                          ├── (N) qualifications
                          └── (N) review_logs

admins ──── (N) review_logs
```

## 4. API 设计规范

### 4.1 接口前缀
- 用户端：`/api/user/v1`
- 管理端：`/api/admin/v1`

### 4.2 统一响应格式
```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

### 4.3 状态码
| Code | 含义 |
|------|------|
| 0 | 成功 |
| 40000 | 参数错误 |
| 40100 | 未登录 |
| 40300 | 无权限 |
| 40400 | 未找到 |
| 42900 | 限流 |
| 50000 | 服务器错误 |

### 4.4 核心接口列表

#### 用户端
- `GET  /providers` - 服务商列表（分页、筛选）
- `GET  /providers/:id` - 服务商详情
- `GET  /providers/featured` - 推荐服务商
- `GET  /providers/search` - 搜索
- `GET  /categories` - 分类列表
- `GET  /stats/overview` - 平台公开统计

#### 管理端
- `POST /auth/login` - 管理员登录
- `GET  /providers` - 全部服务商（管理视图）
- `POST /providers` - 创建服务商
- `PUT  /providers/:id` - 更新服务商
- `DELETE /providers/:id` - 删除服务商
- `POST /providers/:id/status` - 修改状态
- `POST /providers/:id/review` - 审核操作
- `GET  /providers/:id/reviews` - 审核历史
- `GET  /categories` - 分类列表
- `POST /categories` - 创建分类
- `PUT  /categories/:id` - 更新分类
- `DELETE /categories/:id` - 删除分类
- `GET  /dashboard` - 仪表盘数据
- `GET  /stats/analysis` - 统计分析

## 5. 安全设计

### 5.1 认证流程
1. 管理员登录 → 验证密码（bcrypt）
2. 生成 JWT Token（HS256，过期24h）
3. 后续请求 Header：`Authorization: Bearer {token}`
4. 中间件验证 token 并解析角色

### 5.2 授权控制
- 角色：`admin`（普通）、`super_admin`（超级）
- 接口按角色鉴权
- 关键操作（删除、状态变更）需 super_admin

### 5.3 数据安全
- SQL 注入：GORM 参数化
- XSS：HTML 转义
- CSRF：Token 机制 + CORS 白名单
- 密码：bcrypt cost=12
- 敏感字段：AES-256-GCM 加密

### 5.4 限流策略
- 全局：1000 RPS
- 单 IP：60 RPS
- 登录接口：5次/分钟
- 令牌桶算法

## 6. 性能优化

### 6.1 数据库优化
- 核心查询字段建立索引
- 分页查询使用 OFFSET/LIMIT 或游标
- N+1 查询：GORM Preload
- 慢查询日志

### 6.2 缓存策略
- 公开数据：5分钟本地缓存
- 统计数据：1分钟内存缓存
- 用户会话：JWT 无状态

### 6.3 前端优化
- 静态资源 CDN
- 图片懒加载
- 接口防抖/节流
- 骨架屏

## 7. 项目结构

```
main/
├── .trae/documents/        # 项目文档
├── frontend/               # 前端
│   ├── user/               # 用户端
│   │   ├── index.html      # 首页
│   │   ├── providers.html  # 列表页
│   │   ├── detail.html     # 详情页
│   │   ├── css/
│   │   └── js/
│   └── admin/              # 管理端
│       ├── login.html      # 登录页
│       ├── dashboard.html  # 仪表盘
│       ├── providers.html  # 服务商管理
│       ├── categories.html # 分类管理
│       ├── review.html     # 审核中心
│       ├── stats.html      # 数据统计
│       ├── css/
│       └── js/
└── README.md
```

## 8. 部署方案

### 8.1 开发环境
- 前端：HTTP静态服务（Live Server）
- 后端：`go run main.go`（端口8080）
- API代理：前端通过CORS访问后端

### 8.2 生产环境
- Nginx 反向代理
- Go 二进制（Systemd管理）
- MySQL 主从
- 静态资源CDN

## 9. 监控与运维

- 健康检查：`/health`
- 日志：JSON 格式，文件 + stdout
- 关键指标：QPS、响应时间、错误率
- 告警：错误率>1% 通知

## 10. 开发计划

| 阶段 | 内容 | 周期 |
|------|------|------|
| 1 | 基础架构、数据库、认证 | 1天 |
| 2 | 后台服务商管理 | 1天 |
| 3 | 后台分类、审核、统计 | 1天 |
| 4 | 前端用户端 | 1天 |
| 5 | 前端管理端 | 1天 |
| 6 | 测试、调优、文档 | 1天 |
