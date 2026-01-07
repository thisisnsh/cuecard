<?php
declare(strict_types=1);

header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store, no-cache, must-revalidate');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    http_response_code(405);
    echo 'Method Not Allowed';
    exit;
}

function wantsJson(): bool
{
    $accept = $_SERVER['HTTP_ACCEPT'] ?? '';
    $xhr = strtolower($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '');
    return strpos($accept, 'application/json') !== false || $xhr === 'xmlhttprequest';
}

function jsonResponse(bool $success, array $payload = []): void
{
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(array_merge(['success' => $success], $payload));
    exit;
}

function sanitizeReturnTo(?string $returnTo): string
{
    if (!$returnTo) {
        return '/';
    }

    $returnTo = trim($returnTo);
    if ($returnTo === '' || preg_match('/[\r\n]/', $returnTo)) {
        return '/';
    }

    if (strpos($returnTo, '//') === 0) {
        return '/';
    }

    if (strpos($returnTo, '/') === 0) {
        return $returnTo;
    }

    $parts = parse_url($returnTo);
    if (!$parts || empty($parts['host'])) {
        return '/';
    }

    $host = $_SERVER['HTTP_HOST'] ?? '';
    if (!$host || strcasecmp($parts['host'], $host) !== 0) {
        return '/';
    }

    $path = $parts['path'] ?? '/';
    $query = isset($parts['query']) ? '?' . $parts['query'] : '';
    $fragment = isset($parts['fragment']) ? '#' . $parts['fragment'] : '';

    return $path . $query . $fragment;
}

function normalizeEmail(string $email): string
{
    return strtolower(trim($email));
}

function isValidEmail(string $email): bool
{
    if ($email === '' || strlen($email) > 254) {
        return false;
    }

    if (preg_match('/[\x00-\x1F\x7F]/', $email)) {
        return false;
    }

    if (!preg_match('/^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$/i', $email)) {
        return false;
    }

    return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
}

function escapeCsvValue(string $value): string
{
    if (preg_match('/^[=\-+@\t]/', $value)) {
        return "'" . $value;
    }

    return $value;
}

function appendQueryParam(string $url, string $key, string $value): string
{
    $parts = parse_url($url);
    $path = $parts['path'] ?? '/';
    $query = [];
    if (!empty($parts['query'])) {
        parse_str($parts['query'], $query);
    }
    $query[$key] = $value;
    $queryString = http_build_query($query);
    $fragment = isset($parts['fragment']) ? '#' . $parts['fragment'] : '';

    return $path . ($queryString ? '?' . $queryString : '') . $fragment;
}

function redirectWithStatus(string $returnTo, string $status): void
{
    $url = appendQueryParam($returnTo, 'waitlist', $status);
    header('Location: ' . $url, true, 303);
    exit;
}

function resolveStorageDir(): string
{
    $candidates = [];
    $envDir = getenv('WAITLIST_DIR');
    if ($envDir) {
        $candidates[] = $envDir;
    }
    $candidates[] = dirname(__DIR__) . '/waitlist-data';
    $candidates[] = __DIR__ . '/data';

    foreach ($candidates as $candidate) {
        if (!$candidate) {
            continue;
        }
        $dir = rtrim($candidate, '/');
        if (!is_dir($dir)) {
            if (!@mkdir($dir, 0755, true)) {
                continue;
            }
        }
        if (is_writable($dir)) {
            return $dir;
        }
    }

    return '';
}

function protectStorageDir(string $storageDir): void
{
    $webRoot = realpath(__DIR__);
    $storageReal = realpath($storageDir);
    if (!$webRoot || !$storageReal) {
        return;
    }

    if (strpos($storageReal, $webRoot) !== 0) {
        return;
    }

    $htaccess = rtrim($storageDir, '/') . '/.htaccess';
    if (!file_exists($htaccess)) {
        @file_put_contents($htaccess, "Require all denied\nOptions -Indexes\n");
    }
}

$returnTo = sanitizeReturnTo($_POST['return_to'] ?? '');

if (!empty($_POST['company'] ?? '')) {
    if (wantsJson()) {
        jsonResponse(true, ['message' => 'ok']);
    }
    redirectWithStatus($returnTo, 'success');
}

$email = normalizeEmail((string)($_POST['email'] ?? ''));
if (!isValidEmail($email)) {
    if (wantsJson()) {
        jsonResponse(false, ['error' => 'invalid_email']);
    }
    redirectWithStatus($returnTo, 'invalid');
}

$email = escapeCsvValue($email);

$storageDir = resolveStorageDir();
if ($storageDir === '') {
    if (wantsJson()) {
        jsonResponse(false, ['error' => 'storage_unavailable']);
    }
    redirectWithStatus($returnTo, 'error');
}

protectStorageDir($storageDir);

$storageFile = rtrim($storageDir, '/') . '/waitlist.csv';
$isNewFile = !file_exists($storageFile);

$handle = @fopen($storageFile, 'a+');
if (!$handle) {
    if (wantsJson()) {
        jsonResponse(false, ['error' => 'storage_unavailable']);
    }
    redirectWithStatus($returnTo, 'error');
}

if (!flock($handle, LOCK_EX)) {
    fclose($handle);
    if (wantsJson()) {
        jsonResponse(false, ['error' => 'storage_unavailable']);
    }
    redirectWithStatus($returnTo, 'error');
}

if ($isNewFile) {
    fputcsv($handle, ['email', 'created_at']);
}

fputcsv($handle, [$email, gmdate('c')]);
flock($handle, LOCK_UN);
fclose($handle);

if (wantsJson()) {
    jsonResponse(true, ['message' => 'stored']);
}

redirectWithStatus($returnTo, 'success');
