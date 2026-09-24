// Bad: eval with user input – triggers no-eval (AP-TS-SEC-002)
export function runCode(userInput: string): unknown {
  return eval(userInput);
}
