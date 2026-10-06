<?php
// Admin form for one Individual, prefilled from the URL (#?Individual1=<id>); measured by the afform-contact scenario.
return [
  'type' => 'form',
  'title' => 'Bench contact',
  'server_route' => 'civicrm/bench-contact',
  'permission' => ['access CiviCRM'],
  'create_submission' => FALSE,
];
