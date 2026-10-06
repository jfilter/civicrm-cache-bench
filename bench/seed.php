<?php
// Deterministic synthetic dataset. Run once via `cv scr bench/seed.php` on a fresh install.
// Sizes can be overridden for quick trials: SEED_CONTACTS, SEED_ACTIVITIES, SEED_CONTRIBUTIONS.

use Civi\Api4;

mt_srand(20261006);
$nContacts = (int) (getenv('SEED_CONTACTS') ?: 50000);
$nActivities = (int) (getenv('SEED_ACTIVITIES') ?: 200000);
$nContributions = (int) (getenv('SEED_CONTRIBUTIONS') ?: 50000);
$t0 = microtime(TRUE);
$log = function (string $msg) use ($t0) {
  fprintf(STDERR, "[seed %5.0fs] %s\n", microtime(TRUE) - $t0, $msg);
};
$pick = fn(array $a) => $a[mt_rand(0, count($a) - 1)];

$first = ['Anna', 'Ben', 'Clara', 'David', 'Eva', 'Felix', 'Greta', 'Hannes', 'Ida', 'Jonas', 'Karla', 'Leon', 'Mia', 'Noah', 'Olga', 'Paul', 'Rosa', 'Samuel', 'Tara', 'Uwe'];
$last = ['Adler', 'Becker', 'Conrad', 'Dietz', 'Engel', 'Fischer', 'Graf', 'Hahn', 'Imhof', 'Jäger', 'Keller', 'Lange', 'Meyer', 'Neumann', 'Otto', 'Peters', 'Roth', 'Schulz', 'Thiel', 'Vogel'];
$cities = ['Berlin', 'Hamburg', 'München', 'Köln', 'Leipzig', 'Dresden', 'Bremen', 'Kassel', 'Mainz', 'Kiel'];
$words = ['Verein', 'Stiftung', 'Initiative', 'Netzwerk', 'Bündnis', 'Forum', 'Werkstatt', 'Kollektiv'];

// Settings: production mode, no debug output.
Civi::settings()->set('environment', 'Production');
Civi::settings()->set('debug_enabled', 0);
Civi::settings()->set('backtrace', 0);

// Custom fields: 3 groups × 5 fields on Individuals.
$customFields = [];
foreach (['Interests', 'Membership_Details', 'Preferences'] as $g) {
  Api4\CustomGroup::create(FALSE)
    ->setValues(['name' => $g, 'title' => str_replace('_', ' ', $g), 'extends' => 'Individual', 'style' => 'Inline'])
    ->execute();
  for ($i = 1; $i <= 5; $i++) {
    Api4\CustomField::create(FALSE)
      ->setValues(['custom_group_id.name' => $g, 'name' => "field_$i", 'label' => "Field $i", 'html_type' => 'Text', 'data_type' => 'String'])
      ->execute();
    $customFields[] = "$g.field_$i";
  }
}
$log('custom fields');

// Contacts: 80 % individuals, 15 % organisations, 5 % households.
$batch = [];
$flush = function () use (&$batch) {
  if ($batch) {
    Api4\Contact::save(FALSE)->setRecords($batch)->setReload(FALSE)->execute();
    $batch = [];
  }
};
for ($i = 0; $i < $nContacts; $i++) {
  $r = mt_rand(1, 100);
  $city = $pick($cities);
  if ($r <= 80) {
    $c = ['contact_type' => 'Individual', 'first_name' => $pick($first), 'last_name' => $pick($last)];
    foreach ($customFields as $f) {
      $c[$f] = $pick($words) . ' ' . mt_rand(1, 99);
    }
  }
  elseif ($r <= 95) {
    $c = ['contact_type' => 'Organization', 'organization_name' => $pick($words) . ' ' . $city . ' ' . $i];
  }
  else {
    $c = ['contact_type' => 'Household', 'household_name' => 'Haushalt ' . $pick($last) . ' ' . $i];
  }
  $c['email_primary.email'] = "contact$i@example.org";
  $c['address_primary.city'] = $city;
  $c['address_primary.postal_code'] = sprintf('%05d', mt_rand(1000, 99999));
  $batch[] = $c;
  if (count($batch) === 500) {
    $flush();
    if ($i % 5000 === 4999) {
      $log(($i + 1) . ' contacts');
    }
  }
}
$flush();
$contactIds = Api4\Contact::get(FALSE)->addSelect('id')->addWhere('contact_type', '=', 'Individual')->execute()->column('id');
$log(count($contactIds) . ' individuals');

// 15 static groups with ~2 % of individuals each, 5 smart groups by city.
for ($g = 1; $g <= 15; $g++) {
  $gid = Api4\Group::create(FALSE)->setValues(['title' => "Static group $g", 'group_type' => ['Mailing List']])->execute()->single()['id'];
  $members = [];
  foreach ($contactIds as $cid) {
    if (mt_rand(1, 50) === 1) {
      $members[] = ['group_id' => $gid, 'contact_id' => $cid, 'status' => 'Added'];
    }
  }
  Api4\GroupContact::save(FALSE)->setRecords($members)->setReload(FALSE)->execute();
}
foreach (array_slice($cities, 0, 5) as $city) {
  $search = Api4\SavedSearch::create(FALSE)->setValues([
    'name' => "smart_$city",
    'label' => "Smart: $city",
    'api_entity' => 'Contact',
    'api_params' => ['version' => 4, 'select' => ['id'], 'where' => [['contact_type', '=', 'Individual'], ['address_primary.city', '=', $city]]],
  ])->execute()->single();
  Api4\Group::create(FALSE)->setValues(['title' => "Smart group $city", 'saved_search_id' => $search['id']])->execute();
}
$log('groups');

