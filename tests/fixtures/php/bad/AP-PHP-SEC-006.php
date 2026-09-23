<?php

class AuthService
{
    public function hashPassword(string $password): string
    {
        // ruleid: slopguard.php.weak-password-hash
        return md5($password);
    }

    public function generateToken(): string
    {
        // ruleid: slopguard.php.insecure-random-token
        return uniqid('tok_', true);
    }

    public function generateCode(): int
    {
        // ruleid: slopguard.php.insecure-random-token
        return rand(100000, 999999);
    }

    public function legacyHash(string $password): string
    {
        // ruleid: slopguard.php.weak-password-hash
        return sha1($password);
    }
}
