#!/usr/bin/env php
<?php

declare(strict_types=1);

if (PHP_VERSION_ID < 80400) {
    $php = trim((string) shell_exec('command -v php8.4'));
    if ($php === '') {
        fwrite(STDERR, "PII Redactor requires PHP 8.4 and Phel 0.49.\n");
        exit(1);
    }

    $command = array_merge([$php, __FILE__], array_slice($argv, 1));
    passthru(implode(' ', array_map('escapeshellarg', $command)), $status);
    exit($status);
}

$autoload = __DIR__ . '/vendor/autoload.php';
if (!is_file($autoload)) {
    fwrite(STDERR, "Missing Phel dependencies. Run: cd scripts && composer install\n");
    exit(1);
}

require $autoload;

Phel\Phel::run(__DIR__, 'pii.redactor.entry', array_slice($argv, 1));
