import React from 'react';

interface Props { url: string; imageSrc: string; }

// ruleid: slopguard.react.href-js-scheme
function UserLink({ url, imageSrc }: Props) {
  return (
    <div>
      <a href={url}>Profile</a>
      <img src={imageSrc} alt="avatar" />
    </div>
  );
}

// ruleid: slopguard.react.href-js-scheme
function navigateUser(userUrl: string) {
  window.location.href = userUrl;
}

export default UserLink;
