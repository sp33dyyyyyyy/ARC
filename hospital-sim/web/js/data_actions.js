/* Tests, drugs, emergency equipment and bedside procedures. */
(function (G) {
  const HS = G.HS;

  // ------------------------------------------------------------------ TESTS
  // min = minutes until result, cost = $ charged to the hospital.
  HS.TESTS = {
    glucose:   { n: 'Fingerstick glucose', grp: 'Bedside', min: 2,  cost: 5,   norm: '102 mg/dL' },
    ecg:       { n: '12-lead ECG', grp: 'Bedside', min: 5,  cost: 30,  norm: 'Normal sinus rhythm, no ST changes' },
    fast:      { n: 'FAST ultrasound', grp: 'Bedside', min: 5,  cost: 60,  norm: 'No free fluid. No pericardial effusion. Lung sliding present bilaterally.' },
    abg:       { n: 'Arterial blood gas', grp: 'Bedside', min: 10, cost: 45,  norm: 'pH 7.40, pCO2 40, pO2 95, HCO3 24' },
    hcg:       { n: 'Urine hCG', grp: 'Bedside', min: 10, cost: 15,  norm: 'Negative' },
    ua:        { n: 'Urinalysis', grp: 'Bedside', min: 15, cost: 20,  norm: 'Clear. No leukocytes, nitrites or blood.' },
    troponin:  { n: 'Troponin', grp: 'Blood', min: 30, cost: 45,  norm: '<0.01 ng/mL (normal)' },
    cbc:       { n: 'CBC', grp: 'Blood', min: 30, cost: 25,  norm: 'WBC 7.2, Hb 14.1 g/dL, Plt 250 (normal)' },
    bmp:       { n: 'Chem panel (BMP)', grp: 'Blood', min: 30, cost: 30,  norm: 'Na 140, K 4.1, Cl 102, HCO3 24, BUN 14, Cr 0.9, glucose 98 (normal)' },
    lactate:   { n: 'Lactate', grp: 'Blood', min: 15, cost: 25,  norm: '1.0 mmol/L (normal)' },
    lipase:    { n: 'Lipase / LFTs', grp: 'Blood', min: 30, cost: 35,  norm: 'Lipase 30 U/L, LFTs normal' },
    ddimer:    { n: 'D-dimer', grp: 'Blood', min: 30, cost: 40,  norm: '0.2 ug/mL (negative)' },
    tox:       { n: 'Tox screen', grp: 'Blood', min: 30, cost: 55,  norm: 'Negative' },
    ethanol:   { n: 'Blood alcohol', grp: 'Blood', min: 20, cost: 25,  norm: '<10 mg/dL' },
    typecross: { n: 'Type & crossmatch', grp: 'Blood', min: 40, cost: 70,  norm: 'Type and screen complete; crossmatched units available' },
    bcx:       { n: 'Blood cultures', grp: 'Blood', min: 1440, cost: 40,  norm: 'No growth' },
    xr_chest:  { n: 'Chest X-ray', grp: 'Imaging', min: 20, cost: 80,  norm: 'Clear lungs, normal heart size, no pneumothorax' },
    xr_limb:   { n: 'X-ray limb / joint', grp: 'Imaging', min: 20, cost: 80,  norm: 'No fracture or dislocation' },
    xr_pelvis: { n: 'X-ray pelvis', grp: 'Imaging', min: 15, cost: 80,  norm: 'Pelvic ring intact, no fracture' },
    us_abd:    { n: 'Ultrasound abdomen / RUQ', grp: 'Imaging', min: 25, cost: 150, norm: 'No abnormality seen' },
    us_pelvic: { n: 'Ultrasound pelvis', grp: 'Imaging', min: 25, cost: 150, norm: 'Normal uterus and adnexa. No free fluid.' },
    us_scrotal:{ n: 'Ultrasound scrotum', grp: 'Imaging', min: 25, cost: 150, norm: 'Normal testicular flow bilaterally' },
    ct_head:   { n: 'CT head', grp: 'Imaging', min: 40, cost: 450, norm: 'No acute intracranial abnormality', ct: true },
    ct_abd:    { n: 'CT abdomen / pelvis', grp: 'Imaging', min: 45, cost: 600, norm: 'No acute abdominal pathology', ct: true },
    ct_cta:    { n: 'CT angiogram chest', grp: 'Imaging', min: 45, cost: 700, norm: 'No pulmonary embolism, no aortic pathology', ct: true },
  };

  // ------------------------------------------------------------------ ACTIONS
  // group: drug | airway | equip | proc | monitor
  // tags satisfy a condition's "need" list. route decides whether IV/IO access is required.
  HS.ACTIONS = {};
  const A = HS.ACTIONS;
  const add = (id, name, o) => { A[id] = Object.assign({ id, name, min: 2, cost: 5, tags: [], desc: '' }, o); };
  const drug = (id, name, o) => add(id, name, Object.assign({ group: 'drug', route: 'iv', unit: 'mg', doses: null }, o));

  // ----- vascular access / fluids / blood
  add('iv', 'IV access (large bore)', { group: 'access', min: 2, cost: 8, tags: ['iv'], desc: 'Peripheral line. Hard in shock — may fail.', stock: 'iv' });
  add('io', 'IO access (bone drill)', { group: 'access', min: 1, cost: 60, tags: ['io'], desc: 'Fast access in shock/arrest.', stock: 'io' });
  add('fluids', 'IV fluid bolus (crystalloid)', { group: 'drug', route: 'iv', min: 3, cost: 10, tags: ['fluids'], unit: 'mL', doses: [250, 500, 1000], stdIdx: 1, desc: 'Volume. Risky in heart failure.' });
  add('prbc', 'Blood — O-neg PRBC (1 unit)', { group: 'drug', route: 'iv', min: 3, cost: 220, tags: ['blood'], stock: 'blood', desc: 'Emergency release blood. Replaces lost volume.' });
  drug('txa', 'Tranexamic acid (TXA)', { tags: ['txa'], cost: 30, doses: [1, 1, 2], stdIdx: 1, unit: 'g', desc: 'Stops clot breakdown in bleeding. Best within 3 h.' });
  drug('norepi', 'Norepinephrine infusion', { tags: ['pressor'], cost: 40, doses: [2, 8, 16], stdIdx: 1, unit: 'mcg/min', desc: 'Vasopressor for shock after fluids.' });

  // ----- airway & breathing
  add('o2', 'Oxygen — non-rebreather 15 L/min', { group: 'airway', min: 1, cost: 3, tags: ['o2'], desc: 'Raises SpO2. Toggle on/off.' });
  add('suction', 'Suction airway', { group: 'airway', min: 1, cost: 2, tags: ['suction'], desc: 'Clear blood/vomit from airway.' });
  add('jaw', 'Jaw thrust / airway adjunct', { group: 'airway', min: 1, cost: 2, tags: ['jaw'], desc: 'Opens a collapsed airway.' });
  add('heimlich', 'Abdominal thrusts / back blows', { group: 'airway', min: 1, cost: 0, tags: ['heimlich'], desc: 'For a choking foreign body.' });
  add('bvm', 'Bag-valve-mask ventilation', { group: 'airway', min: 1, cost: 3, tags: ['bvm'], desc: 'Breathe for the patient.' });
  add('intubate', 'Intubate (ETT + ventilator)', { group: 'airway', min: 4, cost: 90, tags: ['airway'], stock: 'ett', desc: 'Definitive airway. Needs induction if awake (ketamine).' });
  add('cric', 'Surgical cricothyrotomy kit', { group: 'airway', min: 3, cost: 120, tags: ['airway', 'cric'], stock: 'cric', desc: "Can't intubate / can't oxygenate rescue." });

  // ----- emergency equipment (the ASAP kit)
  add('tourniquet', 'Tourniquet (CAT)', { group: 'equip', min: 1, cost: 35, tags: ['tourniquet'], stock: 'tourniquet', site: 'limb', desc: 'Stops life-threatening limb bleeding. High & tight on the correct limb. Note the time.' });
  add('pressure', 'Pressure dressing', { group: 'equip', min: 1, cost: 10, tags: ['pressure'], stock: 'dressing', desc: 'Direct pressure for moderate bleeding.' });
  add('hemogauze', 'Hemostatic gauze packing', { group: 'equip', min: 2, cost: 55, tags: ['packing'], stock: 'gauze', desc: 'Pack junctional/deep wounds where a tourniquet cannot go.' });
  add('binder', 'Pelvic binder', { group: 'equip', min: 1, cost: 70, tags: ['binder'], stock: 'binder', desc: 'Closes an unstable pelvic ring.' });
  add('collar', 'C-collar + spinal board', { group: 'equip', min: 2, cost: 40, tags: ['collar'], stock: 'collar', desc: 'Spinal precautions for major trauma.' });
  add('splint', 'Splint limb fracture', { group: 'equip', min: 3, cost: 25, tags: ['splint'], stock: 'splint', desc: 'Immobilize. Cuts pain and bleeding.' });
  add('chestseal', 'Vented chest seal', { group: 'equip', min: 1, cost: 30, tags: ['chestseal'], stock: 'chestseal', desc: 'Seals an open (sucking) chest wound.' });
  add('needle', 'Needle decompression (chest)', { group: 'equip', min: 1, cost: 25, tags: ['decompress'], stock: 'needle', desc: 'Relieves tension pneumothorax NOW.' });
  add('restraints', 'Soft restraints (4-point)', { group: 'equip', min: 3, cost: 0, tags: ['restraint'], desc: 'For violent patients endangering themselves/staff. Needs monitoring + usually sedation.' });
  add('unrestrain', 'Remove restraints', { group: 'equip', min: 1, cost: 0, tags: [], desc: 'Release once calm.' });
  add('defib', 'Defibrillate (200 J biphasic)', { group: 'equip', min: 1, cost: 5, tags: ['defib'], desc: 'ONLY for VF / pulseless VT.' });
  add('cardiovert', 'Synchronized cardioversion', { group: 'equip', min: 3, cost: 10, tags: ['cardiovert'], desc: 'For unstable SVT / AF-RVR. Sedate if awake.' });
  add('cpr', 'Start / stop chest compressions', { group: 'equip', min: 0, cost: 0, tags: ['cpr'], desc: '100–120/min. Minimise pauses.' });
  add('warm', 'Warming blanket / warm fluids', { group: 'equip', min: 2, cost: 20, tags: ['warm'], desc: 'Hypothermia.' });
  add('cool', 'Active cooling (ice, fans, cold fluids)', { group: 'equip', min: 3, cost: 20, tags: ['cool'], desc: 'Heat stroke / hyperthermia.' });
  add('monitor', 'Place on cardiac monitor', { group: 'monitor', min: 1, cost: 5, tags: ['monitor'], desc: 'Continuous vitals + rhythm.' });
  add('recheck', 'Recheck vitals now', { group: 'monitor', min: 1, cost: 0, tags: [], desc: 'Nurse updates the displayed vitals.' });
  add('ngt', 'Nasogastric tube', { group: 'proc', min: 4, cost: 15, tags: ['ngt'], desc: 'Decompress the stomach (obstruction).' });
  add('foley', 'Urinary catheter', { group: 'proc', min: 4, cost: 15, tags: ['foley'], desc: 'Track urine output.' });

  // ----- bedside procedures (use the procedure mini-game)
  add('chesttube', 'Chest tube (thoracostomy)', { group: 'proc', min: 10, cost: 150, tags: ['chesttube', 'decompress'], stock: 'chesttube', surgery: 'chesttube', desc: 'Drains air/blood from the chest.' });
  add('suturelac', 'Suture laceration', { group: 'proc', min: 15, cost: 20, tags: ['sutured'], surgery: 'suturelac', desc: 'Close a wound under local.' });
  add('reduce', 'Reduce dislocation', { group: 'proc', min: 15, cost: 20, tags: ['reduced'], surgery: 'reduce', desc: 'Put a dislocated joint back (sedate first).' });

  // ----- drugs. doses = [low, standard, high]; stdIdx marks the right one. perKg => paediatric mg/kg standard.
  drug('aspirin', 'Aspirin', { route: 'po', tags: ['antiplatelet'], doses: [81, 324, 650], stdIdx: 1, unit: 'mg', cost: 2, allergy: 'nsaid', contra: { hem_stroke: [18, 'Aspirin in a brain bleed'], epidural: [10, 'Aspirin with intracranial bleed'], perf_ulcer: [8, 'Aspirin in perforated ulcer'] }, desc: 'Antiplatelet for ACS.' });
  drug('heparin', 'Heparin', { tags: ['anticoag'], doses: [2500, 5000, 10000], stdIdx: 1, unit: 'units', cost: 12, bleedRisk: true, desc: 'Anticoagulant for PE / ACS / clot.' });
  drug('nitro', 'Nitroglycerin', { route: 'sl', tags: ['nitrate'], doses: [0.2, 0.4, 0.8], stdIdx: 1, unit: 'mg SL', cost: 4, hypo: 100, desc: 'Vasodilator. Dangerous if BP low.' });
  drug('morphine', 'Morphine', { tags: ['analgesia', 'opioid'], doses: [2, 4, 10], stdIdx: 1, unit: 'mg', cost: 6, allergy: 'opioid', hypo: 90, resp: true, desc: 'Strong analgesic. Can drop BP + breathing.' });
  drug('fentanyl', 'Fentanyl', { tags: ['analgesia', 'opioid'], doses: [25, 50, 150], stdIdx: 1, unit: 'mcg', cost: 8, allergy: 'opioid', resp: true, desc: 'Fast analgesic, BP-friendly.' });
  drug('ketamine', 'Ketamine', { tags: ['analgesia', 'sedation', 'induction'], doses: [20, 100, 250], stdIdx: 1, unit: 'mg', cost: 12, desc: 'Analgesia / procedural sedation / RSI induction. Preserves BP.' });
  drug('paracetamol', 'Paracetamol (acetaminophen)', { route: 'po', tags: ['analgesia_mild', 'antipyretic'], doses: [500, 1000, 2000], stdIdx: 1, unit: 'mg', cost: 2, desc: 'Mild pain/fever.' });
  drug('ibuprofen', 'Ibuprofen', { route: 'po', tags: ['analgesia_mild', 'antipyretic'], doses: [200, 400, 800], stdIdx: 1, unit: 'mg', cost: 2, allergy: 'nsaid', bleedRisk: true, contra: { asthma: [10, 'NSAID in asthma'], copd: [6, 'NSAID in COPD'], aki_stone: [4, 'NSAID with kidney injury'] }, desc: 'NSAID. Avoid with bleeding/asthma.' });
  drug('ondansetron', 'Ondansetron', { tags: ['antiemetic'], doses: [2, 4, 8], stdIdx: 1, unit: 'mg', cost: 4, desc: 'Anti-nausea.' });
  drug('antacid', 'Antacid + PPI (omeprazole)', { route: 'po', tags: ['antacid'], doses: [20, 40, 80], stdIdx: 1, unit: 'mg', cost: 3, desc: 'Reflux / ulcer.' });
  drug('ceftriaxone', 'Ceftriaxone', { tags: ['abx'], doses: [500, 1000, 2000], stdIdx: 1, unit: 'mg', cost: 10, allergy: 'penicillin', allergyMild: true, desc: 'Broad antibiotic.' });
  drug('amoxclav', 'Amoxicillin-clavulanate', { route: 'po', tags: ['abx'], doses: [500, 875, 1750], stdIdx: 1, unit: 'mg', cost: 4, allergy: 'penicillin', desc: 'Oral antibiotic.' });
  drug('pipetazo', 'Piperacillin-tazobactam', { tags: ['abx', 'abx_broad'], doses: [2250, 4500, 9000], stdIdx: 1, unit: 'mg', cost: 25, allergy: 'penicillin', desc: 'Broad-spectrum for sepsis/abdomen.' });
  drug('vanco', 'Vancomycin', { tags: ['abx', 'abx_mrsa'], doses: [500, 1500, 3000], stdIdx: 1, unit: 'mg', cost: 25, desc: 'MRSA cover.' });
  drug('azithro', 'Azithromycin', { route: 'po', tags: ['abx_atyp'], doses: [250, 500, 1000], stdIdx: 1, unit: 'mg', cost: 4, desc: 'Atypical pneumonia cover.' });
  drug('metro', 'Metronidazole', { tags: ['abx_anaer'], doses: [250, 500, 1000], stdIdx: 1, unit: 'mg', cost: 6, desc: 'Anaerobic cover (abdomen).' });
  drug('salbutamol', 'Salbutamol nebulizer', { route: 'neb', tags: ['bronchodilator'], doses: [2.5, 5, 10], stdIdx: 1, unit: 'mg', cost: 4, desc: 'Open the airways.' });
  drug('ipratropium', 'Ipratropium nebulizer', { route: 'neb', tags: ['bronchodilator2'], doses: [0.25, 0.5, 1], stdIdx: 1, unit: 'mg', cost: 4, desc: 'Add-on bronchodilator.' });
  drug('steroid', 'Methylprednisolone / prednisolone', { route: 'po', tags: ['steroid'], doses: [20, 40, 125], stdIdx: 1, unit: 'mg', cost: 5, desc: 'Reduces airway/allergic inflammation.' });
  drug('epi_im', 'Epinephrine IM (anaphylaxis)', { route: 'im', tags: ['epi'], doses: [0.15, 0.5, 1.0], stdIdx: 1, unit: 'mg', cost: 15, perKg: 0.01, desc: '1st-line for anaphylaxis (0.01 mg/kg).' });
  drug('epi_iv', 'Epinephrine 1 mg IV (arrest)', { tags: ['epi_arrest'], doses: [0.5, 1, 3], stdIdx: 1, unit: 'mg', cost: 15, desc: 'Cardiac arrest, every 3–5 min.' });
  drug('diphen', 'Diphenhydramine', { tags: ['antihistamine'], doses: [12.5, 50, 100], stdIdx: 1, unit: 'mg', cost: 3, desc: 'Antihistamine. Adjunct only in anaphylaxis.' });
  drug('adenosine', 'Adenosine', { tags: ['adenosine'], doses: [6, 12, 18], stdIdx: 0, unit: 'mg rapid push', cost: 20, desc: 'Converts SVT. 6 mg then 12 mg.' });
  drug('amio', 'Amiodarone', { tags: ['antiarrhythmic'], doses: [150, 300, 600], stdIdx: 1, unit: 'mg', cost: 35, desc: 'Refractory VF/VT.' });
  drug('furosemide', 'Furosemide', { tags: ['diuretic'], doses: [20, 40, 120], stdIdx: 1, unit: 'mg', cost: 4, hypovol: true, desc: 'Diuretic. Harmful if dry/bleeding.' });
  drug('insulin', 'Insulin infusion', { tags: ['insulin'], doses: [2, 6, 20], stdIdx: 1, unit: 'units/h', cost: 8, hypoglyc: true, desc: 'Lowers glucose. Dangerous if glucose is low.' });
  drug('dextrose', 'Dextrose 50% (D50)', { tags: ['dextrose'], doses: [12.5, 25, 50], stdIdx: 1, unit: 'g', cost: 5, desc: 'Treats hypoglycaemia.' });
  drug('naloxone', 'Naloxone', { route: 'iv', tags: ['naloxone'], doses: [0.04, 0.4, 2], stdIdx: 1, unit: 'mg', cost: 10, desc: 'Reverses opioids.' });
  drug('lorazepam', 'Lorazepam', { tags: ['anticonvulsant', 'sedation'], doses: [1, 4, 10], stdIdx: 1, unit: 'mg', cost: 8, resp: true, desc: 'Stops seizures; calms agitation.' });
  drug('midazolam', 'Midazolam IM', { route: 'im', tags: ['sedation', 'anticonvulsant'], doses: [2.5, 5, 15], stdIdx: 1, unit: 'mg', cost: 6, resp: true, desc: 'Fast IM sedation for agitated patients.' });
  drug('haloperidol', 'Haloperidol IM', { route: 'im', tags: ['sedation', 'antipsychotic'], doses: [2.5, 5, 15], stdIdx: 1, unit: 'mg', cost: 5, desc: 'Antipsychotic sedation.' });
  drug('alteplase', 'Alteplase (tPA)', { tags: ['thrombolytic'], doses: [0.45, 0.9, 1.5], stdIdx: 1, unit: 'mg/kg', cost: 3500, bleedRisk: true, desc: 'Clot-buster. ONLY ischaemic stroke <4.5 h, never with a bleed/trauma.' });
  drug('labetalol', 'Labetalol', { tags: ['antihypertensive'], doses: [10, 20, 80], stdIdx: 1, unit: 'mg', cost: 6, contra: { asthma: [10, 'Beta-blocker in asthma'] }, desc: 'Lowers BP.' });
  drug('magnesium', 'Magnesium sulfate', { tags: ['mag'], doses: [2, 4, 10], stdIdx: 1, unit: 'g', cost: 8, desc: 'Eclampsia seizure prophylaxis; severe asthma.' });
  drug('oxytocin', 'Oxytocin', { tags: ['oxytocin'], doses: [5, 10, 40], stdIdx: 1, unit: 'units', cost: 8, desc: 'Contracts the uterus (bleeding after birth).' });
  drug('anaesthetic', 'Procedural sedation (propofol)', { tags: ['sedation', 'induction'], doses: [20, 60, 200], stdIdx: 1, unit: 'mg', cost: 15, resp: true, hypo: 90, desc: 'Brief deep sedation for reductions.' });

  // quick lists for UI
  HS.ACTION_GROUPS = [
    ['Emergency kit', ['tourniquet', 'pressure', 'hemogauze', 'binder', 'collar', 'splint', 'chestseal', 'needle', 'chesttube', 'restraints', 'unrestrain', 'warm', 'cool']],
    ['Airway & breathing', ['o2', 'suction', 'jaw', 'heimlich', 'bvm', 'intubate', 'cric']],
    ['Resus', ['cpr', 'defib', 'cardiovert', 'epi_iv', 'amio', 'epi_im', 'io', 'iv', 'monitor', 'recheck']],
    ['Fluids & blood', ['fluids', 'prbc', 'txa', 'norepi']],
    ['Pain & sedation', ['paracetamol', 'ibuprofen', 'morphine', 'fentanyl', 'ketamine', 'anaesthetic', 'lorazepam', 'midazolam', 'haloperidol', 'ondansetron']],
    ['Cardiac', ['aspirin', 'nitro', 'heparin', 'adenosine', 'furosemide', 'labetalol', 'alteplase']],
    ['Respiratory & allergy', ['salbutamol', 'ipratropium', 'steroid', 'diphen']],
    ['Antibiotics', ['ceftriaxone', 'amoxclav', 'pipetazo', 'vanco', 'azithro', 'metro']],
    ['Metabolic / antidotes', ['insulin', 'dextrose', 'naloxone', 'magnesium', 'oxytocin', 'antacid']],
    ['Procedures', ['ngt', 'foley', 'suturelac', 'reduce']],
  ];

  // starting stock of limited supplies and the cost to restock one unit
  HS.SUPPLIES = {
    tourniquet: { n: 'Tourniquets', start: 8, max: 20, cost: 35 },
    dressing:   { n: 'Pressure dressings', start: 20, max: 40, cost: 10 },
    gauze:      { n: 'Hemostatic gauze', start: 10, max: 20, cost: 55 },
    binder:     { n: 'Pelvic binders', start: 3, max: 8, cost: 70 },
    collar:     { n: 'C-collars', start: 6, max: 12, cost: 40 },
    splint:     { n: 'Splints', start: 10, max: 20, cost: 25 },
    chestseal:  { n: 'Chest seals', start: 6, max: 12, cost: 30 },
    needle:     { n: 'Decompression needles', start: 6, max: 12, cost: 25 },
    chesttube:  { n: 'Chest tube kits', start: 4, max: 10, cost: 150 },
    iv:         { n: 'IV cannulas', start: 40, max: 80, cost: 8 },
    io:         { n: 'IO drills', start: 4, max: 10, cost: 60 },
    ett:        { n: 'Intubation kits', start: 6, max: 12, cost: 90 },
    cric:       { n: 'Cric kits', start: 3, max: 8, cost: 120 },
    blood:      { n: 'O-neg blood units', start: 10, max: 30, cost: 220 },
  };
})(typeof globalThis !== 'undefined' ? globalThis : window);
