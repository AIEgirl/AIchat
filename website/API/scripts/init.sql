# 数据库初始化SQL（MySQL示例）

CREATE DATABASE IF NOT EXISTS ai_relay DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ai_relay;

-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    username VARCHAR(64) UNIQUE NOT NULL,
    email VARCHAR(128) UNIQUE NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    nickname VARCHAR(64),
    avatar VARCHAR(512),
    phone VARCHAR(32),
    role VARCHAR(32) DEFAULT 'user',
    status INT DEFAULT 1,
    email_verified TINYINT(1) DEFAULT 0,
    balance DECIMAL(15,4) DEFAULT 0,
    frozen_balance DECIMAL(15,4) DEFAULT 0,
    total_spent DECIMAL(15,4) DEFAULT 0,
    total_recharged DECIMAL(15,4) DEFAULT 0,
    last_login_at DATETIME,
    last_login_ip VARCHAR(64),
    login_count INT DEFAULT 0,
    remark VARCHAR(512),
    created_at DATETIME,
    updated_at DATETIME,
    deleted_at DATETIME,
    INDEX idx_username (username),
    INDEX idx_email (email),
    INDEX idx_role (role),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- AI服务表
CREATE TABLE IF NOT EXISTS ai_services (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    name VARCHAR(64) NOT NULL,
    code VARCHAR(64) UNIQUE NOT NULL,
    provider VARCHAR(64),
    description TEXT,
    avatar VARCHAR(512),
    tags VARCHAR(255),
    endpoint VARCHAR(512) NOT NULL,
    method VARCHAR(16) DEFAULT 'POST',
    headers JSON,
    request_schema JSON,
    response_path VARCHAR(255),
    timeout INT DEFAULT 30,
    billing_mode VARCHAR(32) DEFAULT 'per_request',
    price_per_request DECIMAL(10,6) DEFAULT 0,
    price_per_input_token DECIMAL(10,6) DEFAULT 0,
    price_per_output_token DECIMAL(10,6) DEFAULT 0,
    monthly_price DECIMAL(10,2) DEFAULT 0,
    min_balance DECIMAL(10,4) DEFAULT 0,
    max_qps INT DEFAULT 10,
    max_concurrent INT DEFAULT 100,
    status INT DEFAULT 1,
    is_public TINYINT(1) DEFAULT 1,
    sort_order INT DEFAULT 0,
    call_count BIGINT DEFAULT 0,
    total_revenue DECIMAL(15,4) DEFAULT 0,
    created_at DATETIME,
    updated_at DATETIME,
    deleted_at DATETIME,
    INDEX idx_code (code),
    INDEX idx_status (status),
    INDEX idx_provider (provider)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 交易流水表
CREATE TABLE IF NOT EXISTS transactions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_no VARCHAR(64) UNIQUE NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    type VARCHAR(32),
    amount DECIMAL(15,4) NOT NULL,
    balance_before DECIMAL(15,4),
    balance_after DECIMAL(15,4),
    status VARCHAR(32) DEFAULT 'pending',
    payment_method VARCHAR(32),
    payment_ref VARCHAR(128),
    service_id BIGINT UNSIGNED,
    api_key_id BIGINT UNSIGNED,
    input_tokens INT DEFAULT 0,
    output_tokens INT DEFAULT 0,
    description VARCHAR(512),
    metadata JSON,
    paid_at DATETIME,
    refunded_at DATETIME,
    created_at DATETIME,
    updated_at DATETIME,
    deleted_at DATETIME,
    INDEX idx_order_no (order_no),
    INDEX idx_user_id (user_id),
    INDEX idx_type (type),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- API Key 表
CREATE TABLE IF NOT EXISTS api_keys (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(64) NOT NULL,
    key_id VARCHAR(32) UNIQUE NOT NULL,
    key_secret VARCHAR(256) NOT NULL,
    key_preview VARCHAR(32),
    scopes VARCHAR(255) DEFAULT 'all',
    status INT DEFAULT 1,
    expires_at DATETIME,
    last_used_at DATETIME,
    last_used_ip VARCHAR(64),
    usage_count BIGINT DEFAULT 0,
    total_cost DECIMAL(15,6) DEFAULT 0,
    created_at DATETIME,
    updated_at DATETIME,
    deleted_at DATETIME,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
