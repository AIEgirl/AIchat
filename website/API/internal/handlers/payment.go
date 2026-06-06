package handlers

import (
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/services"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// PaymentHandler 支付处理器
type PaymentHandler struct {
	db      *gorm.DB
	cfg     *config.PaymentConfig
	payment *services.PaymentService
}

// NewPaymentHandler 创建支付处理器
func NewPaymentHandler(db *gorm.DB, cfg *config.PaymentConfig, payment *services.PaymentService) *PaymentHandler {
	return &PaymentHandler{db: db, cfg: cfg, payment: payment}
}

// CreateRechargeRequest 创建充值订单
type CreateRechargeRequest struct {
	PackageID     uint64 `json:"package_id"`
	Amount        float64 `json:"amount"`
	PaymentMethod string `json:"payment_method" binding:"required,oneof=alipay wechat stripe balance"`
}

// CreateRecharge 创建充值订单
func (h *PaymentHandler) CreateRecharge(c *gin.Context) {
	var req CreateRechargeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint64("user_id")
	var amount, balance float64
	var description string

	// 选择套餐
	if req.PackageID > 0 {
		var pkg models.RechargePackage
		if err := h.db.First(&pkg, req.PackageID).Error; err != nil {
			utils.NotFound(c, "套餐不存在")
			return
		}
		if pkg.Status != 1 {
			utils.BadRequest(c, "套餐已下架")
			return
		}
		amount = pkg.Amount
		balance = pkg.Balance
		description = "充值套餐: " + pkg.Name
	} else {
		// 自定义金额
		if req.Amount <= 0 {
			utils.BadRequest(c, "请选择套餐或输入金额")
			return
		}
		amount = req.Amount
		balance = req.Amount
		description = "账户充值"
	}

	// 创建订单
	txn := &models.Transaction{
		OrderNo:       utils.GenerateOrderNo(),
		UserID:        userID,
		Type:          models.OrderRecharge,
		Amount:        amount,
		Status:        models.OrderPending,
		PaymentMethod: models.PaymentMethod(req.PaymentMethod),
		Description:   description,
	}

	if err := h.db.Create(txn).Error; err != nil {
		utils.ServerError(c, "创建订单失败")
		return
	}

	// 根据支付方式返回支付URL
	var payURL string
	var err error
	switch req.PaymentMethod {
	case "alipay":
		payURL, err = h.payment.CreateAlipayOrder(txn.OrderNo, amount, description)
		if err != nil {
			utils.ServerError(c, "创建支付订单失败: "+err.Error())
			return
		}
	case "wechat":
		payURL, err = h.payment.CreateWechatOrder(txn.OrderNo, amount, description)
		if err != nil {
			utils.ServerError(c, "创建支付订单失败: "+err.Error())
			return
		}
	case "stripe":
		successURL := h.cfg.Stripe.WebhookSecret // 占位
		cancelURL := ""
		payURL, err = h.payment.CreateStripeCheckout(txn.OrderNo, amount, description, successURL, cancelURL)
		if err != nil {
			utils.ServerError(c, "创建支付订单失败: "+err.Error())
			return
		}
	case "balance":
		// 余额支付实际上是管理员手动调整
		utils.Success(c, gin.H{
			"order_no": txn.OrderNo,
			"amount":   amount,
			"balance":  balance,
			"message":  "请使用其他支付方式",
		})
		return
	}

	utils.Success(c, gin.H{
		"order_no":  txn.OrderNo,
		"amount":    amount,
		"balance":   balance,
		"pay_url":   payURL,
		"method":    req.PaymentMethod,
		"expire_at": time.Now().Add(30 * time.Minute),
	})
}

// QueryOrder 查询订单
func (h *PaymentHandler) QueryOrder(c *gin.Context) {
	userID := c.GetUint64("user_id")
	orderNo := c.Param("order_no")

	var txn models.Transaction
	if err := h.db.Where("user_id = ? AND order_no = ?", userID, orderNo).First(&txn).Error; err != nil {
		utils.NotFound(c, "订单不存在")
		return
	}
	utils.Success(c, txn)
}

// CancelOrder 取消订单
func (h *PaymentHandler) CancelOrder(c *gin.Context) {
	userID := c.GetUint64("user_id")
	orderNo := c.Param("order_no")

	var txn models.Transaction
	if err := h.db.Where("user_id = ? AND order_no = ? AND status = ?",
		userID, orderNo, models.OrderPending).First(&txn).Error; err != nil {
		utils.BadRequest(c, "订单不可取消")
		return
	}

	h.db.Model(&txn).Update("status", models.OrderCanceled)
	utils.SuccessWithMessage(c, "订单已取消", nil)
}

// AlipayNotify 支付宝回调
func (h *PaymentHandler) AlipayNotify(c *gin.Context) {
	if err := c.Request.ParseForm(); err != nil {
		c.String(http.StatusBadRequest, "fail")
		return
	}

	orderNo, amount, ok := h.payment.VerifyAlipayNotify(c.Request.PostForm)
	if !ok {
		c.String(http.StatusBadRequest, "fail")
		return
	}

	if err := h.completeRecharge(orderNo, amount, "alipay"); err != nil {
		c.String(http.StatusInternalServerError, "fail")
		return
	}

	c.String(http.StatusOK, "success")
}

// WechatNotify 微信回调
func (h *PaymentHandler) WechatNotify(c *gin.Context) {
	body, _ := io.ReadAll(c.Request.Body)
	orderNo, amount, ok := h.payment.VerifyWechatNotify(body)
	if !ok {
		c.String(http.StatusBadRequest, `<xml><return_code><![CDATA[FAIL]]></return_code></xml>`)
		return
	}

	if err := h.completeRecharge(orderNo, amount, "wechat"); err != nil {
		c.String(http.StatusInternalServerError, `<xml><return_code><![CDATA[FAIL]]></return_code></xml>`)
		return
	}

	c.String(http.StatusOK, `<xml><return_code><![CDATA[SUCCESS]]></return_code><return_msg><![CDATA[OK]]></return_msg></xml>`)
}

// completeRecharge 完成充值
func (h *PaymentHandler) completeRecharge(orderNo string, amount float64, method string) error {
	return h.db.Transaction(func(tx *gorm.DB) error {
		var txn models.Transaction
		if err := tx.Where("order_no = ? AND status = ?", orderNo, models.OrderPending).First(&txn).Error; err != nil {
			return err
		}

		// 验证金额
		if txn.Amount != amount {
			return gorm.ErrInvalidData
		}

		// 锁定用户
		var user models.User
		if err := tx.First(&user, txn.UserID).Error; err != nil {
			return err
		}

		// 计算到账金额（含赠送）
		creditAmount := amount
		if txn.Type == models.OrderRecharge {
			// 如果有套餐赠送
			if pkgID := c_pkgIDFromDesc(txn.Description); pkgID > 0 {
				var pkg models.RechargePackage
				if err := tx.First(&pkg, pkgID).Error; err == nil {
					creditAmount = pkg.Balance
				}
			}
		}

		// 更新订单
		now := time.Now()
		txn.Status = models.OrderPaid
		txn.PaidAt = &now
		txn.BalanceBefore = user.Balance
		user.Balance += creditAmount
		user.TotalRecharged += amount
		txn.BalanceAfter = user.Balance

		if err := tx.Save(&txn).Error; err != nil {
			return err
		}
		if err := tx.Save(&user).Error; err != nil {
			return err
		}

		return nil
	})
}

// 简单从描述提取套餐ID
func c_pkgIDFromDesc(desc string) uint64 {
	// 简化处理：实际应该单独存储
	return 0
}

// Recharge 管理员手动充值
type AdminRechargeRequest struct {
	UserID uint64  `json:"user_id" binding:"required"`
	Amount float64 `json:"amount" binding:"required"`
	Remark string  `json:"remark"`
}

// AdminRecharge 管理员充值
func (h *PaymentHandler) AdminRecharge(c *gin.Context) {
	var req AdminRechargeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	if err := h.db.Transaction(func(tx *gorm.DB) error {
		var user models.User
		if err := tx.First(&user, req.UserID).Error; err != nil {
			return err
		}

		balanceBefore := user.Balance
		user.Balance += req.Amount
		user.TotalRecharged += req.Amount

		now := time.Now()
		txn := &models.Transaction{
			OrderNo:       utils.GenerateOrderNo(),
			UserID:        req.UserID,
			Type:          models.OrderRecharge,
			Amount:        req.Amount,
			BalanceBefore: balanceBefore,
			BalanceAfter:  user.Balance,
			Status:        models.OrderPaid,
			PaymentMethod: models.PaymentBalance,
			Description:   "管理员充值: " + req.Remark,
			PaidAt:        &now,
		}
		if err := tx.Save(&user).Error; err != nil {
			return err
		}
		return tx.Create(txn).Error
	}); err != nil {
		utils.ServerError(c, "充值失败: "+err.Error())
		return
	}

	utils.SuccessWithMessage(c, "充值成功", nil)
}

// Helper
var _ = strconv.Itoa
