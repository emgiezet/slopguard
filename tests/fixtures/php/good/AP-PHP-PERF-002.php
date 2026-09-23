<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpPerf002;

// Minimal stubs — no framework required.

class Controller {}

final class Paginator {}

final class Product
{
    public static function paginate(int $perPage = 15): Paginator { return new Paginator(); }
}

final class UserQueryBuilder
{
    public function chunkById(int $size, \Closure $callback): bool { return true; }
}

final class User
{
    public static function query(): UserQueryBuilder { return new UserQueryBuilder(); }
}

/** @param array<string, mixed> $data */
function view(string $view, array $data = []): string { return ''; }

class ProductController extends Controller
{
    public function index(): string
    {
        // ok: slopguard.php.laravel.unbounded-all
        $products = Product::paginate(25);
        return view('products.index', ['products' => $products]);
    }

    public function export(): bool
    {
        // ok: slopguard.php.laravel.unbounded-all
        return User::query()->chunkById(500, function (array $users): void {
            foreach ($users as $user) {
                // process user
            }
        });
    }
}
