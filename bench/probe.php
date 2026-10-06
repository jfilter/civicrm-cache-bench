<?php
// Checks that the running variant stores caches where the benchmark expects; prints JSON, exits 1 on mismatch.
// Run via `cv scr` inside the app container.

const NAMED = ['session', 'settings', 'long', 'metadata', 'navigation', 'fields', 'groups', 'customData', 'contactTypes', 'js_strings', 'community_messages', 'checks', 'angular'];
const MEMORY = ['Redis', 'Memcached', 'Memcache', 'FileCache'];

// Unwraps CacheWrapper and array decorators down to the storage class; a tiered cache as "Tiered(near>far)".
function storage_class(CRM_Utils_Cache_Interface $cache): string {
  for ($depth = 0; $depth < 5; $depth++) {
    $inner = NULL;
    foreach ((new ReflectionObject($cache))->getProperties() as $prop) {
      $value = $prop->isInitialized($cache) ? $prop->getValue($cache) : NULL;
      if ($cache instanceof CRM_Utils_Cache_Tiered && $prop->getName() === 'tiers') {
        return 'Tiered(' . implode('>', array_map('storage_class', $value)) . ')';
      }
      if ($value instanceof CRM_Utils_Cache_Interface) {
        $inner = $value;
        break;
      }
    }
    if (!$inner) {
      break;
    }
    $cache = $inner;
  }
  return get_class($cache);
}

$driver = CIVICRM_DB_CACHE_CLASS;
$named = in_array($driver, MEMORY, TRUE) ? "CRM_Utils_Cache_$driver" : 'CRM_Utils_Cache_SqlGroup';
$named = match (BENCH_TIERS) {
  '' => $named,
  'apcu' => 'CRM_Utils_Cache_APCucache',
  'apcu,standard' => "Tiered(CRM_Utils_Cache_APCucache>$named)",
};
$expected = [
  'default' => "CRM_Utils_Cache_$driver",
  'prevNextCache' => 'CRM_Utils_Cache_SqlGroup',
  'prevnext_driver' => $driver === 'Redis' ? 'CRM_Core_PrevNextCache_Redis' : 'CRM_Core_PrevNextCache_Sql',
  'session_save_handler' => getenv('BENCH_SESSION_HANDLER') ?: 'files',
  // Production configuration: measured as a live site runs.
  'environment' => 'Production',
  'debug_enabled' => FALSE,
  'backtrace' => FALSE,
] + array_fill_keys(NAMED, $named);

$actual = [
  'default' => get_class(CRM_Utils_Cache::singleton()),
  'prevNextCache' => storage_class(Civi::cache('prevNextCache')),
  'prevnext_driver' => get_class(Civi::service('prevnext')),
  'session_save_handler' => ini_get('session.save_handler'),
  'environment' => Civi::settings()->get('environment'),
  'debug_enabled' => (bool) Civi::settings()->get('debug_enabled'),
  'backtrace' => (bool) Civi::settings()->get('backtrace'),
];
foreach (NAMED as $name) {
  $actual[$name] = storage_class(Civi::cache($name));
}

$mismatch = array_keys(array_diff_assoc($expected, $actual));
echo json_encode(['driver' => $driver, 'ok' => !$mismatch, 'mismatch' => $mismatch, 'actual' => $actual], JSON_PRETTY_PRINT), "\n";
exit($mismatch ? 1 : 0);
