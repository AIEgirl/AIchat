package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/aichat/relay/internal/models"
)

// AIProxyService AI代理服务
type AIProxyService struct {
	client *http.Client
}

// NewAIProxyService 创建AI代理服务
func NewAIProxyService() *AIProxyService {
	return &AIProxyService{
		client: &http.Client{
			Timeout: 60 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 20,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}
}

// CallResult 调用结果
type CallResult struct {
	StatusCode   int
	Response     []byte
	Headers      http.Header
	InputTokens  int
	OutputTokens int
	Duration     time.Duration
	Error        error
}

// Call 调用AI服务
func (s *AIProxyService) Call(ctx context.Context, service *models.AIService, requestBody []byte, authToken string) *CallResult {
	start := time.Now()
	result := &CallResult{}

	// 构造请求
	req, err := http.NewRequestWithContext(ctx, service.Method, service.Endpoint, bytes.NewReader(requestBody))
	if err != nil {
		result.Error = err
		return result
	}

	// 设置请求头
	req.Header.Set("Content-Type", "application/json")
	for k, v := range service.Headers {
		req.Header.Set(k, fmt.Sprintf("%v", v))
	}

	// 如果没有设置Authorization，使用传入的token
	if req.Header.Get("Authorization") == "" && authToken != "" {
		req.Header.Set("Authorization", authToken)
	}

	// 发起请求
	resp, err := s.client.Do(req)
	if err != nil {
		result.Error = err
		result.Duration = time.Since(start)
		return result
	}
	defer resp.Body.Close()

	result.StatusCode = resp.StatusCode
	result.Headers = resp.Header

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		result.Error = err
		result.Duration = time.Since(start)
		return result
	}
	result.Response = body
	result.Duration = time.Since(start)

	// 尝试提取token使用量
	result.InputTokens, result.OutputTokens = extractTokenUsage(service, body)

	return result
}

// extractTokenUsage 提取token使用量
func extractTokenUsage(service *models.AIService, body []byte) (int, int) {
	if !strings.Contains(service.Provider, "openai") &&
		!strings.Contains(service.Provider, "anthropic") {
		return 0, 0
	}

	var data struct {
		Usage struct {
			PromptTokens     int `json:"prompt_tokens"`
			CompletionTokens int `json:"completion_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(body, &data); err != nil {
		return 0, 0
	}
	return data.Usage.PromptTokens, data.Usage.CompletionTokens
}

// ValidateRequest 验证请求
func (s *AIProxyService) ValidateRequest(service *models.AIService, body []byte) error {
	// 检查必填字段
	if service.RequestSchema == nil {
		return nil
	}

	var reqData map[string]interface{}
	if err := json.Unmarshal(body, &reqData); err != nil {
		return fmt.Errorf("请求体不是有效的JSON: %w", err)
	}

	for field, rule := range service.RequestSchema {
		if fieldMap, ok := rule.(map[string]interface{}); ok {
			if required, _ := fieldMap["required"].(bool); required {
				if _, exists := reqData[field]; !exists {
					return fmt.Errorf("缺少必填字段: %s", field)
				}
			}
		}
	}

	return nil
}
