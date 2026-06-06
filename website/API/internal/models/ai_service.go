package models

import (
	"database/sql/driver"
	"encoding/json"
	"time"

	"gorm.io/gorm"
)

// BillingMode 计费模式
type BillingMode string

const (
	BillingPerRequest BillingMode = "per_request" // 按次
	BillingPerToken   BillingMode = "per_token"   // 按token
	BillingMonthly    BillingMode = "monthly"     // 包月
	BillingFree       BillingMode = "free"        // 免费
)

// JSONMap 自定义JSON类型
type JSONMap map[string]interface{}

func (j JSONMap) Value() (driver.Value, error) {
	if j == nil {
		return nil, nil
	}
	return json.Marshal(j)
}

func (j *JSONMap) Scan(value interface{}) error {
	if value == nil {
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return nil
	}
	return json.Unmarshal(bytes, j)
}

// AIService AI服务配置
type AIService struct {
	ID            uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID          string         `gorm:"type:varchar(36);uniqueIndex;not null" json:"uuid"`
	Name          string         `gorm:"type:varchar(64);not null;index" json:"name"`
	Code          string         `gorm:"type:varchar(64);uniqueIndex;not null" json:"code"` // 唯一标识
	Provider      string         `gorm:"type:varchar(64);index" json:"provider"`           // openai, anthropic, baidu, etc.
	Description   string         `gorm:"type:text" json:"description"`
	Avatar        string         `gorm:"type:varchar(512)" json:"avatar"`
	Tags          string         `gorm:"type:varchar(255)" json:"tags"` // 逗号分隔

	// API端点配置
	Endpoint      string         `gorm:"type:varchar(512);not null" json:"endpoint"`
	Method        string         `gorm:"type:varchar(16);default:'POST'" json:"method"`
	Headers       JSONMap        `gorm:"type:json" json:"headers"`
	RequestSchema JSONMap        `gorm:"type:json" json:"request_schema"`
	ResponsePath  string         `gorm:"type:varchar(255)" json:"response_path"` // 响应中提取内容的JSONPath
	Timeout       int            `gorm:"default:30" json:"timeout"`              // 秒

	// 价格策略
	BillingMode   BillingMode    `gorm:"type:varchar(32);default:'per_request'" json:"billing_mode"`
	PricePerRequest float64      `gorm:"type:decimal(10,6);default:0" json:"price_per_request"` // 每次价格
	PricePerInputToken  float64  `gorm:"type:decimal(10,6);default:0" json:"price_per_input_token"`
	PricePerOutputToken float64  `gorm:"type:decimal(10,6);default:0" json:"price_per_output_token"`
	MonthlyPrice  float64        `gorm:"type:decimal(10,2);default:0" json:"monthly_price"` // 包月价格
	MinBalance    float64        `gorm:"type:decimal(10,4);default:0" json:"min_balance"`   // 最低余额要求

	// 限流配置
	MaxQPS        int            `gorm:"default:10" json:"max_qps"`
	MaxConcurrent int            `gorm:"default:100" json:"max_concurrent"`

	// 状态
	Status        int            `gorm:"default:1;index" json:"status"` // 0:下线 1:上线 2:维护
	IsPublic      bool           `gorm:"default:true" json:"is_public"`  // 是否对用户可见
	SortOrder     int            `gorm:"default:0" json:"sort_order"`
	CallCount     int64          `gorm:"default:0" json:"call_count"`
	TotalRevenue  float64        `gorm:"type:decimal(15,4);default:0" json:"total_revenue"`

	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

func (AIService) TableName() string { return "ai_services" }

// CalculateCost 计算调用成本
func (s *AIService) CalculateCost(inputTokens, outputTokens int) float64 {
	switch s.BillingMode {
	case BillingPerRequest:
		return s.PricePerRequest
	case BillingPerToken:
		return float64(inputTokens)*s.PricePerInputToken + float64(outputTokens)*s.PricePerOutputToken
	case BillingFree:
		return 0
	default:
		return s.PricePerRequest
	}
}

// APIKey 用户API密钥
type APIKey struct {
	ID          uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID      uint64         `gorm:"index;not null" json:"user_id"`
	Name        string         `gorm:"type:varchar(64);not null" json:"name"`
	KeyID       string         `gorm:"type:varchar(32);uniqueIndex;not null" json:"key_id"`     // 公钥标识 ak_xxx
	KeySecret   string         `gorm:"type:varchar(256);not null" json:"-"`                      // 加密存储的私钥 sk_xxx
	KeyPreview  string         `gorm:"type:varchar(32)" json:"key_preview"`                     // sk_***xxxx 用于显示
	Scopes      string         `gorm:"type:varchar(255);default:'all'" json:"scopes"`            // 权限范围
	Status      int            `gorm:"default:1;index" json:"status"`                           // 0:禁用 1:启用
	ExpiresAt   *time.Time     `json:"expires_at"`
	LastUsedAt  *time.Time     `json:"last_used_at"`
	LastUsedIP  string         `gorm:"type:varchar(64)" json:"last_used_ip"`
	UsageCount  int64          `gorm:"default:0" json:"usage_count"`
	TotalCost   float64        `gorm:"type:decimal(15,6);default:0" json:"total_cost"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (APIKey) TableName() string { return "api_keys" }

// IsValid 是否有效
func (k *APIKey) IsValid() bool {
	if k.Status != 1 {
		return false
	}
	if k.ExpiresAt != nil && k.ExpiresAt.Before(time.Now()) {
		return false
	}
	return true
}
