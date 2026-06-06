package services

import (
	"crypto/tls"
	"fmt"
	"net/smtp"
	"strings"

	"github.com/aichat/relay/internal/config"
)

// EmailService 邮件服务
type EmailService struct {
	cfg *config.SMTPConfig
}

// NewEmailService 创建邮件服务
func NewEmailService(cfg *config.SMTPConfig) *EmailService {
	return &EmailService{cfg: cfg}
}

// Send 发送邮件
func (s *EmailService) Send(to, subject, body string) error {
	if !s.cfg.Enabled {
		// 未启用SMTP时仅打印日志
		fmt.Printf("[Email] To: %s, Subject: %s\n%s\n", to, subject, body)
		return nil
	}

	from := s.cfg.From
	if from == "" {
		from = s.cfg.Username
	}

	// 解析From地址
	fromAddr := from
	if idx := strings.Index(from, "<"); idx >= 0 {
		fromAddr = strings.Trim(from[idx+1:], ">")
	}

	auth := smtp.PlainAuth("", s.cfg.Username, s.cfg.Password, s.cfg.Host)

	// 构建邮件
	msg := []byte(fmt.Sprintf(
		"From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n%s\r\n",
		from, to, subject, body,
	))

	addr := fmt.Sprintf("%s:%d", s.cfg.Host, s.cfg.Port)

	// 587端口使用STARTTLS
	if s.cfg.Port == 587 {
		return s.sendWithStartTLS(addr, fromAddr, []string{to}, msg, auth)
	}

	// 465端口使用SSL
	if s.cfg.Port == 465 {
		return s.sendWithSSL(addr, fromAddr, []string{to}, msg, auth)
	}

	return smtp.SendMail(addr, auth, fromAddr, []string{to}, msg)
}

func (s *EmailService) sendWithStartTLS(addr, from string, to []string, msg []byte, auth smtp.Auth) error {
	conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: strings.Split(addr, ":")[0]})
	if err != nil {
		// 退回到普通SMTP
		return smtp.SendMail(addr, auth, from, to, msg)
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, strings.Split(addr, ":")[0])
	if err != nil {
		return err
	}
	defer client.Close()

	if err := client.Auth(auth); err != nil {
		return err
	}
	if err := client.Mail(from); err != nil {
		return err
	}
	for _, rcpt := range to {
		if err := client.Rcpt(rcpt); err != nil {
			return err
		}
	}
	w, err := client.Data()
	if err != nil {
		return err
	}
	defer w.Close()
	_, err = w.Write(msg)
	return err
}

func (s *EmailService) sendWithSSL(addr, from string, to []string, msg []byte, auth smtp.Auth) error {
	conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: strings.Split(addr, ":")[0]})
	if err != nil {
		return err
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, strings.Split(addr, ":")[0])
	if err != nil {
		return err
	}
	defer client.Close()

	if err := client.Auth(auth); err != nil {
		return err
	}
	if err := client.Mail(from); err != nil {
		return err
	}
	for _, rcpt := range to {
		if err := client.Rcpt(rcpt); err != nil {
			return err
		}
	}
	w, err := client.Data()
	if err != nil {
		return err
	}
	defer w.Close()
	_, err = w.Write(msg)
	return err
}

// SendVerificationCode 发送验证码邮件
func (s *EmailService) SendVerificationCode(to, code, purpose string) error {
	var subject, body string
	switch purpose {
	case "register":
		subject = "【AI中转平台】注册验证码"
		body = fmt.Sprintf(`
			<div style="max-width:600px;margin:0 auto;padding:20px;font-family:Arial,sans-serif">
				<h2 style="color:#333">欢迎注册AI中转平台</h2>
				<p>您的注册验证码为：</p>
				<div style="background:#f5f5f5;padding:20px;text-align:center;font-size:32px;font-weight:bold;letter-spacing:8px;color:#1890ff">%s</div>
				<p style="color:#999;margin-top:20px">验证码10分钟内有效，请尽快完成验证。</p>
				<p style="color:#999">如果不是您本人操作，请忽略此邮件。</p>
			</div>`, code)
	case "reset":
		subject = "【AI中转平台】密码重置验证码"
		body = fmt.Sprintf(`
			<div style="max-width:600px;margin:0 auto;padding:20px;font-family:Arial,sans-serif">
				<h2 style="color:#333">密码重置</h2>
				<p>您正在重置密码，验证码为：</p>
				<div style="background:#f5f5f5;padding:20px;text-align:center;font-size:32px;font-weight:bold;letter-spacing:8px;color:#1890ff">%s</div>
				<p style="color:#999;margin-top:20px">验证码10分钟内有效，请尽快完成验证。</p>
			</div>`, code)
	case "login":
		subject = "【AI中转平台】登录验证码"
		body = fmt.Sprintf(`
			<div style="max-width:600px;margin:0 auto;padding:20px;font-family:Arial,sans-serif">
				<h2 style="color:#333">登录验证</h2>
				<p>您的登录验证码为：</p>
				<div style="background:#f5f5f5;padding:20px;text-align:center;font-size:32px;font-weight:bold;letter-spacing:8px;color:#1890ff">%s</div>
				<p style="color:#999;margin-top:20px">验证码10分钟内有效。</p>
			</div>`, code)
	default:
		subject = "【AI中转平台】通知"
		body = code
	}
	return s.Send(to, subject, body)
}
