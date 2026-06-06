package models

import (
	"time"

	"gorm.io/gorm"
)

// OrderType 订单类型
type OrderType string

const (
	OrderRecharge  OrderType = "recharge"  // 充值
	OrderConsume   OrderType = "consume"   // 消费
	OrderRefund    OrderType = "refund"    // 退款
	OrderSubscribe OrderType = "subscribe" // 订阅
)

// OrderStatus 订单状态
type OrderStatus string

const (
	OrderPending  OrderStatus = "pending"  // 待支付
	OrderPaid     OrderStatus = "paid"     // 已支付
	OrderFailed   OrderStatus = "failed"   // 失败
	OrderRefunded OrderStatus = "refunded" // 已退款
	OrderCanceled OrderStatus = "canceled" // 已取消
)

// PaymentMethod 支付方式
type PaymentMethod string

const (
	PaymentAlipay PaymentMethod = "alipay"
	PaymentWechat PaymentMethod = "wechat"
	PaymentStripe PaymentMethod = "stripe"
	PaymentBalance PaymentMethod = "balance" // 余额支付
)

// Transaction 交易流水
type Transaction struct {
	ID            uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	OrderNo       string         `gorm:"type:varchar(64);uniqueIndex;not null" json:"order_no"`
	UserID        uint64         `gorm:"index;not null" json:"user_id"`
	Type          OrderType      `gorm:"type:varchar(32);index" json:"type"`
	Amount        float64        `gorm:"type:decimal(15,4);not null" json:"amount"`
	BalanceBefore float64        `gorm:"type:decimal(15,4)" json:"balance_before"`
	BalanceAfter  float64        `gorm:"type:decimal(15,4)" json:"balance_after"`
	Status        OrderStatus    `gorm:"type:varchar(32);index;default:'pending'" json:"status"`
	PaymentMethod PaymentMethod  `gorm:"type:varchar(32);index" json:"payment_method"`
	PaymentRef    string         `gorm:"type:varchar(128);index" json:"payment_ref"` // 第三方支付流水号
	ServiceID     *uint64        `gorm:"index" json:"service_id,omitempty"`        // 关联服务
	APIKeyID      *uint64        `gorm:"index" json:"api_key_id,omitempty"`
	InputTokens   int            `gorm:"default:0" json:"input_tokens"`
	OutputTokens  int            `gorm:"default:0" json:"output_tokens"`
	Description   string         `gorm:"type:varchar(512)" json:"description"`
	Metadata      JSONMap        `gorm:"type:json" json:"metadata"`
	PaidAt        *time.Time     `json:"paid_at"`
	RefundedAt    *time.Time     `json:"refunded_at"`
	CreatedAt     time.Time      `gorm:"index" json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Transaction) TableName() string { return "transactions" }

// RechargePackage 充值套餐
type RechargePackage struct {
	ID          uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Name        string         `gorm:"type:varchar(64);not null" json:"name"`
	Amount      float64        `gorm:"type:decimal(10,2);not null" json:"amount"`        // 支付金额
	Balance     float64        `gorm:"type:decimal(10,2);not null" json:"balance"`        // 实际到账金额
	Bonus       float64        `gorm:"type:decimal(10,2);default:0" json:"bonus"`         // 赠送金额
	Description string         `gorm:"type:varchar(512)" json:"description"`
	SortOrder   int            `gorm:"default:0" json:"sort_order"`
	Status      int            `gorm:"default:1" json:"status"` // 0:下架 1:上架
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (RechargePackage) TableName() string { return "recharge_packages" }
