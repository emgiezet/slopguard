<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpSec005;

// Minimal stubs — no framework required.

class Controller {}

final class Request
{
    /** @return array<string, mixed> */
    public function validated(): array { return []; }

    /**
     * @param list<string> $keys
     * @return array<string, mixed>
     */
    public function only(array $keys): array { return []; }
}

final class JsonResponse
{
    public function __construct(private mixed $data) {}

    public function payload(): mixed { return $this->data; }
}

final class ResponseFactory
{
    public function json(mixed $data): JsonResponse { return new JsonResponse($data); }
}

function response(): ResponseFactory { return new ResponseFactory(); }

final class User
{
    /** @var list<string> */
    protected array $fillable = ['name', 'email', 'role'];

    /** @param array<string, mixed> $attributes */
    public static function create(array $attributes = []): static { return new static(); }

    /** @param array<string, mixed> $attributes */
    public function fill(array $attributes): static { return $this; }
}

class UserController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        // ok: slopguard.php.laravel.mass-assignment-request-all
        $validated = $request->validated();
        $user = User::create($validated);

        // ok: slopguard.php.laravel.mass-assignment-request-all
        $user = $user->fill($request->only(['name', 'email']));

        return response()->json($user);
    }
}
