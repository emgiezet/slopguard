// ruleid: slopguard.react.token-in-localstorage
function storeAuth(token: string, refreshToken: string) {
  localStorage.setItem('token', token);
  localStorage.setItem('refresh_token', refreshToken);
}

// ruleid: slopguard.react.token-in-localstorage
function loginUser(response: { jwt: string; accessToken: string }) {
  localStorage.setItem('jwt', response.jwt);
  localStorage.setItem('access_token', response.accessToken);
}
