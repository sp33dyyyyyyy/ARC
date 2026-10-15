/* Operations and bedside procedures.
   steps: [what you are doing, correct instrument, minutes, bleeding risk (ml if botched)]
   an = best anaesthetic; ok = acceptable alternatives. */
(function (G) {
  const HS = G.HS;
  HS.TOOLS = {
    scalpel: ['Scalpel', '🔪'], forceps: ['Forceps', '🥢'], retractor: ['Retractor', '🪝'], suction: ['Suction', '💧'], cautery: ['Cautery', '⚡'],
    clamp: ['Clamp', '🗜️'], suture: ['Suture', '🧵'], stapler: ['Stapler', '📎'], scissors: ['Scissors', '✂️'], drill: ['Bone drill', '🔩'],
    saw: ['Bone saw', '🪚'], packing: ['Lap packs', '🧻'], irrigation: ['Irrigation', '🚿'], graft: ['Vascular graft', '🩸'], plate: ['Plate & screws', '🔧'],
    mesh: ['Mesh', '🕸️'], catheter: ['Catheter + wire', '🧪'], needle: ['Needle', '💉'], implant: ['Implant', '🦴'], clip: ['Clip applier', '📍'],
    reamer: ['Reamer', '🌀'], dressing: ['Dressing', '🩹'], spreader: ['Rib spreader', '🔓'], stent: ['Stent', '🪢'], balloon: ['Balloon', '🎈'],
    trocar: ['Trocar / port', '📌'], tube: ['Chest drain', '🧴'], local: ['Local anaesthetic', '💊'],
  };
  HS.ANAES = { GA: 'General anaesthesia', regional: 'Spinal / regional block', local: 'Local + sedation', none: 'Local only (bedside)' };

  const S = (HS.SURGERIES = {});
  const add = (id, name, o) => { S[id] = Object.assign({ id, name, an: 'GA', ok: [], bed: false }, o); };

  add('appy', 'Appendectomy', { an: 'GA', desc: 'Remove the inflamed appendix.', steps: [
    ['Place ports / open the right iliac fossa', 'scalpel', 5, 120], ['Expose the caecum and appendix', 'retractor', 4, 60], ['Grasp and mobilise the appendix', 'forceps', 4, 80],
    ['Divide the mesoappendix vessels', 'cautery', 5, 200], ['Staple and divide the appendix base', 'stapler', 4, 150], ['Wash out the abdomen', 'irrigation', 3, 20], ['Close the wounds', 'suture', 6, 30] ] });
  add('chole', 'Cholecystectomy', { an: 'GA', desc: 'Remove the gallbladder.', steps: [
    ['Insert laparoscopic ports', 'trocar', 5, 100], ['Retract the liver edge to expose Calot triangle', 'retractor', 5, 60], ['Dissect out the cystic duct and artery', 'cautery', 8, 250],
    ['Clip the cystic duct and artery', 'clip', 4, 400], ['Free the gallbladder from the liver bed', 'cautery', 8, 200], ['Remove gallbladder via port', 'forceps', 4, 30], ['Close', 'suture', 6, 30] ] });
  add('bowel', 'Bowel resection', { an: 'GA', desc: 'Laparotomy and resection of obstructed/ischaemic bowel.', steps: [
    ['Midline laparotomy', 'scalpel', 6, 200], ['Run the bowel to find the transition point', 'forceps', 8, 80], ['Clamp both ends of dead bowel', 'clamp', 4, 150],
    ['Resect the diseased segment', 'scissors', 6, 200], ['Anastomose the bowel ends', 'stapler', 10, 150], ['Wash out the abdomen', 'irrigation', 4, 20], ['Close the abdomen', 'suture', 10, 60] ] });
  add('lap_repair', 'Laparotomy + ulcer repair (Graham patch)', { an: 'GA', desc: 'Close the hole in the stomach and wash out.', steps: [
    ['Midline laparotomy', 'scalpel', 6, 200], ['Find the perforation (retract the liver)', 'retractor', 6, 100], ['Suction the contamination', 'suction', 5, 20],
    ['Close the perforation with an omental patch', 'suture', 8, 120], ['Copious peritoneal washout', 'irrigation', 6, 20], ['Close the abdomen', 'suture', 10, 60] ] });
  add('hernia', 'Strangulated hernia repair', { an: 'GA', ok: ['regional'], desc: 'Reduce hernia, resect dead bowel, repair wall.', steps: [
    ['Groin incision down to the sac', 'scalpel', 5, 100], ['Open the sac and inspect the bowel', 'forceps', 5, 60], ['Resect non-viable bowel', 'scissors', 6, 150], ['Repair the defect with mesh', 'mesh', 8, 80], ['Close the layers', 'suture', 7, 30] ] });
  add('torsion', 'Testicular detorsion + orchiopexy', { an: 'GA', ok: ['regional', 'local'], desc: 'Untwist and fix both testes.', steps: [
    ['Scrotal incision', 'scalpel', 3, 50], ['Deliver and untwist the testis', 'forceps', 3, 30], ['Fix the testis with sutures (and the other side)', 'suture', 6, 20], ['Close', 'suture', 4, 20] ] });
  add('ectopic', 'Salpingectomy (ectopic pregnancy)', { an: 'GA', desc: 'Remove the ruptured tube.', steps: [
    ['Laparoscopic ports', 'trocar', 4, 100], ['Suction the hemoperitoneum', 'suction', 4, 100], ['Clamp the bleeding tube', 'clamp', 3, 350], ['Divide the fallopian tube', 'cautery', 4, 150], ['Remove the specimen', 'forceps', 3, 30], ['Close', 'suture', 5, 30] ] });
  add('csection', 'Emergency Caesarean section', { an: 'GA', ok: ['regional'], desc: 'Deliver the baby.', steps: [
    ['Pfannenstiel incision', 'scalpel', 3, 150], ['Open the uterus', 'scalpel', 2, 250], ['Deliver the baby', 'forceps', 2, 100], ['Clamp and cut the cord', 'clamp', 1, 30], ['Close the uterus', 'suture', 8, 300], ['Close the abdomen', 'suture', 8, 40] ] });
  add('trauma_lap', 'Trauma laparotomy (damage control)', { an: 'GA', desc: 'Stop the internal bleeding: splenectomy / liver packing.', steps: [
    ['Rapid midline laparotomy', 'scalpel', 3, 300], ['Pack all four quadrants', 'packing', 4, 250], ['Suction blood to find the source', 'suction', 3, 200], ['Clamp the splenic hilum / bleeding vessels', 'clamp', 4, 500],
    ['Remove the shattered spleen', 'cautery', 8, 300], ['Washout and temporary closure', 'irrigation', 5, 40] ] });
  add('aaa', 'Ruptured AAA repair (open)', { an: 'GA', desc: 'Cross-clamp aorta and place a graft.', steps: [
    ['Midline laparotomy (fast!)', 'scalpel', 3, 400], ['Get proximal control: clamp the aorta', 'clamp', 4, 800], ['Open the aneurysm sac and evacuate clot', 'scissors', 4, 400], ['Sew in the graft', 'graft', 15, 400], ['Release the clamp slowly', 'clamp', 3, 300], ['Close', 'suture', 8, 40] ] });
  add('thoracotomy', 'Emergency thoracotomy', { an: 'GA', desc: 'Open the chest to control bleeding / relieve tamponade.', steps: [
    ['Left anterolateral thoracotomy', 'scalpel', 3, 400], ['Spread the ribs', 'spreader', 2, 300], ['Open the pericardium', 'scissors', 2, 200], ['Control the bleeding vessel/lung with a clamp', 'clamp', 5, 700], ['Repair the injury', 'suture', 8, 300], ['Place chest drains and close', 'tube', 8, 60] ] });
  add('craniotomy', 'Craniotomy (evacuate hematoma)', { an: 'GA', desc: 'Drain the epidural bleed to save the brain.', steps: [
    ['Scalp incision', 'scalpel', 3, 100], ['Drill a burr hole', 'drill', 4, 100], ['Cut the bone flap', 'saw', 6, 150], ['Evacuate the clot', 'suction', 6, 250], ['Cauterise the bleeding middle meningeal artery', 'cautery', 4, 200], ['Replace the flap and close', 'plate', 8, 40] ] });
  add('orif', 'ORIF femur (plate & screws)', { an: 'GA', ok: ['regional'], desc: 'Fix the broken thigh bone.', steps: [
    ['Lateral thigh incision', 'scalpel', 4, 150], ['Expose and clean the fracture', 'retractor', 6, 100], ['Reduce the fracture with clamps', 'clamp', 8, 80], ['Drill screw holes', 'drill', 6, 60], ['Fix the plate with screws', 'plate', 12, 60], ['Irrigate and close', 'suture', 8, 30] ] });
  add('hip', 'Hip hemiarthroplasty', { an: 'regional', ok: ['GA'], desc: 'Replace the fractured femoral head.', steps: [
    ['Posterior hip incision', 'scalpel', 5, 150], ['Dislocate and remove the femoral head', 'retractor', 8, 100], ['Ream the femoral canal', 'reamer', 8, 80], ['Insert the prosthesis', 'implant', 8, 60], ['Close in layers', 'suture', 10, 40] ] });
  add('amput', 'Amputation (mangled limb)', { an: 'GA', desc: 'Remove the non-salvageable limb.', steps: [
    ['Fish-mouth skin flaps', 'scalpel', 5, 150], ['Divide and clamp the major vessels', 'clamp', 6, 500], ['Cut through the bone', 'saw', 5, 80], ['Smooth the stump and irrigate', 'irrigation', 4, 30], ['Close the flaps', 'suture', 8, 40] ] });
  add('vascular', 'Limb vascular repair', { an: 'GA', desc: 'Repair or bypass the severed artery.', steps: [
    ['Incision over the injury', 'scalpel', 4, 200], ['Control the artery above and below with clamps', 'clamp', 5, 500], ['Debride the vessel ends', 'scissors', 4, 100], ['Interposition graft', 'graft', 15, 300], ['Check flow, then fasciotomy to prevent compartment syndrome', 'scalpel', 6, 100], ['Close', 'suture', 8, 40] ] });
  add('fasciotomy', 'Decompressive fasciotomy', { an: 'GA', ok: ['regional'], desc: 'Release the pressure in the swollen compartments.', steps: [
    ['Long lateral leg incision', 'scalpel', 3, 100], ['Release the fascia over the compartments', 'scissors', 6, 100], ['Medial incision and release', 'scissors', 6, 100], ['Debride dead muscle', 'forceps', 5, 60], ['Dress and leave open', 'dressing', 4, 20] ] });
  add('washout', 'Arthroscopic washout of septic joint', { an: 'GA', ok: ['regional'], desc: 'Wash the pus out of the knee.', steps: [
    ['Arthroscopy portals', 'trocar', 3, 60], ['Inspect the joint', 'forceps', 3, 20], ['Copious irrigation', 'irrigation', 8, 20], ['Debride infected synovium', 'scissors', 6, 60], ['Place drain and close', 'suture', 4, 20] ] });
  add('id', 'Incision & drainage of abscess', { an: 'local', ok: ['GA'], desc: 'Lance and drain the abscess.', steps: [
    ['Infiltrate local anaesthetic', 'needle', 2, 5], ['Incise over the abscess', 'scalpel', 2, 40], ['Break down loculations', 'forceps', 3, 20], ['Irrigate and pack the cavity', 'packing', 3, 20] ] });
  add('embolectomy', 'Embolectomy (Fogarty catheter)', { an: 'regional', ok: ['GA', 'local'], desc: 'Remove the clot from the artery.', steps: [
    ['Groin cut-down to the femoral artery', 'scalpel', 4, 100], ['Clamp the artery above and below', 'clamp', 3, 150], ['Open the vessel', 'scalpel', 2, 80], ['Pass the Fogarty balloon catheter and pull the clot', 'catheter', 8, 100], ['Repair the arteriotomy', 'suture', 8, 100], ['Close', 'suture', 6, 30] ] });
  add('hyst', 'Emergency hysterectomy (uncontrolled PPH)', { an: 'GA', desc: 'Remove the uterus to stop the bleeding.', steps: [
    ['Midline laparotomy', 'scalpel', 3, 300], ['Clamp the uterine arteries', 'clamp', 4, 700], ['Divide the ligaments', 'cautery', 6, 300], ['Remove the uterus', 'scissors', 5, 200], ['Pack and close', 'suture', 8, 50] ] });
  add('pci', 'PCI — primary angioplasty & stent', { an: 'local', cath: true, ok: ['none'], desc: 'Cath lab: open the blocked coronary.', steps: [
    ['Radial artery access', 'needle', 3, 40], ['Pass the catheter to the coronaries', 'catheter', 6, 60], ['Cross the blockage with a wire', 'catheter', 5, 100], ['Inflate the balloon', 'balloon', 4, 100], ['Deploy the stent', 'stent', 5, 80] ] });

  // ---- bedside procedures (used from the Treat tab)
  add('chesttube', 'Chest tube (thoracostomy)', { an: 'none', bed: true, desc: 'Drain air and blood from the chest.', steps: [
    ['Infiltrate local anaesthetic', 'local', 1, 5], ['Incise in the 5th intercostal space', 'scalpel', 1, 40], ['Blunt dissect over the rib into the pleura', 'forceps', 2, 40], ['Insert the chest drain', 'tube', 2, 30], ['Secure and connect to the underwater seal', 'suture', 2, 5] ] });
  add('suturelac', 'Laceration repair', { an: 'none', bed: true, desc: 'Clean and close the wound.', steps: [
    ['Local anaesthetic', 'local', 1, 5], ['Irrigate the wound', 'irrigation', 2, 5], ['Close with sutures', 'suture', 6, 10] ] });
  add('reduce', 'Shoulder reduction', { an: 'none', bed: true, desc: 'Put the joint back.', steps: [
    ['Position and apply gentle traction', 'forceps', 2, 5], ['External rotation technique until the clunk', 'forceps', 3, 5], ['Sling and check pulses', 'dressing', 2, 5] ] });
})(typeof globalThis !== 'undefined' ? globalThis : window);
