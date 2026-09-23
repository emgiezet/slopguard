<?php
// ok: slopguard.php.laravel.blade-unescaped-output
// In Blade templates, use {{ $var }} for all user-supplied values.
// The double-brace syntax auto-escapes HTML entities, preventing XSS.
// Reserve {!! ... !!} only for pre-sanitized, verified-safe HTML — never
// pass raw user input through unescaped output.
?>
<div>{{ $userBio }}</div>
<h1>{{ $title }}</h1>
<p>{{ $description }}</p>
