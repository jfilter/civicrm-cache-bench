<?php
// Reports the web server's PHP runtime; bench/run.sh requires a production configuration.
header('Content-Type: application/json');
echo json_encode([
  'display_errors' => ini_get('display_errors'),
  'zend.assertions' => ini_get('zend.assertions'),
  'opcache' => (bool) (opcache_get_status(FALSE)['opcache_enabled'] ?? FALSE),
  'debug_extensions' => array_values(array_intersect(['xdebug', 'pcov', 'blackfire', 'tideways', 'spx'], get_loaded_extensions())),
]);
