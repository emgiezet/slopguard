<?php
declare(strict_types=1);

namespace SlopGuard\Fixture\PhpMaint003;

/**
 * Return type missing — PHPStan missingType.return → AP-PHP-MAINT-003.
 * Both the function and the method lack a return-type declaration; phpstan
 * reports missingType.return for each at level 8 and above (including max,
 * which the dispatcher applies to untracked files).
 */
function processData(string $input)
{
    return strtoupper($input);
}

final class Processor
{
    /**
     * @param list<string> $items
     */
    public function format(array $items)
    {
        return implode(', ', $items);
    }
}
