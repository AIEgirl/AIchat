package models

import (
	"time"
)

// APIRequestLog API调用日志
type APIRequestLog struct {
	ID           uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	RequestID    string    `gorm:"type:varchar(64);uniqueIndex" json:"request_id"`
	UserID       uint64    `gorm:"index" json:"user_id"`
	APIKeyID     uint64    `gorm:"index" json:"api_key_id"`
	ServiceID    uint64    `gorm:"index" json:"service_id"`
	ServiceCode  string    `gorm:"type:varchar(64);index" json:"service_code"`
	Method       string    `gorm:"type:varchar(16)" json:"method"`
	Path         string    `gorm:"type:varchar(512)" json:"path"`
	IP           string    `gorm:"type:varchar(64);index" json:"ip"`
	UserAgent    string    `gorm:"type:varchar(512)" json:"user_agent"`
	RequestSize  int       `json:"request_size"`
	ResponseSize int       `json:"response_size"`
	StatusCode   int       `gorm:"index" json:"status_code"`
	InputTokens  int       `json:"input_tokens"`
	OutputTokens int       `json:"output_tokens"`
	Cost         float64   `gorm:"type:decimal(10,6)" json:"cost"`
	Duration     int64     `json:"duration"` // 毫秒
	Error        string    `gorm:"type:text" json:"error"`
	CreatedAt    time.Time `gorm:"index" json:"created_at"`
}

func (APIRequestLog) TableName() string { return "api_request_logs" }

// SystemConfig 系统配置
type SystemConfig struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Key       string    `gorm:"type:varchar(128);uniqueIndex;not null" json:"key"`
	Value     string    `gorm:"type:text" json:"value"`
	Type      string    `gorm:"type:varchar(32);default:'string'" json:"type"` // string, number, bool, json
	Group     string    `gorm:"type:varchar(64);index" json:"group"`           // smtp, payment, rate_limit, etc.
	Label     string    `gorm:"type:varchar(128)" json:"label"`
	Remark    string    `gorm:"type:varchar(512)" json:"remark"`
	IsPublic  bool      `gorm:"default:false" json:"is_public"` // 是否对用户公开
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (SystemConfig) TableName() string { return "system_configs" }

// OperationLog 操作日志
type OperationLog struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID     uint64    `gorm:"index" json:"user_id"`
	Username   string    `gorm:"type:varchar(64);index" json:"username"`
	Module     string    `gorm:"type:varchar(64);index" json:"module"`
	Action     string    `gorm:"type:varchar(64);index" json:"action"`
	Resource   string    `gorm:"type:varchar(128)" json:"resource"`
	IP         string    `gorm:"type:varchar(64);index" json:"ip"`
	UserAgent  string    `gorm:"type:varchar(512)" json:"user_agent"`
	Method     string    `gorm:"type:varchar(16)" json:"method"`
	Path       string    `gorm:"type:varchar(512)" json:"path"`
	StatusCode int       `json:"status_code"`
	Request    string    `gorm:"type:text" json:"request"`
	Response   string    `gorm:"type:text" json:"response"`
	Duration   int64     `json:"duration"`
	CreatedAt  time.Time `gorm:"index" json:"created_at"`
}

func (OperationLog) TableName() string { return "operation_logs" }

// AnomalyDetection 异常检测记录
type AnomalyDetection struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Type       string    `gorm:"type:varchar(32);index" json:"type"` // rate_limit, signature, ddos, abnormal_behavior
	IP         string    `gorm:"type:varchar(64);index" json:"ip"`
	UserID     *uint64   `gorm:"index" json:"user_id,omitempty"`
	APIKeyID   *uint64   `gorm:"index" json:"api_key_id,omitempty"`
	Path       string    `gorm:"type:varchar(512)" json:"path"`
	Reason     string    `gorm:"type:varchar(512)" json:"reason"`
	Level      string    `gorm:"type:varchar(16);index" json:"level"` // info, warn, error, critical
	Blocked    bool      `gorm:"default:true" json:"blocked"`
	CreatedAt  time.Time `gorm:"index" json:"created_at"`
}

func (AnomalyDetection) TableName() string { return "anomaly_detections" }

// IPBlacklist IP黑名单
type IPBlacklist struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	IP        string    `gorm:"type:varchar(64);uniqueIndex;not null" json:"ip"`
	Reason    string    `gorm:"type:varchar(512)" json:"reason"`
	ExpiresAt *time.Time `json:"expires_at"`
	CreatedAt time.Time  `json:"created_at"`
}

func (IPBlacklist) TableName() string { return "ip_blacklists" }
