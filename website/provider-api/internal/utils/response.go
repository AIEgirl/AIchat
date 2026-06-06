package utils

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

const (
	CodeSuccess     = 0
	CodeBadRequest  = 40000
	CodeUnauthorized = 40100
	CodeForbidden   = 40300
	CodeNotFound    = 40400
	CodeServerError = 50000
)

type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

type PageData struct {
	List     interface{} `json:"list"`
	Total    int64       `json:"total"`
	Page     int         `json:"page"`
	PageSize int         `json:"page_size"`
}

func OK(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Response{Code: CodeSuccess, Message: "success", Data: data})
}

func OKPage(c *gin.Context, list interface{}, total int64, page, size int) {
	c.JSON(http.StatusOK, Response{Code: CodeSuccess, Message: "success", Data: PageData{
		List: list, Total: total, Page: page, PageSize: size,
	}})
}

func Fail(c *gin.Context, code int, msg string) {
	c.JSON(http.StatusOK, Response{Code: code, Message: msg})
}

func BadRequest(c *gin.Context, msg string)   { Fail(c, CodeBadRequest, msg) }
func Unauthorized(c *gin.Context, msg string)  { c.JSON(http.StatusUnauthorized, Response{Code: CodeUnauthorized, Message: msg}) }
func Forbidden(c *gin.Context, msg string)     { c.JSON(http.StatusForbidden, Response{Code: CodeForbidden, Message: msg}) }
func NotFound(c *gin.Context, msg string)      { c.JSON(http.StatusNotFound, Response{Code: CodeNotFound, Message: msg}) }
func ServerError(c *gin.Context, msg string)   { Fail(c, CodeServerError, msg) }
