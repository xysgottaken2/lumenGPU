//go:build !windows

package main
import "os/exec"
func hideDracoWindow(c *exec.Cmd){}
