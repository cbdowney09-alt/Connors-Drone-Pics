/**
 * KnoxCanvas emails, sent from your Google account:
 *   - a new company asks for access  → you get an email
 *   - a canvasser sends a hot lead    → that company's owner gets an email with the photo
 *
 * Setup (about 5 minutes):
 *  1. Go to script.google.com → New project. Paste this file in.
 *  2. Project Settings (gear icon) → tick "Show appsscript.json manifest file in editor".
 *     Open appsscript.json and replace it with admin/appsscript.json from this repo.
 *  3. Deploy → New deployment → type "Web app". Execute as: Me. Who has access: Anyone.
 *     Deploy, and allow the permissions (send email as you, read the KnoxCanvas database).
 *  4. Copy the Web app URL (ends in /exec) and put it in:
 *       - app.html and docs/app.html: const REQUEST_WEBHOOK = '...';
 *       - ios-native/KnoxCanvas/App/AppConfig.swift: static let requestWebhook = "..."
 *
 * Anyone on the internet can call a web app, so this never trusts the address in the request:
 * a lead email goes only to the owner on file for that company, and only if the lead really is
 * in the database. Requests and leads are saved in Firestore first; the email is a heads-up.
 */
const ADMIN_EMAIL = 'connorbdowney48@gmail.com';
const PROJECT = 'knoxcanvas-a7bfe';

function doPost(e) {
  let d = {};
  try { d = JSON.parse(e.postData.contents); } catch (err) { return ok(); }
  if (d.action === 'companyRequest') companyRequest(d);
  else if (d.action === 'lead') lead(d);
  return ok();
}

const clean = (v, n) => String(v || '').slice(0, n || 200);

function companyRequest(d) {
  const body = [
    'New company request on KnoxCanvas',
    '',
    'Company: ' + clean(d.company),
    'Owner:   ' + clean(d.owner),
    'Email:   ' + clean(d.email),
    'Phone:   ' + clean(d.phone),
    'From:    ' + clean(d.source),
    '',
    'Approve or decline it in KnoxCanvas: Account → Companies (admin).',
    'Company ID: ' + clean(d.companyId),
  ].join('\n');
  MailApp.sendEmail(ADMIN_EMAIL, 'KnoxCanvas request: ' + clean(d.company), body);
}

// Reads one document with your own access (the script runs as you).
function fsGet(path) {
  const r = UrlFetchApp.fetch('https://firestore.googleapis.com/v1/projects/' + PROJECT + '/databases/(default)/documents/' + path,
    { headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() }, muteHttpExceptions: true });
  return r.getResponseCode() === 200 ? JSON.parse(r.getContentText()).fields || {} : null;
}
const str = (f, k) => (f && f[k] && f[k].stringValue) || '';

function lead(d) {
  const cid = clean(d.companyId, 60), id = clean(d.id, 60);
  if (!/^[A-Za-z0-9_-]+$/.test(cid) || !/^[A-Za-z0-9_-]+$/.test(id)) return;
  // The lead must exist (the phone saves it a moment before asking for the email).
  let saved = fsGet('companies/' + cid + '/leads/' + id);
  if (!saved) { Utilities.sleep(3000); saved = fsGet('companies/' + cid + '/leads/' + id); }
  if (!saved) return;
  const company = fsGet('companies/' + cid);
  if (!company) return;
  let to = str(company, 'ownerEmail');
  if (!to) to = str(fsGet('users/' + str(company, 'ownerId')), 'email'); // companies from before requests
  if (!to) return;

  const addr = str(saved, 'addr'), reason = str(saved, 'reasonLabel');
  const lat = saved.lat && (saved.lat.doubleValue || saved.lat.integerValue), lng = saved.lng && (saved.lng.doubleValue || saved.lng.integerValue);
  const lines = [
    'Hot lead from ' + (str(saved, 'byName') || 'your team'),
    '',
    'Address:   ' + addr,
    'Why:       ' + reason,
    str(saved, 'homeowner') ? 'Homeowner: ' + str(saved, 'homeowner') : '',
    str(saved, 'phone') ? 'Phone:     ' + str(saved, 'phone') : '',
    str(saved, 'note') ? 'Note:      ' + str(saved, 'note') : '',
    lat && lng ? 'Map:       https://maps.google.com/?q=' + lat + ',' + lng : '',
    '',
    'See all hot leads in KnoxCanvas: Account → Hot leads.',
  ].filter(l => l !== '');
  const options = {};
  const photo = String(d.photo || '');
  const m = photo.match(/^data:(image\/(?:jpeg|png));base64,(.+)$/);
  if (m && photo.length < 1500000) options.attachments = [Utilities.newBlob(Utilities.base64Decode(m[2]), m[1], 'hot-lead.jpg')];
  MailApp.sendEmail(to, '🔥 Hot lead: ' + addr + (reason ? ' (' + reason + ')' : ''), lines.join('\n'), options);
}

function ok() {
  return ContentService.createTextOutput('ok');
}
