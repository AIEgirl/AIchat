package handlers

import (
	"errors"
	"strconv"
	"time"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// UserHandler 用户处理器
type UserHandler struct {
	db *gorm.DB
}

// NewUserHandler 创建用户处理器
func NewUserHandler(db *gorm.DB) *UserHandler {
	return &UserHandler{db: db}
}

// UpdateProfileRequest 更新资料
type UpdateProfileRequest struct {
	Nickname string `json:"nickname"`
	Avatar   string `json:"avatar"`
	Phone    string `json:"phone"`
}

// UpdateProfile 更新个人资料
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint64("user_id")
	updates := map[string]interface{}{}
	if req.Nickname != "" {
		updates["nickname"] = req.Nickname
	}
	if req.Avatar != "" {
		updates["avatar"] = req.Avatar
	}
	if req.Phone != "" {
		updates["phone"] = req.Phone
	}

	if len(updates) == 0 {
		utils.BadRequest(c, "无更新内容")
		return
	}

	if err := h.db.Model(&models.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
		utils.ServerError(c, "更新失败")
		return
	}

	utils.SuccessWithMessage(c, "更新成功", nil)
}

// GetBalance 获取账户余额
func (h *UserHandler) GetBalance(c *gin.Context) {
	userID := c.GetUint64("user_id")
	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	utils.Success(c, gin.H{
		"balance":        user.Balance,
		"frozen_balance": user.FrozenBalance,
		"available":      user.Balance - user.FrozenBalance,
		"total_spent":    user.TotalSpent,
		"total_recharged": user.TotalRecharged,
	})
}

// GetTransactions 查询交易记录
func (h *UserHandler) GetTransactions(c *gin.Context) {
	userID := c.GetUint64("user_id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	txType := c.Query("type")

	query := h.db.Model(&models.Transaction{}).Where("user_id = ?", userID)
	if txType != "" {
		query = query.Where("type = ?", txType)
	}

	var total int64
	query.Count(&total)

	var transactions []models.Transaction
	if err := query.Order("created_at DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&transactions).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, transactions, total, page, pageSize)
}

// GetRechargePackages 获取充值套餐
func (h *UserHandler) GetRechargePackages(c *gin.Context) {
	var packages []models.RechargePackage
	if err := h.db.Where("status = ?", 1).Order("sort_order ASC").Find(&packages).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}
	utils.Success(c, packages)
}

// GetUsageStats 获取消费统计
func (h *UserHandler) GetUsageStats(c *gin.Context) {
	userID := c.GetUint64("user_id")

	// 今日消费
	var todayCost float64
	h.db.Model(&models.Transaction{}).
		Where("user_id = ? AND type = ? AND status = ? AND created_at >= ?",
			userID, models.OrderConsume, models.OrderPaid, time.Now().Truncate(24*time.Hour)).
		Select("COALESCE(SUM(amount), 0)").Scan(&todayCost)

	// 本月消费
	var monthCost float64
	h.db.Model(&models.Transaction{}).
		Where("user_id = ? AND type = ? AND status = ? AND created_at >= ?",
			userID, models.OrderConsume, models.OrderPaid, time.Now().AddDate(0, 0, -time.Now().Day()+1)).
		Select("COALESCE(SUM(amount), 0)").Scan(&monthCost)

	// 总消费
	var totalCost float64
	h.db.Model(&models.Transaction{}).
		Where("user_id = ? AND type = ? AND status = ?",
			userID, models.OrderConsume, models.OrderPaid).
		Select("COALESCE(SUM(amount), 0)").Scan(&totalCost)

	// 总调用次数
	var callCount int64
	h.db.Model(&models.APIRequestLog{}).Where("user_id = ?", userID).Count(&callCount)

	utils.Success(c, gin.H{
		"today_cost":   todayCost,
		"month_cost":   monthCost,
		"total_cost":   totalCost,
		"call_count":   callCount,
	})
}

// CheckAuthStatus 检查认证状态
func (h *UserHandler) CheckAuthStatus(c *gin.Context) {
	userID := c.GetUint64("user_id")
	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			utils.NotFound(c, "用户不存在")
			return
		}
		utils.ServerError(c, "查询失败")
		return
	}
	utils.Success(c, gin.H{
		"active":        user.IsActive(),
		"email_verified": user.EmailVerified,
		"role":          user.Role,
	})
}
