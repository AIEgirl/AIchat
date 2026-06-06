package models

import (
	"time"

	"gorm.io/gorm"
)

// ProviderStatus 服务商状态
type ProviderStatus int

const (
	StatusPending  ProviderStatus = 0 // 待审核
	StatusReviewing ProviderStatus = 1 // 审核中
	StatusApproved ProviderStatus = 2 // 已通过
	StatusDisabled ProviderStatus = 3 // 已禁用
	StatusRejected ProviderStatus = 4 // 未通过
)

// Provider 服务商
type Provider struct {
	ID              uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID            string         `gorm:"type:varchar(36);uniqueIndex;not null" json:"uuid"`
	Name            string         `gorm:"type:varchar(128);not null;index" json:"name"`
	CreditCode      string         `gorm:"type:varchar(64)" json:"credit_code"`
	Logo            string         `gorm:"type:varchar(512)" json:"logo"`
	Description     string         `gorm:"type:text" json:"description"`
	Website         string         `gorm:"type:varchar(512)" json:"website"`
	ContactName     string         `gorm:"type:varchar(64)" json:"contact_name"`
	ContactPhone    string         `gorm:"type:varchar(32);index" json:"contact_phone"`
	ContactEmail    string         `gorm:"type:varchar(128);index" json:"contact_email"`
	Address         string         `gorm:"type:varchar(512)" json:"address"`
	Region          string         `gorm:"type:varchar(64);index" json:"region"`
	CategoryID      uint64         `gorm:"index" json:"category_id"`
	ServiceScope    string         `gorm:"type:text" json:"service_scope"`
	PriceMin        float64        `gorm:"type:decimal(10,2);default:0" json:"price_min"`
	PriceMax        float64        `gorm:"type:decimal(10,2);default:0" json:"price_max"`
	CooperationMode string         `gorm:"type:varchar(64)" json:"cooperation_mode"`
	Tags            string         `gorm:"type:varchar(512)" json:"tags"`
	Rating          float64        `gorm:"type:decimal(3,2);default:0" json:"rating"`
	ResponseScore   float64        `gorm:"type:decimal(3,2);default:0" json:"response_score"`
	DealCount       int            `gorm:"default:0" json:"deal_count"`
	ViewCount       int            `gorm:"default:0" json:"view_count"`
	FavoriteCount   int            `gorm:"default:0" json:"favorite_count"`
	Status          ProviderStatus `gorm:"default:0;index" json:"status"`
	IsFeatured      bool           `gorm:"default:false;index" json:"is_featured"`
	SortOrder       int            `gorm:"default:0" json:"sort_order"`
	SubmitTime      *time.Time     `json:"submit_time"`
	ApprovedTime    *time.Time     `json:"approved_time"`
	ApprovedBy      *uint64        `json:"approved_by"`
	RejectReason    string         `gorm:"type:varchar(512)" json:"reject_reason"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Provider) TableName() string { return "providers" }

// Category 分类
type Category struct {
	ID        uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Name      string         `gorm:"type:varchar(64);not null" json:"name"`
	Icon      string         `gorm:"type:varchar(128)" json:"icon"`
	Color     string         `gorm:"type:varchar(16)" json:"color"`
	ParentID  uint64         `gorm:"default:0;index" json:"parent_id"`
	SortOrder int            `gorm:"default:0" json:"sort_order"`
	Status    int            `gorm:"default:1" json:"status"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Category) TableName() string { return "categories" }

// Qualification 资质材料
type Qualification struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	ProviderID uint64    `gorm:"index;not null" json:"provider_id"`
	Type       string    `gorm:"type:varchar(32)" json:"type"`
	Name       string    `gorm:"type:varchar(128)" json:"name"`
	FileURL    string    `gorm:"type:varchar(512)" json:"file_url"`
	FileType   string    `gorm:"type:varchar(16)" json:"file_type"`
	ExpireDate *time.Time `json:"expire_date"`
	CreatedAt  time.Time  `json:"created_at"`
}

func (Qualification) TableName() string { return "qualifications" }

// ReviewLog 审核记录
type ReviewLog struct {
	ID           uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	ProviderID   uint64    `gorm:"index;not null" json:"provider_id"`
	ReviewerID   uint64    `gorm:"index" json:"reviewer_id"`
	ReviewerName string    `gorm:"type:varchar(64)" json:"reviewer_name"`
	Action       string    `gorm:"type:varchar(32);index" json:"action"`
	FromStatus   int       `json:"from_status"`
	ToStatus     int       `json:"to_status"`
	Comment      string    `gorm:"type:text" json:"comment"`
	CreatedAt    time.Time `gorm:"index" json:"created_at"`
}

func (ReviewLog) TableName() string { return "review_logs" }

// Admin 管理员
type Admin struct {
	ID           uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Username     string    `gorm:"type:varchar(64);uniqueIndex;not null" json:"username"`
	PasswordHash string    `gorm:"type:varchar(256);not null" json:"-"`
	Nickname     string    `gorm:"type:varchar(64)" json:"nickname"`
	Avatar       string    `gorm:"type:varchar(512)" json:"avatar"`
	Role         string    `gorm:"type:varchar(32);default:'admin'" json:"role"`
	Status       int       `gorm:"default:1" json:"status"`
	LastLoginAt  *time.Time `json:"last_login_at"`
	LastLoginIP  string    `gorm:"type:varchar(64)" json:"last_login_ip"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

func (Admin) TableName() string { return "admins" }

// OperationLog 操作日志
type OperationLog struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AdminID    uint64    `gorm:"index" json:"admin_id"`
	Username   string    `gorm:"type:varchar(64);index" json:"username"`
	Module     string    `gorm:"type:varchar(64);index" json:"module"`
	Action     string    `gorm:"type:varchar(64)" json:"action"`
	Resource   string    `gorm:"type:varchar(128)" json:"resource"`
	IP         string    `gorm:"type:varchar(64)" json:"ip"`
	StatusCode int       `json:"status_code"`
	Detail     string    `gorm:"type:text" json:"detail"`
	CreatedAt  time.Time `gorm:"index" json:"created_at"`
}

func (OperationLog) TableName() string { return "operation_logs" }

// ContactRecord 联系记录
type ContactRecord struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	ProviderID uint64    `gorm:"index;not null" json:"provider_id"`
	Name       string    `gorm:"type:varchar(64)" json:"name"`
	Phone      string    `gorm:"type:varchar(32)" json:"phone"`
	Email      string    `gorm:"type:varchar(128)" json:"email"`
	Message    string    `gorm:"type:text" json:"message"`
	IP         string    `gorm:"type:varchar(64)" json:"ip"`
	CreatedAt  time.Time `gorm:"index" json:"created_at"`
}

func (ContactRecord) TableName() string { return "contact_records" }

var AllModels = []interface{}{
	&Provider{}, &Category{}, &Qualification{}, &ReviewLog{},
	&Admin{}, &OperationLog{}, &ContactRecord{},
}
