<?php
// Included at the top of civicrm.settings.php; the variant is chosen by the container environment.
foreach (['CLASS', 'HOST', 'PORT', 'PASSWORD', 'PREFIX'] as $key) {
  $value = getenv("BENCH_CACHE_$key");
  if ($value !== FALSE && $value !== '') {
    define("CIVICRM_DB_CACHE_$key", $key === 'PORT' ? (int) $value : $value);
  }
}

// BENCH_TIERS, used via patches/cache-tiers.patch: "apcu" = APCu as memory backend for all caches,
// "apcu,standard" = APCu in front of the CIVICRM_DB_CACHE_CLASS backend, empty = core behaviour.
const BENCH_APCU_TTL = 300;
define('BENCH_TIERS', (string) getenv('BENCH_TIERS'));
if (!in_array(BENCH_TIERS, ['', 'apcu', 'apcu,standard'], TRUE)) {
  throw new RuntimeException('Unknown BENCH_TIERS: ' . BENCH_TIERS);
}

function bench_memory_classes(array $classes): array {
  return BENCH_TIERS === 'apcu' ? [...$classes, 'APCucache'] : $classes;
}

function bench_cache_tiers(CRM_Utils_Cache_Interface $cache, string $prefix): CRM_Utils_Cache_Interface {
  if (BENCH_TIERS !== 'apcu,standard') {
    return $cache;
  }
  $config = ['prefix' => $prefix];
  return new CRM_Utils_Cache_Tiered([new CRM_Utils_Cache_APCucache($config), $cache], [BENCH_APCU_TTL, 86400]);
}
