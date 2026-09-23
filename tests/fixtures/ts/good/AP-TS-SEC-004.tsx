import React from 'react';

const ALLOWED_SCHEMES = new Set(['https:', 'http:', 'mailto:']);

function sanitizeUrl(url: string): string {
  try {
    const parsed = new URL(url);
    if (!ALLOWED_SCHEMES.has(parsed.protocol)) {
      return '#';
    }
    return url;
  } catch {
    return '#';
  }
}

interface Props { url: string; imageSrc: string; }

// ok: slopguard.react.href-js-scheme
function UserLink({ url, imageSrc }: Props) {
  const safeUrl = sanitizeUrl(url);
  const safeImg = sanitizeUrl(imageSrc);
  return (
    <div>
      <a href={safeUrl}>Profile</a>
      <img src={safeImg} alt="avatar" />
    </div>
  );
}

export default UserLink;
