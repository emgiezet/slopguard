// ok: slopguard.react.token-in-localstorage
// Tokens are stored in HttpOnly cookies managed by the server.
// The client never handles raw token values in JavaScript.

// Non-sensitive UI preferences in localStorage are fine:
function storePreferences(theme: string, language: string) {
  localStorage.setItem('theme', theme);
  localStorage.setItem('language', language);
}
