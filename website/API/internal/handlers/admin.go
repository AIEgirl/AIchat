package handlers

import (
	"strconv"
	"time"

	"github.com/aichat/relay/internal/database"
	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// AdminHandler 管理员处理器
type AdminHandler struct {
	db *gorm.DB
}

// NewAdminHandler 创建管理员处理器
func NewAdminHandler(db *gorm.DB) *AdminHandler {
	return &AdminHandler{db: db}
}

// AdminUserList 管理员查看用户列表
func (h *AdminHandler) UserList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	status := c.Query("status")
	role := c.Query("role")

	query := h.db.Model(&models.User{})
	if keyword != "" {
		query = query.Where("username LIKE ? OR email LIKE ? OR nickname LIKE ?",
			"%"+keyword+"%", "%"+keyword+"%", "%"+keyword+"%")
	}
	if status != "" {
		if s, err := strconv.Atoi(status); err == nil {
			query = query.Where("status = ?", s)
		}
	}
	if role != "" {
		query = query.Where("role = ?", role)
	}

	var total int64
	query.Count(&total)

	var users []models.User
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&users).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	// 脱敏处理
	for i := range users {
		users[i].Email = utils.MaskEmail(users[i].Email)
		users[i].Phone = utils.MaskPhone(users[i].Phone)
		users[i].PasswordHash = ""
	}

	utils.Page(c, users, total, page, pageSize)
}

// AdminGetUser 获取用户详情
func (h *AdminHandler) GetUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var user models.User
	if err := h.db.First(&user, id).Error; err != nil {
		utils.NotFound(c, "用户不存在")
		return
	}
	user.PasswordHash = ""
	utils.Success(c, user)
}

// UpdateUserRequest 更新用户请求
type UpdateUserRequest struct {
	Nickname *string `json:"nickname"`
	Role     *string `json:"role"`
	Status   *int    `json:"status"`
	Remark   *string `json:"remark"`
}

// UpdateUser 更新用户
func (h *AdminHandler) UpdateUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var req UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.Nickname != nil {
		updates["nickname"] = *req.Nickname
	}
	if req.Role != nil {
		updates["role"] = *req.Role
	}
	if req.Status != nil {
		updates["status"] = *req.Status
	}
	if req.Remark != nil {
		updates["remark"] = *req.Remark
	}

	if len(updates) == 0 {
		utils.BadRequest(c, "无更新内容")
		return
	}

	if err := h.db.Model(&models.User{}).Where("id = ?", id).Updates(updates).Error; err != nil {
		utils.ServerError(c, "更新失败")
		return
	}

	utils.SuccessWithMessage(c, "更新成功", nil)
}

