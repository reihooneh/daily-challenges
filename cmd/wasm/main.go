//go:build js && wasm

// Command wasm exposes the planner to the browser. It registers one global
// function, pickTwoSolve(text), which returns the answer as a JSON string.
// Text in, text out: no JavaScript objects cross the boundary.
package main

import (
	"encoding/json"
	"syscall/js"

	"github.com/reihooneh/pick-two/internal/planner"
)

func solve(_ js.Value, args []js.Value) (result any) {
	defer func() {
		if recover() != nil {
			result = `{"status":"error","error":"internal error","complete":true,"nodes":0}`
		}
	}()
	if len(args) != 1 || args[0].Type() != js.TypeString {
		return `{"status":"error","error":"expected one text argument","complete":true,"nodes":0}`
	}
	encoded, err := json.Marshal(planner.Run(args[0].String())) // Run enforces the size limit itself
	if err != nil {
		return `{"status":"error","error":"internal error","complete":true,"nodes":0}`
	}
	return string(encoded)
}

func main() {
	js.Global().Set("pickTwoSolve", js.FuncOf(solve))
	select {} // keep the program alive so the function stays callable
}
