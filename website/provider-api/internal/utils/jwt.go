package utils

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var secret []byte

type Claims struct {
	AdminID  uint64 `json:"admin_id"`
	Username string `json:"username"`
	Role     string `json:"role"`
	jwt.RegisteredClaims
}

func InitJWT(s string) { secret = []byte(s) }

func GenerateToken(adminID uint64, username, role string, expireHours int) (string, error) {
	c := Claims{
		AdminID: adminID, Username: username, Role: role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Duration(expireHours) * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "providerhub",
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(secret)
}

func ParseToken(t string) (*Claims, error) {
	if len(secret) == 0 {
		return nil, errors.New("jwt not initialized")
	}
	tok, err := jwt.ParseWithClaims(t, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		return secret, nil
	})
	if err != nil {
		return nil, err
	}
	if c, ok := tok.Claims.(*Claims); ok && tok.Valid {
		return c, nil
	}
	return nil, errors.New("invalid token")
}
