<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpPerf003;

// Minimal stubs — no framework required.

class Controller {}

final class Order
{
    public static function find(int $id): self { return new self(); }
    public function process(): void {}
}

final class UserBuilder
{
    public function first(): User { return new User(); }
}

final class User
{
    public static function where(string $column, mixed $value): UserBuilder { return new UserBuilder(); }

    /** @return array<string, mixed> */
    public function toArray(): array { return []; }
}

class OrderController extends Controller
{
    /** @param list<int> $orderIds */
    public function processOrders(array $orderIds): void
    {
        foreach ($orderIds as $id) {
            // ruleid: slopguard.php.laravel.query-in-loop
            $order = Order::find($id);
            $order->process();
        }
    }

    /**
     * @param list<int> $userIds
     * @return list<array<string, mixed>>
     */
    public function showUsers(array $userIds): array
    {
        $results = [];
        foreach ($userIds as $userId) {
            // ruleid: slopguard.php.laravel.query-in-loop
            $user = User::where('id', $userId)->first();
            $results[] = $user->toArray();
        }
        return $results;
    }
}
