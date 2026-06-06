package handlers

import (
	"context"
	"encoding/json"
	"io"
	"strconv"
	"time"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/services"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// APICallHandler API调用处理器
type APICallHandler struct {
	db    *gorm.DB
	proxy *services.AIProxyService
	enc   *services.EncryptionService
}

// NewAPICallHandler 创建API调用处理器
func NewAPICallHandler(db *gorm.DB, proxy *services.AIProxyService, enc *services.EncryptionService) *APICallHandler {
	return &APICallHandler{db: db, proxy: proxy, enc: enc}
}

// Call 调用AI服务
func (h *APICallHandler) Call(c *gin.Context) {
	serviceCode := c.Param("code")
	apiKeyID := c.GetUint64("api_key_id")
	userID := c.GetUint64("user_id")

	// 查询服务
	var service models.AIService
	if err := h.db.Where("code = ? AND status = ?", serviceCode, 1).First(&service).Error; err != nil {
		utils.NotFound(c, "AI服务不存在或已下线")
		return
	}

	// 验证API Key
	var apiKey models.APIKey
	if err := h.db.First(&apiKey, apiKeyID).Error; err != nil || !apiKey.IsValid() || apiKey.UserID != userID {
		utils.Unauthorized(c, "API Key无效")
		return
	}

	// 检查用户余额
	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.Unauthorized(c, "用户不存在")
		return
	}
	if user.Balance < service.MinBalance {
		utils.Fail(c, utils.CodeBadRequest, "余额不足，请先充值")
		return
	}

	// 读取请求体
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		utils.BadRequest(c, "读取请求体失败")
		return
	}

	// 验证请求
	if err := h.proxy.ValidateRequest(&service, body); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	// 解密API Key的secret用于上游认证
	upstreamSecret, _ := h.enc.DecryptAPIKey(apiKey.KeySecret)

	// 调用AI服务
	ctx, cancel := context.WithTimeout(c.Request.Context(), time.Duration(service.Timeout)*time.Second)
	defer cancel()

	result := h.proxy.Call(ctx, &service, body, upstreamSecret)

	if result.Error != nil {
		h.logCall(c, &service, &apiKey, &user, body, result, 0, 0)
		utils.ServerError(c, "调用AI服务失败: "+result.Error.Error())
		return
	}

	// 计算费用
	cost := service.CalculateCost(result.InputTokens, result.OutputTokens)

	// 检查余额
	if user.Balance < cost {
		h.logCall(c, &service, &apiKey, &user, body, result, result.InputTokens, result.OutputTokens)
		utils.Fail(c, utils.CodeBadRequest, "余额不足，本次调用预计费用: "+strconv.FormatFloat(cost, 'f', 4, 64))
		return
	}

	// 扣减余额
	if cost > 0 {
		if err := h.deductBalance(userID, cost, &service, &apiKey, result.InputTokens, result.OutputTokens); err != nil {
			utils.ServerError(c, "扣费失败")
			return
		}
	}

	// 更新服务调用次数和收入
	h.db.Model(&service).Updates(map[string]interface{}{
		"call_count":    gorm.Expr("call_count + 1"),
		"total_revenue": gorm.Expr("total_revenue + ?", cost),
	})

	// 记录日志
	h.logCall(c, &service, &apiKey, &user, body, result, result.InputTokens, result.OutputTokens)

	// 复制上游响应头
	for k, v := range result.Headers {
		if k == "Content-Length" || k == "Content-Encoding" || k == "Transfer-Encoding" {
			continue
		}
		c.Writer.Header().Set(k, v[0])
	}

	c.Data(result.StatusCode, "application/json", result.Response)
	// 在响应头中加入费用信息
	c.Writer.Header().Set("X-Request-Cost", strconv.FormatFloat(cost, 'f', 6, 64))
	c.Writer.Header().Set("X-Balance-After", strconv.FormatFloat(user.Balance-cost, 'f', 4, 64))
}