// 10 public events, 5 contribution pages.
for ($e = 1; $e <= 10; $e++) {
  Api4\Event::create(FALSE)->setValues([
    'title' => "Event $e",
    'event_type_id:name' => 'Conference',
    'start_date' => date('Y-m-d', strtotime("+$e weeks")) . ' 18:00:00',
    'is_public' => TRUE,
    'is_active' => TRUE,
    'is_online_registration' => TRUE,
    'summary' => 'Synthetic event for benchmarking.',
    'description' => str_repeat('Lorem ipsum dolor sit amet. ', 20),
  ])->execute();
}
for ($p = 1; $p <= 5; $p++) {
  $page = Api4\ContributionPage::create(FALSE)->setValues([
    'title' => "Donation page $p",
    'financial_type_id:name' => 'Donation',
    'is_active' => TRUE,
    'is_monetary' => TRUE,
    'is_allow_other_amount' => TRUE,
    'min_amount' => 1,
    'max_amount' => 10000,
    'is_pay_later' => TRUE,
    'pay_later_text' => 'Pay later',
    'currency' => 'EUR',
  ])->execute()->single();
  // A contribution page renders only with a price set; one free-amount field.
  $ps = Api4\PriceSet::create(FALSE)->setValues([
    'name' => "donation_page_$p",
    'title' => "Donation page $p",
    'extends:name' => ['CiviContribute'],
    'financial_type_id:name' => 'Donation',
  ])->execute()->single();
  $pf = Api4\PriceField::create(FALSE)->setValues([
    'price_set_id' => $ps['id'], 'name' => 'amount', 'label' => 'Amount', 'html_type' => 'Text', 'is_enter_qty' => TRUE, 'is_required' => TRUE,
  ])->execute()->single();
  Api4\PriceFieldValue::create(FALSE)->setValues([
    'price_field_id' => $pf['id'], 'name' => 'amount', 'label' => 'Amount', 'amount' => 1, 'financial_type_id:name' => 'Donation',
  ])->execute();
  Api4\PriceSetEntity::create(FALSE)->setValues(['price_set_id' => $ps['id'], 'entity_table' => 'civicrm_contribution_page', 'entity_id' => $page['id']])->execute();
}
$log('events and contribution pages');

// Activities and contributions are bulk-inserted: the API path would take hours and the
// benchmark only reads them (counts, tabs, search columns).
$typeIds = Api4\OptionValue::get(FALSE)->addSelect('value')->addWhere('option_group_id:name', '=', 'activity_type')
  ->addWhere('name', 'IN', ['Meeting', 'Phone Call', 'Email'])->execute()->column('value');
$sourceCid = $contactIds[0];
$maxActivity = (int) CRM_Core_DAO::singleValueQuery('SELECT COALESCE(MAX(id), 0) FROM civicrm_activity');
for ($done = 0; $done < $nActivities; $done += 2000) {
  $rows = $links = [];
  for ($k = 0; $k < 2000 && $done + $k < $nActivities; $k++) {
    $id = $maxActivity + $done + $k + 1;
    $date = date('Y-m-d H:i:s', mt_rand(strtotime('2020-01-01'), strtotime('2026-09-30')));
    $rows[] = sprintf('(%d, %d, "Activity %d", "%s", 2, 0, 0)', $id, $pick($typeIds), $id, $date);
    $links[] = sprintf('(%d, %d, 3)', $id, $pick($contactIds));
    $links[] = sprintf('(%d, %d, 2)', $id, $sourceCid);
  }
  CRM_Core_DAO::executeQuery('INSERT INTO civicrm_activity (id, activity_type_id, subject, activity_date_time, status_id, is_test, is_deleted) VALUES ' . implode(',', $rows));
  CRM_Core_DAO::executeQuery('INSERT INTO civicrm_activity_contact (activity_id, contact_id, record_type_id) VALUES ' . implode(',', $links));
}
$log("$nActivities activities");

$finType = (int) CRM_Core_DAO::singleValueQuery('SELECT id FROM civicrm_financial_type WHERE name = "Donation"');
for ($done = 0; $done < $nContributions; $done += 2000) {
  $rows = [];
  for ($k = 0; $k < 2000 && $done + $k < $nContributions; $k++) {
    $date = date('Y-m-d H:i:s', mt_rand(strtotime('2020-01-01'), strtotime('2026-09-30')));
    $amount = mt_rand(5, 500);
    $rows[] = sprintf('(%d, %d, "%s", %d, %d, "EUR", 1, 0)', $pick($contactIds), $finType, $date, $amount, $amount);
  }
  CRM_Core_DAO::executeQuery('INSERT INTO civicrm_contribution (contact_id, financial_type_id, receive_date, total_amount, net_amount, currency, contribution_status_id, is_test) VALUES ' . implode(',', $rows));
}
$log("$nContributions contributions");

CRM_Core_DAO::executeQuery('ANALYZE TABLE civicrm_contact, civicrm_email, civicrm_address, civicrm_group_contact, civicrm_activity, civicrm_activity_contact, civicrm_contribution');
$log('done');
