# Mercy General ER — Emergency Department Simulator (Android APK)

A realistic, hospital-style doctor / surgery simulator. You are the attending physician in a busy
emergency department. Patients walk in on their own, arrive by ambulance after accidents, or crash
unexpectedly in a bay. You diagnose, treat, send people home, admit them, or operate.

**Install:** copy `dist/MercyGeneralER.apk` to an Android phone (7.0+), allow "install unknown apps", tap it.
(Debug-signed, ~95 KB, fully offline, no permissions except vibration.)

## What's in it

* **54 conditions** across cardiac, respiratory, neuro, abdominal, OB/GYN, trauma, vascular, tox, environmental,
  infection, metabolic and psychiatric — each with its own symptoms, atypical presentations, exam findings,
  lab/imaging results, deterioration curve and correct disposition. Benign look-alikes (costochondritis, migraine, gastro)
  are mixed in with the killers.
* **Hospital flow:** triage queue (ESI 1–5, sometimes mis-triaged), inbound ambulances with paramedic hand-over and ETA,
  8 ER bays (2 resus), 10 ward beds, 3 ICU beds, 2 theatres + cath lab. When the department is full, patients wait —
  and deteriorate — in the corridor. Mass-casualty events happen rarely.
* **Real workup:** take a history (ask about allergies!), examine 6 body systems, order 24 tests that return after
  realistic delays (a first troponin can be falsely negative, CT in an unstable patient can crash them).
  Only patients on a monitor show live vitals; everyone else is a stale snapshot.
* **ASAP emergency equipment (limited stock, restock in Supplies):**
  tourniquets (correct limb, high and tight, with a running clock), pressure dressings, hemostatic gauze packing,
  pelvic binders, C-collars/spinal boards, splints, vented chest seals, needle decompression, chest tubes,
  O₂ / suction / jaw thrust / abdominal thrusts / BVM / intubation / cricothyrotomy, IV and IO access,
  O-neg blood, TXA, defibrillator, synchronized cardioversion, soft restraints + chemical sedation for violent patients,
  warming and cooling.
* **38 drugs with dosing** (low / standard / high, weight-based for children), allergy reactions, contraindications
  (thrombolytics or heparin in a bleeder, nitrates in hypotension, insulin in hypoglycaemia, fluids in heart failure,
  opioids and respiratory depression…).
* **Random emergencies** — rare by design (about one every 6–8 game hours): cardiac arrest (VF / PEA / asystole with a
  full ACLS loop and reversible causes), anaphylaxis, seizure, airway obstruction, tension pneumothorax, re-bleed,
  hypoglycaemia, septic shock, violent patient. A red banner appears; ignore it and the patient dies.
* **25 operations and procedures** with their own pre-op checklist, anaesthesia choice, instrument-selection steps and
  a timing mini-game, plus intra-operative events (spurting vessel, falling BP, light anaesthesia):
  appendectomy, cholecystectomy, bowel resection, perforated ulcer repair, strangulated hernia, testicular torsion,
  ectopic pregnancy, caesarean, trauma laparotomy/splenectomy, ruptured AAA repair, emergency thoracotomy, craniotomy,
  femur ORIF, hip hemiarthroplasty, amputation, limb vascular repair, fasciotomy, septic joint washout,
  abscess I&D, embolectomy, emergency hysterectomy, PCI/stent (cath lab) — and bedside chest tube, laceration repair
  and shoulder reduction. Operating on the wrong problem is punished. The rest of the hospital keeps running while you scrub.
* **Consequences:** discharging someone who needed admission can send them back collapsed or dead (and a lawsuit).
  Reputation 0 = fired. Money matters: tests and supplies cost, correct cases pay, overheads tick.

## Controls
Top bar: pause / 1× / 2× / 4× / 8×. Tabs: ER board · Triage (ambulances + waiting room) · Wards · Supplies · Log.
Tap a patient → Overview (live monitor + emergency kit), History, Tests, Treat, Dispo/OR.
Android **Back** closes sheets. The game auto-saves.

## Project layout
```
web/            the whole game (plain HTML/CSS/JS, no build step, no dependencies)
  js/engine.js  simulation: physiology, bleeding, arrest, crises, dispositions (no DOM)
  js/data_*.js  conditions, drugs/equipment/tests, surgeries
  js/ui.js, surgery_ui.js, ecg.js, main.js
android/        minimal WebView wrapper (no libraries) — bundles ../web into the APK
dist/           prebuilt MercyGeneralER.apk
tests/          engine unit tests + a "competent doctor" bot for balance checks
```

## Build the APK yourself
Needs JDK 17+ and the Android SDK (platform 34, build-tools 34.0.0):
```
cd android
echo "sdk.dir=/path/to/android-sdk" > local.properties
./gradlew assembleDebug            # → app/build/outputs/apk/debug/app-debug.apk
```
## Play in a browser / run the tests
Open `web/index.html` in any browser (mobile layout), or:
```
node tests/engine.test.js      # data integrity + behaviour tests
node tests/bot.test.js 1 1     # balance: a competent scripted doctor over 3 game days (seed, difficulty)
```

*Educational game. Medical content is simplified and is not clinical advice.*