// deductBalance 扣减余额（事务）
func (h *APICallHandler) deductBalance(userID uint64, cost float64, service *models.AIService, apiKey *models.APIKey, inputTokens, outputTokens int) error {
	return h.db.Transaction(func(tx *gorm.DB) error {
		// 锁定用户行
		var user models.User
		if err := tx.Set("gorm:query_option", "FOR UPDATE").First(&user, userID).Error; err != nil {
			return err
		}

		if user.Balance < cost {
			return gorm.ErrInvalidData
		}

		balanceBefore := user.Balance
		user.Balance -= cost
		user.TotalSpent += cost
		if err := tx.Save(&user).Error; err != nil {
			return err
		}

		// 创建消费交易记录
		sid := service.ID
		akid := apiKey.ID
		txn := &models.Transaction{
			OrderNo:        utils.GenerateOrderNo(),
			UserID:         userID,
			Type:           models.OrderConsume,
			Amount:         cost,
			BalanceBefore:  balanceBefore,
			BalanceAfter:   user.Balance,
			Status:         models.OrderPaid,
			PaymentMethod:  models.PaymentBalance,
			ServiceID:      &sid,
			APIKeyID:       &akid,
			InputTokens:    inputTokens,
			OutputTokens:   outputTokens,
			Description:    "AI服务调用: " + service.Name,
			PaidAt:         &time.Time{},
		}
		now := time.Now()
		txn.PaidAt = &now
		if err := tx.Create(txn).Error; err != nil {
			return err
		}

		// 更新API Key使用情况
		tx.Model(apiKey).Updates(map[string]interface{}{
			"usage_count": gorm.Expr("usage_count + 1"),
			"total_cost":  gorm.Expr("total_cost + ?", cost),
			"last_used_at": &now,
			"last_used_ip": apiKey.LastUsedIP,
		})

		return nil
	})
}

// logCall 记录调用日志
func (h *APICallHandler) logCall(c *gin.Context, service *models.AIService, apiKey *models.APIKey, user *models.User, reqBody []byte, result *services.CallResult, inputTokens, outputTokens int) {
	cost := service.CalculateCost(inputTokens, outputTokens)

	log := &models.APIRequestLog{
		RequestID:    uuid.New().String(),
		UserID:       user.ID,
		APIKeyID:     apiKey.ID,
		ServiceID:    service.ID,
		ServiceCode:  service.Code,
		Method:       c.Request.Method,
		Path:         c.Request.URL.Path,
		IP:           c.ClientIP(),
		UserAgent:    c.Request.UserAgent(),
		RequestSize:  len(reqBody),
		ResponseSize: len(result.Response),
		StatusCode:   result.StatusCode,
		InputTokens:  inputTokens,
		OutputTokens: outputTokens,
		Cost:         cost,
		Duration:     result.Duration.Milliseconds(),
	}
	if result.Error != nil {
		log.Error = result.Error.Error()
	}
	if len(reqBody) > 2000 {
		// 不记录过大请求体
	}
	h.db.Create(log)
}

// ChatCompletion 兼容OpenAI格式的聊天补全接口
func (h *APICallHandler) ChatCompletion(c *gin.Context) {
	h.Call(c)
}

// GetCallLogs 获取调用日志
func (h *APICallHandler) GetCallLogs(c *gin.Context) {
	userID := c.GetUint64("user_id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	query := h.db.Model(&models.APIRequestLog{}).Where("user_id = ?", userID)

	if serviceCode := c.Query("service_code"); serviceCode != "" {
		query = query.Where("service_code = ?", serviceCode)
	}
	if statusCode := c.Query("status_code"); statusCode != "" {
		if sc, err := strconv.Atoi(statusCode); err == nil {
			query = query.Where("status_code = ?", sc)
		}
	}

	var total int64
	query.Count(&total)

	var logs []models.APIRequestLog
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&logs).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, logs, total, page, pageSize)
}

// ChatStream 流式调用（占位实现）
func (h *APICallHandler) ChatStream(c *gin.Context) {
	// 流式调用可使用SSE实现
	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")

	flusher, ok := c.Writer.(interface {
		Flush()
	})
	if !ok {
		utils.ServerError(c, "流式响应不支持")
		return
	}

	body, _ := json.Marshal(map[string]string{"error": "stream not fully implemented, please use non-stream mode"})
	_, _ = io.WriteString(c.Writer, "data: "+string(body)+"\n\n")
	flusher.Flush()
}

// Replay 重放请求（调试用）
func (h *APICallHandler) Replay(c *gin.Context) {
	logID, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	userID := c.GetUint64("user_id")

	var log models.APIRequestLog
	if err := h.db.Where("user_id = ? AND id = ?", userID, logID).First(&log).Error; err != nil {
		utils.NotFound(c, "日志不存在")
		return
	}
	utils.Success(c, log)
}
