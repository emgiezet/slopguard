<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpPerf002;

// Minimal stubs — no framework required.

class Controller {}

final class Collection
{
    public function toJson(int $options = 0): string { return ''; }
}

final class Product
{
    public static function all(): Collection { return new Collection(); }
}

final class User
{
    public static function all(): Collection { return new Collection(); }
}

/** @param array<string, mixed> $data */
function view(string $view, array $data = []): string { return ''; }

class ProductController extends Controller
{
    public function index(): string
    {
        // ruleid: slopguard.php.laravel.unbounded-all
        $products = Product::all();
        return view('products.index', ['products' => $products]);
    }

    public function export(): string
    {
        // ruleid: slopguard.php.laravel.unbounded-all
        $users = User::all();
        return $users->toJson();
    }
}
