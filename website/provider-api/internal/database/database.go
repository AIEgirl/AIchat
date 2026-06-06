package database

import (
	"log"
	"time"

	"github.com/aichat/relay/internal/models"
	"github.com/glebarez/sqlite"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func Init(driver, path string) (*gorm.DB, error) {
	gormLogger := logger.New(
		log.New(log.Writer(), "\r\n", log.LstdFlags),
		logger.Config{
			SlowThreshold:             200 * time.Millisecond,
			LogLevel:                  logger.Warn,
			IgnoreRecordNotFoundError: true,
			Colorful:                  false,
		},
	)

	db, err := gorm.Open(sqlite.Open(path), &gorm.Config{
		Logger: gormLogger,
	})
	if err != nil {
		return nil, err
	}

	sqlDB, _ := db.DB()
	sqlDB.SetMaxOpenConns(50)
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetConnMaxLifetime(time.Hour)

	if err := db.AutoMigrate(models.AllModels...); err != nil {
		return nil, err
	}

	if err := seed(db); err != nil {
		log.Printf("Seed error: %v", err)
	}
	return db, nil
}

func HashPassword(p string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(p), bcrypt.DefaultCost)
	return string(b), err
}

func CheckPassword(p, hash string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(p)) == nil
}

func seed(db *gorm.DB) error {
	// 管理员
	var count int64
	db.Model(&models.Admin{}).Where("username = ?", "admin").Count(&count)
	if count == 0 {
		hash, _ := HashPassword("Admin@123")
		admin := &models.Admin{
			Username: "admin", PasswordHash: hash,
			Nickname: "系统管理员", Role: "super_admin", Status: 1,
		}
		db.Create(admin)
	}

	// 分类
	db.Model(&models.Category{}).Count(&count)
	if count == 0 {
		cats := []models.Category{
			{Name: "IT服务", Icon: "💻", Color: "#3b82f6", SortOrder: 1},
			{Name: "设计创意", Icon: "🎨", Color: "#ec4899", SortOrder: 2},
			{Name: "营销推广", Icon: "📈", Color: "#f59e0b", SortOrder: 3},
			{Name: "咨询服务", Icon: "💼", Color: "#8b5cf6", SortOrder: 4},
			{Name: "教育培训", Icon: "📚", Color: "#10b981", SortOrder: 5},
			{Name: "生活服务", Icon: "🏠", Color: "#ef4444", SortOrder: 6},
		}
		db.Create(&cats)
	}

	// 服务商
	db.Model(&models.Provider{}).Count(&count)
	if count == 0 {
		now := time.Now()
		approved := now
		providers := []models.Provider{
			{
				UUID: "p1", Name: "云擎科技", CreditCode: "91110000XXXXXXXX1",
				Logo: "https://api.dicebear.com/7.x/initials/svg?seed=云擎&backgroundColor=3b82f6",
				Description: "专注于企业级云服务与AI解决方案，提供从架构设计到部署运维的全链路服务。",
				Website: "https://example.com", ContactName: "张明", ContactPhone: "13800138001",
				ContactEmail: "zhangming@yunqing.com", Address: "北京市朝阳区科技园A座",
				Region: "北京", CategoryID: 1, ServiceScope: "云计算、AI集成、数据迁移",
				PriceMin: 5000, PriceMax: 50000, CooperationMode: "项目制",
				Tags: "云服务,AI,数字化", Rating: 4.8, ResponseScore: 4.9, DealCount: 128,
				ViewCount: 1820, Status: 2, IsFeatured: true, SortOrder: 100,
				ApprovedTime: &approved,
			},
			{
				UUID: "p2", Name: "墨韵设计工作室", CreditCode: "91310000XXXXXXXX2",
				Logo: "https://api.dicebear.com/7.x/initials/svg?seed=墨韵&backgroundColor=ec4899",
				Description: "10年品牌设计经验，已为200+企业提供从VI到产品的整体视觉解决方案。",
				Website: "https://example.com", ContactName: "李雪", ContactPhone: "13800138002",
				ContactEmail: "lixue@moyun.com", Address: "上海市黄浦区南京路100号",
				Region: "上海", CategoryID: 2, ServiceScope: "品牌设计、UI/UX、视觉包装",
				PriceMin: 3000, PriceMax: 30000, CooperationMode: "项目制/季度合作",
				Tags: "设计,品牌,UI", Rating: 4.9, ResponseScore: 4.7, DealCount: 256,
				ViewCount: 3120, Status: 2, IsFeatured: true, SortOrder: 99,
				ApprovedTime: &approved,
			},
			{
				UUID: "p3", Name: "增长引擎营销", CreditCode: "91440000XXXXXXXX3",
				Logo: "https://api.dicebear.com/7.x/initials/svg?seed=增长&backgroundColor=f59e0b",
				Description: "全网整合营销专家，专注增长黑客方法论与精细化运营。",
				ContactName: "王强", ContactPhone: "13800138003",
				ContactEmail: "wangqiang@zengzhang.com", Address: "深圳市南山区科技园",
				Region: "深圳", CategoryID: 3, ServiceScope: "全案营销、SEO/SEM、社交媒体",
				PriceMin: 8000, PriceMax: 80000, CooperationMode: "年度服务",
				Tags: "营销,增长,运营", Rating: 4.6, ResponseScore: 4.5, DealCount: 89,
				ViewCount: 950, Status: 2, IsFeatured: true, SortOrder: 98,
				ApprovedTime: &approved,
			},
			{
				UUID: "p4", Name: "智库咨询", CreditCode: "91110000XXXXXXXX4",
				Logo: "https://api.dicebear.com/7.x/initials/svg?seed=智库&backgroundColor=8b5cf6",
				Description: "战略咨询与组织发展专家，麦肯锡背景团队。",
				ContactName: "陈博士", ContactPhone: "13800138004",
				ContactEmail: "chen@zhiku.com", Address: "北京市海淀区中关村",
				Region: "北京", CategoryID: 4, ServiceScope: "战略咨询、组织诊断、并购整合",
				PriceMin: 50000, PriceMax: 500000, CooperationMode: "项目制",
				Tags: "咨询,战略,管理", Rating: 5.0, ResponseScore: 4.8, DealCount: 32,
				ViewCount: 480, Status: 2, IsFeatured: false, SortOrder: 90,
				ApprovedTime: &approved,
			},
			{
				UUID: "p5", Name: "编程学院", CreditCode: "91330000XXXXXXXX5",
				Logo: "https://api.dicebear.com/7.x/initials/svg?seed=编程&backgroundColor=10b981",
				Description: "在线编程教育平台，专注培养实战型开发人才。",
				ContactName: "刘老师", ContactPhone: "13800138005",
				ContactEmail: "liu@biancheng.com", Address: "杭州市西湖区",
				Region: "杭州", CategoryID: 5, ServiceScope: "编程培训、企业内训、技术认证",
				PriceMin: 2000, PriceMax: 20000, CooperationMode: "课程购买/企业内训",
				Tags: "教育,编程,培训", Rating: 4.7, ResponseScore: 4.6, DealCount: 412,
				ViewCount: 5680, Status: 2, IsFeatured: true, SortOrder: 95,
				ApprovedTime: &approved,
			},
			{
				UUID: "p6", Name: "洁净家政", CreditCode: "91510000XXXXXXXX6",
				Logo: "https://api.dicebear.com/7.x/initials/svg?seed=洁净&backgroundColor=ef4444",
				Description: "高端家政服务，提供专业月嫂、育婴、养老护理。",
				ContactName: "赵经理", ContactPhone: "13800138006",
				ContactEmail: "zhao@jieqing.com", Address: "成都市锦江区",
				Region: "成都", CategoryID: 6, ServiceScope: "月嫂、育婴师、家政保洁",
				PriceMin: 5000, PriceMax: 30000, CooperationMode: "按月/按次",
				Tags: "家政,母婴,护理", Rating: 4.8, ResponseScore: 4.9, DealCount: 320,
				ViewCount: 2150, Status: 2, IsFeatured: false, SortOrder: 80,
				ApprovedTime: &approved,
			},
		}
		db.Create(&providers)
	}
	return nil
}
