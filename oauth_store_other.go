//go:build !windows

package main
import "fmt"
func protectOAuth([]byte)([]byte,error){return nil,fmt.Errorf("Windows DPAPI unavailable")}
func unprotectOAuth([]byte)([]byte,error){return nil,fmt.Errorf("Windows DPAPI unavailable")}
