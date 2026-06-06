package services

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/aichat/relay/internal/config"
)

// PaymentService 支付服务
type PaymentService struct {
	cfg *config.PaymentConfig
}

// NewPaymentService 创建支付服务
func NewPaymentService(cfg *config.PaymentConfig) *PaymentService {
	return &PaymentService{cfg: cfg}
}

// CreateAlipayOrder 创建支付宝订单
func (p *PaymentService) CreateAlipayOrder(orderNo string, amount float64, subject string) (string, error) {
	if !p.cfg.Alipay.Enabled {
		return "", fmt.Errorf("支付宝未启用")
	}

	// 构造支付宝参数
	params := url.Values{}
	params.Set("app_id", p.cfg.Alipay.AppID)
	params.Set("method", "alipay.trade.page.pay")
	params.Set("charset", "utf-8")
	params.Set("sign_type", "RSA2")
	params.Set("timestamp", time.Now().Format("2006-01-02 15:04:05"))
	params.Set("version", "1.0")
	params.Set("notify_url", p.cfg.Alipay.NotifyURL)
	params.Set("biz_content", fmt.Sprintf(
		`{"out_trade_no":"%s","total_amount":"%.2f","subject":"%s","product_code":"FAST_INSTANT_TRADE_PAY"}`,
		orderNo, amount, subject,
	))

	// 生成签名
	sign := p.signAlipay(params)
	params.Set("sign", sign)

	return p.cfg.Alipay.Gateway + "?" + params.Encode(), nil
}

func (p *PaymentService) signAlipay(params url.Values) string {
	// 排序参数
	keys := make([]string, 0, len(params))
	for k := range params {
		if k != "sign" {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)

	var parts []string
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf(`%s=%s`, k, params.Get(k)))
	}
	content := strings.Join(parts, "&")

	// 实际RSA2签名应使用支付宝SDK，这里使用简化版本
	// 生产环境请使用 github.com/smartwalle/alipay 等库
	mac := hmac.New(sha256.New, []byte(p.cfg.Alipay.PrivateKey))
	mac.Write([]byte(content))
	return hex.EncodeToString(mac.Sum(nil))
}

// VerifyAlipayNotify 验证支付宝回调
func (p *PaymentService) VerifyAlipayNotify(params url.Values) (string, float64, bool) {
	if !p.cfg.Alipay.Enabled {
		return "", 0, false
	}
	sign := params.Get("sign")
	if sign == "" {
		return "", 0, false
	}

	// 验证签名
	keys := make([]string, 0, len(params))
	for k := range params {
		if k != "sign" && k != "sign_type" {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)

	var parts []string
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf(`%s=%s`, k, params.Get(k)))
	}
	content := strings.Join(parts, "&")

	mac := hmac.New(sha256.New, []byte(p.cfg.Alipay.PublicKey))
	mac.Write([]byte(content))
	expected := hex.EncodeToString(mac.Sum(nil))

	if expected != sign {
		return "", 0, false
	}

	return params.Get("out_trade_no"), parseFloat(params.Get("total_amount")), true
}

// CreateWechatOrder 创建微信订单
func (p *PaymentService) CreateWechatOrder(orderNo string, amount float64, subject string) (string, error) {
	if !p.cfg.Wechat.Enabled {
		return "", fmt.Errorf("微信支付未启用")
	}
	// 实际生产环境需要调用微信统一下单API
	// https://api.mch.weixin.qq.com/pay/unifiedorder
	// 这里返回模拟URL
	return fmt.Sprintf("weixin://wxpay/bizpayurl?pr=mock_%s", orderNo), nil
}

// VerifyWechatNotify 验证微信回调
func (p *PaymentService) VerifyWechatNotify(data []byte) (string, float64, bool) {
	if !p.cfg.Wechat.Enabled {
		return "", 0, false
	}
	var result struct {
		OutTradeNo string `xml:"out_trade_no"`
		TotalFee   int    `xml:"total_fee"`
		ResultCode string `xml:"result_code"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return "", 0, false
	}
	if result.ResultCode != "SUCCESS" {
		return "", 0, false
	}
	return result.OutTradeNo, float64(result.TotalFee) / 100, true
}

// CreateStripeCheckout 创建Stripe Checkout Session
func (p *PaymentService) CreateStripeCheckout(orderNo string, amount float64, subject, successURL, cancelURL string) (string, error) {
	if !p.cfg.Stripe.Enabled {
		return "", fmt.Errorf("Stripe未启用")
	}

	form := url.Values{}
	form.Set("payment_method_types[]", "card")
	form.Set("line_items[0][price_data][currency]", "usd")
	form.Set("line_items[0][price_data][product_data][name]", subject)
	form.Set("line_items[0][price_data][unit_amount]", fmt.Sprintf("%d", int(amount*100)))
	form.Set("line_items[0][quantity]", "1")
	form.Set("mode", "payment")
	form.Set("success_url", successURL)
	form.Set("cancel_url", cancelURL)
	form.Set("metadata[order_no]", orderNo)

	req, _ := http.NewRequestWithContext(context.Background(), "POST",
		"https://api.stripe.com/v1/checkout/sessions", strings.NewReader(form.Encode()))
	req.Header.Set("Authorization", "Bearer "+p.cfg.Stripe.SecretKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var session struct {
		URL string `json:"url"`
	}
	if err := json.Unmarshal(body, &session); err != nil {
		return "", err
	}
	return session.URL, nil
}

func parseFloat(s string) float64 {
	var f float64
	fmt.Sscanf(s, "%f", &f)
	return f
}

// HttpJSON JSON HTTP辅助
func HttpJSON(method, url string, headers map[string]string, body interface{}) ([]byte, int, error) {
	var bodyReader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, 0, err
		}
		bodyReader = bytes.NewReader(data)
	}

	req, err := http.NewRequestWithContext(context.Background(), method, url, bodyReader)
	if err != nil {
		return nil, 0, err
	}

	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	return respBody, resp.StatusCode, nil
}
