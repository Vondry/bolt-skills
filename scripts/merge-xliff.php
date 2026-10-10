<?php

declare(strict_types=1);

/*
 * Merge XLIFF 2.0 translation units shipped by a skill into a project catalog.
 *
 * Usage:
 *   php vendor/tomvondracek/bolt-skills/scripts/merge-xliff.php <source.xlf> <target.xlf>
 *
 * Example:
 *   php vendor/tomvondracek/bolt-skills/scripts/merge-xliff.php \
 *       vendor/tomvondracek/bolt-skills/skills/bolt-theme-templates/examples/translations.cs.xlf \
 *       translations/messages.cs.xlf
 *
 * - Units are matched by their translation key: the unit's `name` attribute, or its
 *   <source> text when the unit has no name (the convention Symfony's loader uses).
 * - Units missing from the target are appended; existing units are never changed,
 *   so translations already edited in the project are kept.
 * - When the target does not exist, it is created from the source with `trgLang`
 *   and the file id taken from the target name (messages.<locale>.xlf).
 * - Unit ids are kept unique inside the target file.
 */

const XLIFF_NS = 'urn:oasis:names:tc:xliff:document:2.0';

if ($argc !== 3) {
    fwrite(STDERR, "Usage: php merge-xliff.php <source.xlf> <target.xlf>\n");
    exit(1);
}

[, $sourcePath, $targetPath] = $argv;

if (! is_file($sourcePath)) {
    fwrite(STDERR, "Source catalog not found: {$sourcePath}\n");
    exit(1);
}

$source = loadCatalog($sourcePath);

if (! is_file($targetPath)) {
    $locale = preg_match('/\.([a-zA-Z_]+)\.xlf$/', $targetPath, $m) === 1 ? $m[1] : null;
    if ($locale !== null) {
        $source->documentElement->setAttribute('trgLang', $locale);
        $file = firstFile($source);
        $domain = preg_match('/([^\/]+)\.[a-zA-Z_]+\.xlf$/', $targetPath, $d) === 1 ? $d[1] : 'messages';
        $file->setAttribute('id', $domain . '.' . $locale);
    }
    if (! is_dir(dirname($targetPath))) {
        mkdir(dirname($targetPath), 0775, true);
    }
    $source->save($targetPath);
    echo "Created {$targetPath} with " . count(units($source)) . " units.\n";
    exit(0);
}

$target = loadCatalog($targetPath);
$targetFile = firstFile($target);

$existingKeys = [];
$existingIds = [];
foreach (units($target) as $unit) {
    $existingKeys[unitKey($unit)] = true;
    $existingIds[$unit->getAttribute('id')] = true;
}

$added = 0;
foreach (units($source) as $unit) {
    $key = unitKey($unit);
    if ($key === '' || isset($existingKeys[$key])) {
        continue;
    }

    /** @var DOMElement $copy */
    $copy = $target->importNode($unit, true);

    $id = $copy->getAttribute('id') !== '' ? $copy->getAttribute('id') : preg_replace('/[^A-Za-z0-9_-]/', '_', $key);
    $candidate = $id;
    $suffix = 2;
    while (isset($existingIds[$candidate])) {
        $candidate = $id . '_' . $suffix++;
    }
    $copy->setAttribute('id', $candidate);
    $existingIds[$candidate] = true;
    $existingKeys[$key] = true;

    $targetFile->appendChild($target->createTextNode('  '));
    $targetFile->appendChild($copy);
    $targetFile->appendChild($target->createTextNode("\n  "));
    ++$added;
}

$target->save($targetPath);
echo "Merged {$added} new unit(s) into {$targetPath}.\n";

function loadCatalog(string $path): DOMDocument
{
    $doc = new DOMDocument();
    $doc->preserveWhiteSpace = true;
    if (! @$doc->load($path)) {
        fwrite(STDERR, "Cannot parse XML: {$path}\n");
        exit(1);
    }
    if ($doc->documentElement->namespaceURI !== XLIFF_NS) {
        fwrite(STDERR, "Not an XLIFF 2.0 catalog: {$path}\n");
        exit(1);
    }

    return $doc;
}

function firstFile(DOMDocument $doc): DOMElement
{
    $file = $doc->getElementsByTagNameNS(XLIFF_NS, 'file')->item(0);
    if (! $file instanceof DOMElement) {
        fwrite(STDERR, "Catalog has no <file> element.\n");
        exit(1);
    }

    return $file;
}

/** @return list<DOMElement> */
function units(DOMDocument $doc): array
{
    $list = [];
    foreach ($doc->getElementsByTagNameNS(XLIFF_NS, 'unit') as $unit) {
        $list[] = $unit;
    }

    return $list;
}

function unitKey(DOMElement $unit): string
{
    if ($unit->hasAttribute('name')) {
        return $unit->getAttribute('name');
    }
    $source = $unit->getElementsByTagNameNS(XLIFF_NS, 'source')->item(0);

    return $source !== null ? trim($source->textContent) : '';
}
