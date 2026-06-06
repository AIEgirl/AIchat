package handlers

import (
	"strconv"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// AIServiceHandler AI服务处理器
type AIServiceHandler struct {
	db *gorm.DB
}

// NewAIServiceHandler 创建AI服务处理器
func NewAIServiceHandler(db *gorm.DB) *AIServiceHandler {
	return &AIServiceHandler{db: db}
}

// List 公开的AI服务列表
func (h *AIServiceHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	keyword := c.Query("keyword")
	provider := c.Query("provider")

	query := h.db.Model(&models.AIService{}).Where("status = ? AND is_public = ?", 1, true)
	if keyword != "" {
		query = query.Where("name LIKE ? OR code LIKE ? OR description LIKE ?",
			"%"+keyword+"%", "%"+keyword+"%", "%"+keyword+"%")
	}
	if provider != "" {
		query = query.Where("provider = ?", provider)
	}

	var total int64
	query.Count(&total)

	var services []models.AIService
	if err := query.Order("sort_order ASC, id ASC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&services).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, services, total, page, pageSize)
}

// Get 获取单个服务详情
func (h *AIServiceHandler) Get(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var service models.AIService
	if err := h.db.First(&service, id).Error; err != nil {
		utils.NotFound(c, "服务不存在")
		return
	}
	utils.Success(c, service)
}

// GetByCode 通过code获取
func (h *AIServiceHandler) GetByCode(c *gin.Context) {
	code := c.Param("code")
	var service models.AIService
	if err := h.db.Where("code = ?", code).First(&service).Error; err != nil {
		utils.NotFound(c, "服务不存在")
		return
	}
	utils.Success(c, service)
}

// EstimateCost 估算调用费用
func (h *AIServiceHandler) EstimateCost(c *gin.Context) {
	code := c.Param("code")
	var req struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	}
	c.ShouldBindJSON(&req)

	var service models.AIService
	if err := h.db.Where("code = ?", code).First(&service).Error; err != nil {
		utils.NotFound(c, "服务不存在")
		return
	}

	cost := service.CalculateCost(req.InputTokens, req.OutputTokens)
	utils.Success(c, gin.H{
		"service_code": service.Code,
		"billing_mode": service.BillingMode,
		"cost":         cost,
		"currency":     "CNY",
	})
}

// AdminList 管理员列表（包含所有状态）
func (h *AIServiceHandler) AdminList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")

	query := h.db.Model(&models.AIService{})
	if keyword != "" {
		query = query.Where("name LIKE ? OR code LIKE ?", "%"+keyword+"%", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var services []models.AIService
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&services).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, services, total, page, pageSize)
}

// CreateServiceRequest 创建AI服务
type CreateServiceRequest struct {
	Name                string                 `json:"name" binding:"required"`
	Code                string                 `json:"code" binding:"required"`
	Provider            string                 `json:"provider"`
	Description         string                 `json:"description"`
	Avatar              string                 `json:"avatar"`
	Tags                string                 `json:"tags"`
	Endpoint            string                 `json:"endpoint" binding:"required"`
	Method              string                 `json:"method"`
	Headers             map[string]interface{} `json:"headers"`
	RequestSchema       map[string]interface{} `json:"request_schema"`
	ResponsePath        string                 `json:"response_path"`
	Timeout             int                    `json:"timeout"`
	BillingMode         models.BillingMode     `json:"billing_mode"`
	PricePerRequest     float64                `json:"price_per_request"`
	PricePerInputToken  float64                `json:"price_per_input_token"`
	PricePerOutputToken float64                `json:"price_per_output_token"`
	MonthlyPrice        float64                `json:"monthly_price"`
	MinBalance          float64                `json:"min_balance"`
	MaxQPS              int                    `json:"max_qps"`
	MaxConcurrent       int                    `json:"max_concurrent"`
	Status              int                    `json:"status"`
	IsPublic            bool                   `json:"is_public"`
	SortOrder           int                    `json:"sort_order"`
}

