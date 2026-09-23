<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpSec001;

// Minimal stubs — no framework required.

final class Builder
{
    public function where(string $column, mixed $value): self { return $this; }

    /** @param list<mixed> $bindings */
    public function whereRaw(string $sql, array $bindings = []): self { return $this; }

    /** @return list<object> */
    public function get(): array { return []; }
}

final class DB
{
    /** @param list<mixed> $bindings */
    public static function select(string $query, array $bindings = []): array { return []; }

    public static function raw(string $value): string { return $value; }
}

final class User
{
    public static function where(string $column, string $value): Builder { return new Builder(); }

    /** @param list<mixed> $bindings */
    public static function whereRaw(string $sql, array $bindings = []): Builder { return new Builder(); }
}

function runUnsafeQueries(string $email, string $status, string $date): void
{
    // ruleid: slopguard.php.laravel.raw-sql-interpolation
    $results = DB::select("SELECT * FROM users WHERE email = '" . $email . "'");

    // ruleid: slopguard.php.laravel.raw-sql-interpolation
    $users = User::whereRaw("status = '" . $status . "' AND role = 'user'")
        ->get();

    // ruleid: slopguard.php.laravel.raw-sql-interpolation
    $query = DB::raw("created_at > '" . $date . "'");
}
