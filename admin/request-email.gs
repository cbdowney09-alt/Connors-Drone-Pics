/**
 * KnoxCanvas: email the admin when a company requests access.
 *
 * Setup (5 minutes):
 *  1. Go to script.google.com → New project. Paste this file in.
 *  2. Deploy → New deployment → type "Web app".
 *     Execute as: Me. Who has access: Anyone. Deploy, and allow the permissions.
 *  3. Copy the Web app URL (ends in /exec) and put it in:
 *       - app.html and docs/app.html: const REQUEST_WEBHOOK = '...';
 *       - ios-native/KnoxCanvas/App/AppConfig.swift: static let requestWebhook = "..."
 *
 * The request is already saved in Firestore before this runs; the email is just a heads-up.
 * Approve it in the iPhone app: Account → Admin: companies.
 */
const ADMIN_EMAIL = 'connorbdowney48@gmail.com';

function doPost(e) {
  let d = {};
  try { d = JSON.parse(e.postData.contents); } catch (err) { return ok(); }
  if (d.action !== 'companyRequest') return ok();
  const clean = v => String(v || '').slice(0, 200);
  const body = [
    'New company request on KnoxCanvas',
    '',
    'Company: ' + clean(d.company),
    'Owner:   ' + clean(d.owner),
    'Email:   ' + clean(d.email),
    'Phone:   ' + clean(d.phone),
    'From:    ' + clean(d.source),
    '',
    'Approve or decline it in the KnoxCanvas iPhone app: Account → Admin: companies.',
    'Company ID: ' + clean(d.companyId),
  ].join('\n');
  MailApp.sendEmail(ADMIN_EMAIL, 'KnoxCanvas request: ' + clean(d.company), body);
  return ok();
}

function ok() {
  return ContentService.createTextOutput('ok');
}
