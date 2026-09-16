import React from 'react';

interface GreetProps {
  name: string;
}

export function Greet({ name }: GreetProps): React.JSX.Element {
  return <span>Hello, {name}</span>;
}
