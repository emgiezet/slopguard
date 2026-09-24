<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpMaint003;

/**
 * Return types present — no PHPStan missingType.return.
 * ok: phpstan.missingType.return
 */
function processData(string $input): string
{
    return strtoupper($input);
}

final class Processor
{
    /**
     * @param list<string> $items
     */
    public function format(array $items): string
    {
        // ok: phpstan.missingType.return
        return implode(', ', $items);
    }
}
