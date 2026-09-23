// Bad: eval with user input (AP-TS-SEC-002 / no-eval)
export function runCode(userInput: string): unknown {
  return eval(userInput);  // eslint-disable-line no-eval
}
