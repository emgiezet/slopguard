<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpSec005;

// Minimal stubs — no framework required.

class Controller {}

final class Request
{
    /** @return array<string, mixed> */
    public function all(): array { return []; }

    /** @return array<string, mixed> */
    public function input(): array { return []; }
}

final class JsonResponse
{
    public function __construct(mixed $data) {}
}

final class ResponseFactory
{
    public function json(mixed $data): JsonResponse { return new JsonResponse($data); }
}

function response(): ResponseFactory { return new ResponseFactory(); }

class User
{
    /** @param array<string, mixed> $attributes */
    public static function create(array $attributes = []): static { return new static(); }

    /** @param array<string, mixed> $attributes */
    public function fill(array $attributes): static { return $this; }
}

class UserController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        // ruleid: slopguard.php.laravel.mass-assignment-request-all
        $user = User::create($request->all());

        // ruleid: slopguard.php.laravel.mass-assignment-request-all
        $user->fill($request->all());

        return response()->json($user);
    }
}