// Create 创建AI服务
func (h *AIServiceHandler) Create(c *gin.Context) {
	var req CreateServiceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误: "+err.Error())
		return
	}

	// 检查code唯一性
	var count int64
	h.db.Model(&models.AIService{}).Where("code = ?", req.Code).Count(&count)
	if count > 0 {
		utils.Fail(c, utils.CodeConflict, "服务代码已存在")
		return
	}

	service := &models.AIService{
		UUID:                utils.GenerateUUID(),
		Name:                req.Name,
		Code:                req.Code,
		Provider:            req.Provider,
		Description:         req.Description,
		Avatar:              req.Avatar,
		Tags:                req.Tags,
		Endpoint:            req.Endpoint,
		Method:              req.Method,
		Headers:             req.Headers,
		RequestSchema:       req.RequestSchema,
		ResponsePath:        req.ResponsePath,
		Timeout:             req.Timeout,
		BillingMode:         req.BillingMode,
		PricePerRequest:     req.PricePerRequest,
		PricePerInputToken:  req.PricePerInputToken,
		PricePerOutputToken: req.PricePerOutputToken,
		MonthlyPrice:        req.MonthlyPrice,
		MinBalance:          req.MinBalance,
		MaxQPS:              req.MaxQPS,
		MaxConcurrent:       req.MaxConcurrent,
		Status:              req.Status,
		IsPublic:            req.IsPublic,
		SortOrder:           req.SortOrder,
	}

	if service.Method == "" {
		service.Method = "POST"
	}
	if service.BillingMode == "" {
		service.BillingMode = models.BillingPerRequest
	}

	if err := h.db.Create(service).Error; err != nil {
		utils.ServerError(c, "创建失败: "+err.Error())
		return
	}

	utils.SuccessWithMessage(c, "创建成功", service)
}

// Update 更新AI服务
func (h *AIServiceHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var service models.AIService
	if err := h.db.First(&service, id).Error; err != nil {
		utils.NotFound(c, "服务不存在")
		return
	}

	var req CreateServiceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 不允许修改Code
	service.Name = req.Name
	service.Provider = req.Provider
	service.Description = req.Description
	service.Avatar = req.Avatar
	service.Tags = req.Tags
	service.Endpoint = req.Endpoint
	service.Method = req.Method
	service.Headers = req.Headers
	service.RequestSchema = req.RequestSchema
	service.ResponsePath = req.ResponsePath
	service.Timeout = req.Timeout
	service.BillingMode = req.BillingMode
	service.PricePerRequest = req.PricePerRequest
	service.PricePerInputToken = req.PricePerInputToken
	service.PricePerOutputToken = req.PricePerOutputToken
	service.MonthlyPrice = req.MonthlyPrice
	service.MinBalance = req.MinBalance
	service.MaxQPS = req.MaxQPS
	service.MaxConcurrent = req.MaxConcurrent
	service.Status = req.Status
	service.IsPublic = req.IsPublic
	service.SortOrder = req.SortOrder

	if err := h.db.Save(&service).Error; err != nil {
		utils.ServerError(c, "更新失败")
		return
	}

	utils.SuccessWithMessage(c, "更新成功", service)
}

// Delete 删除AI服务
func (h *AIServiceHandler) Delete(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	if err := h.db.Delete(&models.AIService{}, id).Error; err != nil {
		utils.ServerError(c, "删除失败")
		return
	}
	utils.SuccessWithMessage(c, "删除成功", nil)
}

// ToggleStatus 切换状态
func (h *AIServiceHandler) ToggleStatus(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var service models.AIService
	if err := h.db.First(&service, id).Error; err != nil {
		utils.NotFound(c, "服务不存在")
		return
	}
	newStatus := 0
	if service.Status == 0 {
		newStatus = 1
	}
	h.db.Model(&service).Update("status", newStatus)
	utils.SuccessWithMessage(c, "状态已更新", gin.H{"status": newStatus})
}
