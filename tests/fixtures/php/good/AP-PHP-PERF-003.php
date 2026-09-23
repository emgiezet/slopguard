<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpPerf003;

// Minimal stubs — no framework required.

class Controller {}

final class Order
{
    /**
     * @param list<int> $ids
     * @return list<Order>
     */
    public static function whereIn(string $column, array $ids): array { return []; }

    public function process(): void {}
}

final class User
{
    /**
     * @param list<int> $ids
     * @return list<User>
     */
    public static function whereIn(string $column, array $ids): array { return []; }

    /** @return array<string, mixed> */
    public function toArray(): array { return []; }
}

class OrderController extends Controller
{
    /** @param list<int> $orderIds */
    public function processOrders(array $orderIds): void
    {
        // ok: slopguard.php.laravel.query-in-loop
        // Fetch all orders in a single query; iterate the in-memory result.
        $orders = Order::whereIn('id', $orderIds);
        foreach ($orders as $order) {
            $order->process();
        }
    }

    /**
     * @param list<int> $userIds
     * @return list<array<string, mixed>>
     */
    public function showUsers(array $userIds): array
    {
        // ok: slopguard.php.laravel.query-in-loop
        $users = User::whereIn('id', $userIds);
        $result = [];
        foreach ($users as $user) {
            $result[] = $user->toArray();
        }
        return $result;
    }
}
