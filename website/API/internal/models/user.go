package models

import (
	"time"
	"gorm.io/gorm"
)

// User 用户模型
type User struct {
	ID           uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID         string         `gorm:"type:varchar(36);uniqueIndex;not null" json:"uuid"`
	Username     string         `gorm:"type:varchar(64);uniqueIndex;not null" json:"username"`
	Email        string         `gorm:"type:varchar(128);uniqueIndex;not null" json:"email"`
	PasswordHash string         `gorm:"type:varchar(256);not null" json:"-"`
	Nickname     string         `gorm:"type:varchar(64)" json:"nickname"`
	Avatar       string         `gorm:"type:varchar(512)" json:"avatar"`
	Phone        string         `gorm:"type:varchar(32)" json:"phone"`
	Role         string         `gorm:"type:varchar(32);default:'user';index" json:"role"` // user, admin, super_admin
	Status       int            `gorm:"default:1;index" json:"status"`                    // 0:禁用 1:正常 2:待验证
	EmailVerified bool          `gorm:"default:false" json:"email_verified"`
	Balance      float64        `gorm:"type:decimal(15,4);default:0" json:"balance"`
	FrozenBalance float64       `gorm:"type:decimal(15,4);default:0" json:"frozen_balance"`
	TotalSpent   float64        `gorm:"type:decimal(15,4);default:0" json:"total_spent"`
	TotalRecharged float64      `gorm:"type:decimal(15,4);default:0" json:"total_recharged"`
	LastLoginAt  *time.Time     `json:"last_login_at"`
	LastLoginIP  string         `gorm:"type:varchar(64)" json:"last_login_ip"`
	LoginCount   int            `gorm:"default:0" json:"login_count"`
	Remark       string         `gorm:"type:varchar(512)" json:"remark"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
}

// TableName 表名
func (User) TableName() string { return "users" }

// IsAdmin 是否管理员
func (u *User) IsAdmin() bool {
	return u.Role == "admin" || u.Role == "super_admin"
}

// IsActive 是否激活
func (u *User) IsActive() bool {
	return u.Status == 1
}

// VerificationCode 验证码
type VerificationCode struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Email      string    `gorm:"type:varchar(128);index;not null" json:"email"`
	Code       string    `gorm:"type:varchar(16);not null" json:"code"`
	Type       string    `gorm:"type:varchar(32);index" json:"type"` // register, reset_password, login
	ExpiresAt  time.Time `gorm:"index" json:"expires_at"`
	Used       bool      `gorm:"default:false" json:"used"`
	IP         string    `gorm:"type:varchar(64)" json:"ip"`
	CreatedAt  time.Time `json:"created_at"`
}

func (VerificationCode) TableName() string { return "verification_codes" }

// UserLoginLog 登录日志
type UserLoginLog struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    uint64    `gorm:"index" json:"user_id"`
	Username  string    `gorm:"type:varchar(64);index" json:"username"`
	IP        string    `gorm:"type:varchar(64);index" json:"ip"`
	UserAgent string    `gorm:"type:text" json:"user_agent"`
	Status    int       `json:"status"` // 0:失败 1:成功
	Message   string    `gorm:"type:varchar(255)" json:"message"`
	CreatedAt time.Time `gorm:"index" json:"created_at"`
}

func (UserLoginLog) TableName() string { return "user_login_logs" }
