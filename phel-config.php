<?php

declare(strict_types=1);

use Phel\Config\PhelConfig;
use Phel\Config\ProjectLayout;

return PhelConfig::forProject(ProjectLayout::Flat)
    ->withMainPhelNamespace('pii.redactor.entry')
    ->withMainPhpPath('out/pii-redactor.php')
    ->withOptimizationLevel(2);
