<?php

/**
 * @file
 * Twig-CS-Fixer configuration used by drupal-lint.sh.
 *
 * Used only when the project has no .twig-cs-fixer.php or
 * .twig-cs-fixer.dist.php of its own. The ruleset is empty, so the only
 * reported problems are templates that cannot be tokenized (unclosed or
 * malformed {{ }}, {% %} and {# #} delimiters). Style is left to the project.
 */

declare(strict_types=1);

$config = new TwigCsFixer\Config\Config('drupal-dev syntax only');
$config->setRuleset(new TwigCsFixer\Ruleset\Ruleset());

return $config;
