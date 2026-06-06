package models

import (
	"time"

	"gorm.io/gorm"
)

// AllModels 所有模型列表，用于自动迁移
var AllModels = []interface{}{
	&User{},
	&VerificationCode{},
	&UserLoginLog{},
	&AIService{},
	&APIKey{},
	&Transaction{},
	&RechargePackage{},
	&APIRequestLog{},
	&SystemConfig{},
	&OperationLog{},
	&AnomalyDetection{},
	&IPBlacklist{},
}

// AutoMigrate 自动迁移所有表
func AutoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(AllModels...)
}

// BaseModel 基础模型
type BaseModel struct {
	ID        uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