// ResetUserPassword 管理员重置用户密码
func (h *AdminHandler) ResetUserPassword(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var req struct {
		NewPassword string `json:"new_password" binding:"required,min=8"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	passwordHash, _ := database.HashPassword(req.NewPassword)
	if err := h.db.Model(&models.User{}).Where("id = ?", id).Update("password_hash", passwordHash).Error; err != nil {
		utils.ServerError(c, "重置失败")
		return
	}

	utils.SuccessWithMessage(c, "密码已重置", gin.H{
		"new_password": req.NewPassword,
	})
}

// DeleteUser 删除用户
func (h *AdminHandler) DeleteUser(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	if err := h.db.Delete(&models.User{}, id).Error; err != nil {
		utils.ServerError(c, "删除失败")
		return
	}
	utils.SuccessWithMessage(c, "用户已删除", nil)
}

// UserTransactions 查看用户交易记录
func (h *AdminHandler) UserTransactions(c *gin.Context) {
	userID, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	query := h.db.Model(&models.Transaction{}).Where("user_id = ?", userID)
	var total int64
	query.Count(&total)

	var transactions []models.Transaction
	if err := query.Order("created_at DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&transactions).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, transactions, total, page, pageSize)
}

// DashboardStats 仪表盘统计
func (h *AdminHandler) DashboardStats(c *gin.Context) {
	now := time.Now()
	todayStart := now.Truncate(24 * time.Hour)
	monthStart := now.AddDate(0, 0, -now.Day()+1)

	// 总用户数
	var totalUsers int64
	h.db.Model(&models.User{}).Count(&totalUsers)
	var todayNewUsers int64
	h.db.Model(&models.User{}).Where("created_at >= ?", todayStart).Count(&todayNewUsers)

	// 总调用次数
	var totalCalls int64
	h.db.Model(&models.APIRequestLog{}).Count(&totalCalls)
	var todayCalls int64
	h.db.Model(&models.APIRequestLog{}).Where("created_at >= ?", todayStart).Count(&todayCalls)

	// 总收入（已完成充值）
	var totalRevenue float64
	h.db.Model(&models.Transaction{}).
		Where("type = ? AND status = ?", models.OrderRecharge, models.OrderPaid).
		Select("COALESCE(SUM(amount), 0)").Scan(&totalRevenue)
	var todayRevenue float64
	h.db.Model(&models.Transaction{}).
		Where("type = ? AND status = ? AND paid_at >= ?", models.OrderRecharge, models.OrderPaid, todayStart).
		Select("COALESCE(SUM(amount), 0)").Scan(&todayRevenue)

	// 总消费
	var totalConsumption float64
	h.db.Model(&models.Transaction{}).
		Where("type = ? AND status = ?", models.OrderConsume, models.OrderPaid).
		Select("COALESCE(SUM(amount), 0)").Scan(&totalConsumption)
	var monthConsumption float64
	h.db.Model(&models.Transaction{}).
		Where("type = ? AND status = ? AND paid_at >= ?", models.OrderConsume, models.OrderPaid, monthStart).
		Select("COALESCE(SUM(amount), 0)").Scan(&monthConsumption)

	// 活跃AI服务数
	var activeServices int64
	h.db.Model(&models.AIService{}).Where("status = ?", 1).Count(&activeServices)

	// 总API Key数
	var totalAPIKeys int64
	h.db.Model(&models.APIKey{}).Count(&totalAPIKeys)

	utils.Success(c, gin.H{
		"users": gin.H{
			"total":     totalUsers,
			"today_new": todayNewUsers,
		},
		"calls": gin.H{
			"total":    totalCalls,
			"today":    todayCalls,
		},
		"revenue": gin.H{
			"total":  totalRevenue,
			"today":  todayRevenue,
		},
		"consumption": gin.H{
			"total": totalConsumption,
			"month": monthConsumption,
		},
		"services": gin.H{
			"active": activeServices,
		},
		"api_keys": totalAPIKeys,
	})
}

// OperationLogs 操作日志
func (h *AdminHandler) OperationLogs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	query := h.db.Model(&models.OperationLog{})
	if username := c.Query("username"); username != "" {
		query = query.Where("username = ?", username)
	}
	if module := c.Query("module"); module != "" {
		query = query.Where("module = ?", module)
	}

	var total int64
	query.Count(&total)

	var logs []models.OperationLog
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&logs).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, logs, total, page, pageSize)
}

// AnomalyLogs 异常日志
func (h *AdminHandler) AnomalyLogs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	query := h.db.Model(&models.AnomalyDetection{})
	if anomalyType := c.Query("type"); anomalyType != "" {
		query = query.Where("type = ?", anomalyType)
	}

	var total int64
	query.Count(&total)

	var logs []models.AnomalyDetection
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&logs).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, logs, total, page, pageSize)
}

// AnomalyStats 异常统计
func (h *AdminHandler) AnomalyStats(c *gin.Context) {
	var totalCount int64
	h.db.Model(&models.AnomalyDetection{}).Count(&totalCount)
	var todayCount int64
	h.db.Model(&models.AnomalyDetection{}).Where("created_at >= ?", time.Now().Truncate(24*time.Hour)).Count(&todayCount)

	// 按类型分组
	type TypeCount struct {
		Type  string `json:"type"`
		Count int64  `json:"count"`
	}
	var typeStats []TypeCount
	h.db.Model(&models.AnomalyDetection{}).
		Select("type, COUNT(*) as count").
		Group("type").
		Scan(&typeStats)

	utils.Success(c, gin.H{
		"total":      totalCount,
		"today":      todayCount,
		"by_type":    typeStats,
	})
}

// IPBlacklists IP黑名单
func (h *AdminHandler) ListBlacklist(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	query := h.db.Model(&models.IPBlacklist{})
	var total int64
	query.Count(&total)

	var list []models.IPBlacklist
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&list).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, list, total, page, pageSize)
}

// AddBlacklist 添加黑名单
func (h *AdminHandler) AddBlacklist(c *gin.Context) {
	var req struct {
		IP        string `json:"ip" binding:"required"`
		Reason    string `json:"reason"`
		ExpiresAt string `json:"expires_at"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	entry := &models.IPBlacklist{
		IP:     req.IP,
		Reason: req.Reason,
	}
	if req.ExpiresAt != "" {
		if t, err := time.Parse(time.RFC3339, req.ExpiresAt); err == nil {
			entry.ExpiresAt = &t
		}
	}
	h.db.Create(entry)
	utils.SuccessWithMessage(c, "已添加黑名单", entry)
}

// RemoveBlacklist 移除黑名单
func (h *AdminHandler) RemoveBlacklist(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	h.db.Delete(&models.IPBlacklist{}, id)
	utils.SuccessWithMessage(c, "已移除", nil)
}
