<?php
declare(strict_types=1);

// Minimal stubs in Illuminate namespaces — no framework required.

namespace Illuminate\Database\Migrations {
    abstract class Migration
    {
        abstract public function up(): void;
        abstract public function down(): void;
    }
}

namespace Illuminate\Database\Schema {
    class Blueprint
    {
        public function foreignId(string $column): static { return $this; }
        public function constrained(string $table = '', string $column = ''): static { return $this; }
        public function dropConstrainedForeignId(string $column): void {}
        public function unsignedBigInteger(string $column): static { return $this; }
        public function foreign(string $column): static { return $this; }
        public function references(string $column): static { return $this; }
        public function on(string $table): static { return $this; }
        /** @param string|list<string> $columns */
        public function index(string|array $columns): static { return $this; }
        /** @param string|list<string> $index */
        public function dropForeign(string|array $index): void {}
        public function dropColumn(string $column): void {}
    }
}

namespace Illuminate\Support\Facades {
    class Schema
    {
        public static function table(string $table, \Closure $callback): void {}
        public static function create(string $table, \Closure $callback): void {}
    }
}

namespace {
    use Illuminate\Database\Migrations\Migration;
    use Illuminate\Database\Schema\Blueprint;
    use Illuminate\Support\Facades\Schema;

    return new class extends Migration
    {
        #[\Override]
        public function up(): void
        {
            // ruleid: slopguard.laravel.migration-fk-without-index
            Schema::table('orders', function (Blueprint $table): void {
                $table->unsignedBigInteger('user_id');
                $table->foreign('user_id')->references('id')->on('users');
                // Missing: $table->index(['user_id']);
            });
        }

        #[\Override]
        public function down(): void
        {
            Schema::table('orders', function (Blueprint $table): void {
                $table->dropForeign(['user_id']);
                $table->dropColumn('user_id');
            });
        }
    };
}
