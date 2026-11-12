import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, collection, query, where, getDocs, Timestamp, serverTimestamp } from 'firebase/firestore';
import { readFileSync } from 'fs';

const env = await initializeTestEnvironment({ projectId: 'knox-rules-test', firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8085 } });
let pass = 0, fail = 0;
async function t(name, p) { try { await p; pass++; console.log('  ok  ', name); } catch (e) { fail++; console.log('  FAIL', name, '-', e.message.split('\n')[0]); } }

// Seed: legacy company (no status, like Jeff Woods), a paused company, an admin.
await env.withSecurityRulesDisabled(async ctx => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'admins/admin'), { note: 'connor' });
  await setDoc(doc(db, 'users/admin'), { name: 'Connor', role: 'owner', companyId: 'legacy' });
  await setDoc(doc(db, 'companies/legacy'), { name: 'Jeff Woods', ownerId: 'owner1', roofCutoff: 2012, sheetsUrl: '' });
  await setDoc(doc(db, 'users/owner1'), { name: 'Jeff', role: 'owner', companyId: 'legacy' });
  await setDoc(doc(db, 'users/emp1'), { name: 'Jake', role: 'employee', companyId: 'legacy' });
  await setDoc(doc(db, 'companies/legacy/pins/35.000000,-84.000000'), { status: 'hanger', ts: 1 });
  await setDoc(doc(db, 'companies/paused'), { name: 'Paused Co', ownerId: 'powner', status: 'paused' });
  await setDoc(doc(db, 'users/powner'), { name: 'P', role: 'owner', companyId: 'paused' });
  await setDoc(doc(db, 'users/pemp'), { name: 'PE', role: 'employee', companyId: 'paused' });
  await setDoc(doc(db, 'companies/paused/pins/1,1'), { status: 'none' });
  await setDoc(doc(db, 'users/outsider'), { name: 'O', role: 'owner', companyId: 'other' });
  await setDoc(doc(db, 'companies/other'), { name: 'Other', ownerId: 'outsider' });
  await setDoc(doc(db, 'invites/GOODCODE'), { companyId: 'legacy', companyName: 'Jeff Woods', createdBy: 'owner1', expiresAt: Timestamp.fromMillis(Date.now() + 86400000) });
  await setDoc(doc(db, 'invites/OLDCODE1'), { companyId: 'legacy', companyName: 'Jeff Woods', createdBy: 'owner1', expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
});
const as = uid => env.authenticatedContext(uid).firestore();

console.log('Existing company (no status) keeps working');
await t('owner reads own user doc', assertSucceeds(getDoc(doc(as('owner1'), 'users/owner1'))));
await t('owner reads company', assertSucceeds(getDoc(doc(as('owner1'), 'companies/legacy'))));
await t('employee reads pins', assertSucceeds(getDocs(collection(as('emp1'), 'companies/legacy/pins'))));
await t('employee writes pin', assertSucceeds(setDoc(doc(as('emp1'), 'companies/legacy/pins/35.1,-84.1'), { status: 'hanger', source: 'gps-sweep' }, { merge: true })));
await t('employee saves shift', assertSucceeds(setDoc(doc(as('emp1'), 'companies/legacy/shifts/s1'), { userId: 'emp1', trail: '1,2,3', trailMeters: 10, gpsHangers: 1 })));
await t('employee queries own shifts', assertSucceeds(getDocs(query(collection(as('emp1'), 'companies/legacy/shifts'), where('userId', '==', 'emp1')))));
await t('employee writes zones', assertSucceeds(setDoc(doc(as('emp1'), 'companies/legacy/settings/neighborhoodYears'), { zones: [] })));
await t('employee lists team (names on map)', assertSucceeds(getDocs(query(collection(as('emp1'), 'users'), where('companyId', '==', 'legacy')))));
await t('employee sets activeClockIn', assertSucceeds(setDoc(doc(as('emp1'), 'users/emp1'), { activeClockIn: 123 }, { merge: true })));
await t('owner saves settings', assertSucceeds(updateDoc(doc(as('owner1'), 'companies/legacy'), { name: 'Jeff Woods Roofing', roofCutoff: 2010, sheetsUrl: 'https://x' })));
await t('owner sets company states', assertSucceeds(updateDoc(doc(as('owner1'), 'companies/legacy'), { states: ['TN', 'NC'] })));
await t('employee CANNOT set company states', assertFails(updateDoc(doc(as('emp1'), 'companies/legacy'), { states: ['TX'] })));
await t('owner creates invite', assertSucceeds(setDoc(doc(as('owner1'), 'invites/NEWCODE1'), { companyId: 'legacy', companyName: 'J', createdBy: 'owner1', createdAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 1e8) })));

console.log('Nobody can unlock themselves');
await t('owner CANNOT change own status', assertFails(updateDoc(doc(as('owner1'), 'companies/legacy'), { status: 'active' })));
await t('paused owner CANNOT resume', assertFails(updateDoc(doc(as('powner'), 'companies/paused'), { status: 'active' })));
await t('employee CANNOT promote self to owner', assertFails(setDoc(doc(as('emp1'), 'users/emp1'), { role: 'owner' }, { merge: true })));
await t('employee CANNOT switch company', assertFails(setDoc(doc(as('emp1'), 'users/emp1'), { companyId: 'paused' }, { merge: true })));
await t('employee CANNOT edit company settings', assertFails(updateDoc(doc(as('emp1'), 'companies/legacy'), { name: 'x' })));
await t('nobody can make themselves admin', assertFails(setDoc(doc(as('emp1'), 'admins/emp1'), { x: 1 })));
await t('employee CANNOT list all companies', assertFails(getDocs(collection(as('emp1'), 'companies'))));
await t('outsider CANNOT read other company pins', assertFails(getDocs(collection(as('outsider'), 'companies/legacy/pins'))));
await t('outsider CANNOT read other company doc', assertFails(getDoc(doc(as('outsider'), 'companies/legacy'))));

console.log('New company requests');
{
  const db = as('newowner'); const b = writeBatch(db);
  b.set(doc(db, 'companies/newco'), { name: 'New Co', ownerId: 'newowner', status: 'pending', phone: '8655551234', createdAt: serverTimestamp() });
  b.set(doc(db, 'users/newowner'), { name: 'N', role: 'owner', companyId: 'newco' });
  await t('request a company (pending)', assertSucceeds(b.commit()));
}
{
  const db = as('sneaky'); const b = writeBatch(db);
  b.set(doc(db, 'companies/sneakyco'), { name: 'S', ownerId: 'sneaky', status: 'active' });
  b.set(doc(db, 'users/sneaky'), { name: 'S', role: 'owner', companyId: 'sneakyco' });
  await t('CANNOT create an active company', assertFails(b.commit()));
}
{
  const db = as('oldweb'); const b = writeBatch(db);
  b.set(doc(db, 'companies/oldwebco'), { name: 'S', ownerId: 'oldweb', roofCutoff: 2012, sheetsUrl: '' });
  b.set(doc(db, 'users/oldweb'), { name: 'S', role: 'owner', companyId: 'oldwebco' });
  await t('CANNOT create a company without status (old website)', assertFails(b.commit()));
}
await t('CANNOT claim owner of an existing company', assertFails(setDoc(doc(as('thief'), 'users/thief'), { role: 'owner', companyId: 'legacy' })));
await t('pending owner reads own company (waiting screen)', assertSucceeds(getDoc(doc(as('newowner'), 'companies/newco'))));
await t('pending owner CANNOT add pins', assertFails(setDoc(doc(as('newowner'), 'companies/newco/pins/1,1'), { status: 'none' })));
await t('pending owner CANNOT create invites', assertFails(setDoc(doc(as('newowner'), 'invites/PENDCODE'), { companyId: 'newco', createdBy: 'newowner', expiresAt: Timestamp.fromMillis(Date.now() + 1e8) })));
await t('pending owner CANNOT approve self', assertFails(updateDoc(doc(as('newowner'), 'companies/newco'), { status: 'active' })));

console.log('Joining with invite codes');
{
  const db = as('newemp'); const b = writeBatch(db);
  b.set(doc(db, 'users/newemp'), { name: 'E', role: 'employee', companyId: 'legacy', companyName: 'J', inviteCode: 'GOODCODE' });
  b.delete(doc(db, 'invites/GOODCODE'));
  await t('join with a valid code', assertSucceeds(b.commit()));
}
{
  const db = as('lateemp'); const b = writeBatch(db);
  b.set(doc(db, 'users/lateemp'), { name: 'E', role: 'employee', companyId: 'legacy', inviteCode: 'OLDCODE1' });
  b.delete(doc(db, 'invites/OLDCODE1'));
  await t('CANNOT join with an expired code', assertFails(b.commit()));
}
await t('CANNOT join without a code', assertFails(setDoc(doc(as('nocode'), 'users/nocode'), { role: 'employee', companyId: 'legacy' })));
{
  const db = as('reuse'); 
  await t('CANNOT join without using up the code', assertFails(setDoc(doc(db, 'users/reuse'), { role: 'employee', companyId: 'legacy', inviteCode: 'NEWCODE1' })));
}

console.log('Paused company');
await t('paused employee reads company doc (paused screen)', assertSucceeds(getDoc(doc(as('pemp'), 'companies/paused'))));
await t('paused employee CANNOT read pins', assertFails(getDocs(collection(as('pemp'), 'companies/paused/pins'))));
await t('paused employee CANNOT write pins', assertFails(setDoc(doc(as('pemp'), 'companies/paused/pins/2,2'), { status: 'none' })));
await t('paused owner CANNOT read shifts', assertFails(getDocs(collection(as('powner'), 'companies/paused/shifts'))));

console.log('Admin');
await t('admin reads own admin doc', assertSucceeds(getDoc(doc(as('admin'), 'admins/admin'))));
await t('non-admin admin check reads nothing', (async () => { const s = await getDoc(doc(as('emp1'), 'admins/emp1')); if (s.exists()) throw new Error('exists'); })());
await t('admin lists all companies', assertSucceeds(getDocs(collection(as('admin'), 'companies'))));
await t('admin approves request', assertSucceeds(updateDoc(doc(as('admin'), 'companies/newco'), { status: 'active', statusAt: serverTimestamp(), statusBy: 'admin' })));
await t('approved owner can now add pins', assertSucceeds(setDoc(doc(as('newowner'), 'companies/newco/pins/1,1'), { status: 'none' })));
await t('admin pauses a company', assertSucceeds(updateDoc(doc(as('admin'), 'companies/newco'), { status: 'paused' })));
await t('then its owner is locked out', assertFails(getDocs(collection(as('newowner'), 'companies/newco/pins'))));
await t('admin resumes', assertSucceeds(updateDoc(doc(as('admin'), 'companies/paused'), { status: 'active' })));
await t('resumed employee reads pins again', assertSucceeds(getDocs(collection(as('pemp'), 'companies/paused/pins'))));
await t('admin counts members of any company', assertSucceeds(getDocs(query(collection(as('admin'), 'users'), where('companyId', '==', 'other')))));
await t('admin lists every user (team sizes on Companies)', assertSucceeds(getDocs(collection(as('admin'), 'users'))));
await t('owner CANNOT list every user', assertFails(getDocs(collection(as('owner1'), 'users'))));
await t('owner CANNOT list another company\'s team', assertFails(getDocs(query(collection(as('owner1'), 'users'), where('companyId', '==', 'other')))));
await t('admin reads any company pins (counts)', assertSucceeds(getDocs(collection(as('admin'), 'companies/other/pins'))));
await t('admin reads owner profile', assertSucceeds(getDoc(doc(as('admin'), 'users/outsider'))));

console.log('Doorline Hangers');
await env.withSecurityRulesDisabled(async ctx => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'companies/dlhq'), { name: 'Doorline Hangers', ownerId: 'dlowner', status: 'active' });
  await setDoc(doc(db, 'users/dlowner'), { name: 'Connor', role: 'owner', companyId: 'dlhq' });
  await setDoc(doc(db, 'users/crew1'), { name: 'Crew', role: 'employee', companyId: 'dlhq' });
  await setDoc(doc(db, 'users/crew2'), { name: 'Crew Two', role: 'employee', companyId: 'dlhq' });
  await setDoc(doc(db, 'companies/acme'), { name: 'Acme', ownerId: 'acmeowner', status: 'active', doorline: true, crew: ['crew1'] });
  await setDoc(doc(db, 'users/acmeowner'), { name: 'A', role: 'owner', companyId: 'acme' });
  await setDoc(doc(db, 'companies/acme/pins/1,1'), { status: 'hanger' });
});
{
  const db = as('dlnew'); const b = writeBatch(db);
  b.set(doc(db, 'companies/dlnewco'), { name: 'Client', ownerId: 'dlnew', status: 'pending', doorline: true });
  b.set(doc(db, 'users/dlnew'), { name: 'C', role: 'owner', companyId: 'dlnewco' });
  await t('request a Doorline client company', assertSucceeds(b.commit()));
}
await t('crew lists the clients they hang for', assertSucceeds(getDocs(query(collection(as('crew1'), 'companies'), where('crew', 'array-contains', 'crew1')))));
await t('crew reads the client doc', assertSucceeds(getDoc(doc(as('crew1'), 'companies/acme'))));
await t('crew reads client pins', assertSucceeds(getDocs(collection(as('crew1'), 'companies/acme/pins'))));
await t('crew hangs for client', assertSucceeds(setDoc(doc(as('crew1'), 'companies/acme/pins/2,2'), { status: 'hanger', source: 'gps-sweep' })));
await t('crew saves client shift (walk path)', assertSucceeds(setDoc(doc(as('crew1'), 'companies/acme/shifts/s1'), { userId: 'crew1', trail: '1,2,0' })));
await t('crew saves home copy of shift', assertSucceeds(setDoc(doc(as('crew1'), 'companies/dlhq/shifts/s1'), { userId: 'crew1', forCompanyId: 'acme', hangers: 1 })));
await t('client owner reads hangers', assertSucceeds(getDocs(collection(as('acmeowner'), 'companies/acme/pins'))));
await t('client owner reads walk paths', assertSucceeds(getDocs(collection(as('acmeowner'), 'companies/acme/shifts'))));
await t('client owner saves routes', assertSucceeds(setDoc(doc(as('acmeowner'), 'companies/acme/settings/areas'), { list: [{ id: 'a', kind: 'zip', zip: '37919', name: '37919' }] })));
await t('crew reads routes', assertSucceeds(getDoc(doc(as('crew1'), 'companies/acme/settings/areas'))));
await t('crew adds a photo for the client', assertSucceeds(setDoc(doc(as('crew1'), 'companies/acme/pinPhotos/C1'), { pinId: '2,2', by: 'crew1', data: 'data:image/jpeg;base64,xx' })));
await t('client owner sees the photo', assertSucceeds(getDoc(doc(as('acmeowner'), 'companies/acme/pinPhotos/C1'))));
await t('client owner CANNOT add photos', assertFails(setDoc(doc(as('acmeowner'), 'companies/acme/pinPhotos/C2'), { pinId: '2,2', by: 'acmeowner', data: 'x' })));
await t('client owner CANNOT delete crew photos', assertFails(deleteDoc(doc(as('acmeowner'), 'companies/acme/pinPhotos/C1'))));
await t('unassigned crew CANNOT read client', assertFails(getDoc(doc(as('crew2'), 'companies/acme'))));
await t('unassigned crew CANNOT read client pins', assertFails(getDocs(collection(as('crew2'), 'companies/acme/pins'))));
await t('unassigned crew CANNOT write client pins', assertFails(setDoc(doc(as('crew2'), 'companies/acme/pins/3,3'), { status: 'hanger' })));
await t('crew CANNOT list all companies', assertFails(getDocs(collection(as('crew1'), 'companies'))));
await t('crew CANNOT list another person\'s clients', assertFails(getDocs(query(collection(as('crew2'), 'companies'), where('crew', 'array-contains', 'crew1')))));
await t('client owner CANNOT add crew', assertFails(updateDoc(doc(as('acmeowner'), 'companies/acme'), { crew: ['acmeowner', 'crew1'] })));
await t('client owner CANNOT drop doorline', assertFails(updateDoc(doc(as('acmeowner'), 'companies/acme'), { doorline: false })));
await t('crew CANNOT edit the client company', assertFails(updateDoc(doc(as('crew1'), 'companies/acme'), { name: 'x' })));
await t('client owner CANNOT read Doorline team', assertFails(getDoc(doc(as('acmeowner'), 'users/crew1'))));
await t('client owner CANNOT read Doorline pins', assertFails(getDocs(collection(as('acmeowner'), 'companies/dlhq/pins'))));
await t('admin lists Doorline clients', assertSucceeds(getDocs(query(collection(as('admin'), 'companies'), where('doorline', '==', true)))));
await t('admin assigns crew', assertSucceeds(updateDoc(doc(as('admin'), 'companies/acme'), { crew: ['crew1', 'crew2'] })));
await t('newly assigned crew reads client pins', assertSucceeds(getDocs(collection(as('crew2'), 'companies/acme/pins'))));
await t('admin pauses client', assertSucceeds(updateDoc(doc(as('admin'), 'companies/acme'), { status: 'paused' })));
await t('crew CANNOT hang for a paused client', assertFails(setDoc(doc(as('crew1'), 'companies/acme/pins/4,4'), { status: 'hanger' })));
console.log('Doorline crew (no company)');
await env.withSecurityRulesDisabled(async ctx => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'invites/CREWCODE'), { crew: true, companyId: '', createdBy: 'admin', expiresAt: Timestamp.fromMillis(Date.now() + 86400000) });
  await setDoc(doc(db, 'invites/OLDCREW1'), { crew: true, companyId: '', createdBy: 'admin', expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  await setDoc(doc(db, 'users/crewx'), { name: 'Other crew', role: 'crew', companyId: '' });
});
await t('admin makes a crew invite', assertSucceeds(setDoc(doc(as('admin'), 'invites/CREWNEW1'), { crew: true, companyId: '', createdBy: 'admin', expiresAt: Timestamp.fromMillis(Date.now() + 1e8) })));
await t('owner CANNOT make a crew invite', assertFails(setDoc(doc(as('owner1'), 'invites/CREWBAD1'), { crew: true, companyId: '', createdBy: 'owner1', expiresAt: Timestamp.fromMillis(Date.now() + 1e8) })));
await t('owner CANNOT sneak crew onto a company invite', assertFails(setDoc(doc(as('owner1'), 'invites/CREWBAD2'), { crew: true, companyId: 'legacy', createdBy: 'owner1', expiresAt: Timestamp.fromMillis(Date.now() + 1e8) })));
{
  const db = as('newcrew'); const b = writeBatch(db);
  b.set(doc(db, 'users/newcrew'), { name: 'New', role: 'crew', companyId: '', inviteCode: 'CREWCODE' });
  b.delete(doc(db, 'invites/CREWCODE'));
  await t('join the crew with a crew invite', assertSucceeds(b.commit()));
}
{
  const db = as('latecrew'); const b = writeBatch(db);
  b.set(doc(db, 'users/latecrew'), { name: 'L', role: 'crew', companyId: '', inviteCode: 'OLDCREW1' });
  b.delete(doc(db, 'invites/OLDCREW1'));
  await t('CANNOT join the crew with an expired code', assertFails(b.commit()));
}
{
  const db = as('fakecrew'); const b = writeBatch(db);
  b.set(doc(db, 'users/fakecrew'), { name: 'F', role: 'crew', companyId: '', inviteCode: 'NEWCODE1' });
  b.delete(doc(db, 'invites/NEWCODE1'));
  await t('CANNOT join the crew with a company invite', assertFails(b.commit()));
}
{
  const db = as('crewjump'); const b = writeBatch(db);
  b.set(doc(db, 'users/crewjump'), { name: 'J', role: 'crew', companyId: 'legacy', inviteCode: 'CREWNEW1' });
  b.delete(doc(db, 'invites/CREWNEW1'));
  await t('CANNOT use a crew invite to get into a company', assertFails(b.commit()));
}
await t('crew reads own profile', assertSucceeds(getDoc(doc(as('newcrew'), 'users/newcrew'))));
await t('crew CANNOT read another crew member', assertFails(getDoc(doc(as('newcrew'), 'users/crewx'))));
await t('crew CANNOT list crew members', assertFails(getDocs(query(collection(as('newcrew'), 'users'), where('companyId', '==', '')))));
await t('crew CANNOT give self a company', assertFails(setDoc(doc(as('newcrew'), 'users/newcrew'), { companyId: 'legacy' }, { merge: true })));
await t('unassigned crew CANNOT read client pins', assertFails(getDocs(collection(as('newcrew'), 'companies/acme/pins'))));
await t('admin lists the crew', assertSucceeds(getDocs(query(collection(as('admin'), 'users'), where('role', '==', 'crew')))));
await t('admin resumes client for crew test', assertSucceeds(updateDoc(doc(as('admin'), 'companies/acme'), { status: 'active', crew: ['crew1', 'newcrew'] })));
await t('assigned crew (no company) hangs for client', assertSucceeds(setDoc(doc(as('newcrew'), 'companies/acme/pins/5,5'), { status: 'hanger' })));
await t('assigned crew finds their clients', assertSucceeds(getDocs(query(collection(as('newcrew'), 'companies'), where('crew', 'array-contains', 'newcrew')))));
await t('employee still lists own team', assertSucceeds(getDocs(query(collection(as('crew1'), 'users'), where('companyId', '==', 'dlhq')))));
await t('admin removes a crew member', assertSucceeds(deleteDoc(doc(as('admin'), 'users/crewx'))));

await t('owner saves states (house data)', assertSucceeds(updateDoc(doc(as('owner1'), 'companies/legacy'), { states: ['TN'] })));

console.log('Who can change what (Comfort Pros build)');
await env.withSecurityRulesDisabled(async ctx => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/emp2'), { name: 'Maria', role: 'employee', companyId: 'legacy' });
  await setDoc(doc(db, 'companies/legacy/pins/9,9'), { status: 'hanger', createdBy: 'owner1' });
  await setDoc(doc(db, 'companies/legacy/shifts/other'), { userId: 'emp2', hangers: 5, clockIn: 1 });
  await setDoc(doc(db, 'companies/legacy/leads/L2'), { by: 'emp2', reason: 'roof' });
  await setDoc(doc(db, 'companies/acme/pins/7,7'), { status: 'hanger', createdBy: 'crew1' });
  await setDoc(doc(db, 'companies/acme/pins/8,8'), { status: 'hanger', createdBy: 'newcrew' });
});
await t('employee CANNOT delete a pin someone else placed', assertFails(deleteDoc(doc(as('emp1'), 'companies/legacy/pins/9,9'))));
await t('employee CANNOT delete an old pin with no creator', assertFails(deleteDoc(doc(as('emp1'), 'companies/legacy/pins/35.000000,-84.000000'))));
await t('employee places a pin', assertSucceeds(setDoc(doc(as('emp1'), 'companies/legacy/pins/6,6'), { status: 'none', createdBy: 'emp1' })));
await t('employee removes their own pin', assertSucceeds(deleteDoc(doc(as('emp1'), 'companies/legacy/pins/6,6'))));
await t('owner removes any pin', assertSucceeds(deleteDoc(doc(as('owner1'), 'companies/legacy/pins/9,9'))));
await t('employee CANNOT save a shift as someone else', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/shifts/fake'), { userId: 'emp2', hangers: 500 })));
await t('employee CANNOT save a shift with code in the numbers', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/shifts/xss'), { userId: 'emp1', hangers: '<img src=x onerror=alert(1)>' })));
await t('employee CANNOT rewrite another person\'s shift', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/shifts/other'), { userId: 'emp1', hangers: 0 })));
await t('employee CANNOT delete a shift', assertFails(deleteDoc(doc(as('emp1'), 'companies/legacy/shifts/other'))));
await t('owner deletes a shift', assertSucceeds(deleteDoc(doc(as('owner1'), 'companies/legacy/shifts/other'))));
await t('employee CANNOT change neighborhood assignments', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/settings/areas'), { list: [] })));
await t('owner assigns neighborhoods', assertSucceeds(setDoc(doc(as('owner1'), 'companies/legacy/settings/areas'), { list: [{ id: 'n1', kind: 'draw', name: 'Myers Park', assignees: ['emp1'] }] })));
await t('employee reads assignments', assertSucceeds(getDoc(doc(as('emp1'), 'companies/legacy/settings/areas'))));
await t('owner sets the detection distance', assertSucceeds(updateDoc(doc(as('owner1'), 'companies/legacy'), { doorRadius: 20 })));
await t('employee CANNOT set the detection distance', assertFails(updateDoc(doc(as('emp1'), 'companies/legacy'), { doorRadius: 45 })));
await t('employee sends a hot lead', assertSucceeds(setDoc(doc(as('emp1'), 'companies/legacy/leads/L1'), { by: 'emp1', reason: 'roof', addr: '1 Main St' })));
await t('employee sends the lead photo', assertSucceeds(setDoc(doc(as('emp1'), 'companies/legacy/leadPhotos/L1'), { by: 'emp1', data: 'data:image/jpeg;base64,xx' })));
await t('employee CANNOT send a lead as someone else', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/leads/L3'), { by: 'emp2' })));
await t('employee reads own lead', assertSucceeds(getDoc(doc(as('emp1'), 'companies/legacy/leads/L1'))));
await t('employee lists own leads', assertSucceeds(getDocs(query(collection(as('emp1'), 'companies/legacy/leads'), where('by', '==', 'emp1')))));
await t('employee CANNOT read a coworker\'s lead', assertFails(getDoc(doc(as('emp1'), 'companies/legacy/leads/L2'))));
await t('employee CANNOT list all leads', assertFails(getDocs(collection(as('emp1'), 'companies/legacy/leads'))));
await t('coworker CANNOT see the lead photo', assertFails(getDoc(doc(as('emp2'), 'companies/legacy/leadPhotos/L1'))));
await t('owner lists all leads', assertSucceeds(getDocs(collection(as('owner1'), 'companies/legacy/leads'))));
await t('owner sees the lead photo', assertSucceeds(getDoc(doc(as('owner1'), 'companies/legacy/leadPhotos/L1'))));
await t('owner marks a lead handled', assertSucceeds(updateDoc(doc(as('owner1'), 'companies/legacy/leads/L1'), { status: 'done' })));
await t('employee CANNOT edit a lead after sending', assertFails(updateDoc(doc(as('emp1'), 'companies/legacy/leads/L1'), { reason: 'x' })));
await t('outsider CANNOT read leads', assertFails(getDocs(collection(as('outsider'), 'companies/legacy/leads'))));
const photo = (by, extra = {}) => ({ pinId: '1,1', by, data: 'data:image/jpeg;base64,xx', at: 1, ...extra });
await t('employee adds a house photo', assertSucceeds(setDoc(doc(as('emp1'), 'companies/legacy/pinPhotos/P1'), photo('emp1'))));
await t('coworker adds a house photo', assertSucceeds(setDoc(doc(as('emp2'), 'companies/legacy/pinPhotos/P2'), photo('emp2'))));
await t('coworker sees house photos', assertSucceeds(getDocs(query(collection(as('emp2'), 'companies/legacy/pinPhotos'), where('pinId', '==', '1,1')))));
await t('employee CANNOT add a photo as someone else', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/pinPhotos/P3'), photo('emp2'))));
await t('employee CANNOT add a photo with no pin', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/pinPhotos/P4'), { by: 'emp1', data: 'x' })));
await t('employee CANNOT add a giant photo', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/pinPhotos/P5'), photo('emp1', { data: 'x'.repeat(950000) }))));
await t('employee CANNOT edit a photo', assertFails(updateDoc(doc(as('emp1'), 'companies/legacy/pinPhotos/P1'), { data: 'y' })));
await t('employee CANNOT delete a coworker\'s photo', assertFails(deleteDoc(doc(as('emp1'), 'companies/legacy/pinPhotos/P2'))));
await t('employee deletes own photo', assertSucceeds(deleteDoc(doc(as('emp1'), 'companies/legacy/pinPhotos/P1'))));
await t('owner deletes any photo', assertSucceeds(deleteDoc(doc(as('owner1'), 'companies/legacy/pinPhotos/P2'))));
await t('outsider CANNOT see house photos', assertFails(getDocs(collection(as('outsider'), 'companies/legacy/pinPhotos'))));
await t('owner writes some other company data', assertSucceeds(setDoc(doc(as('owner1'), 'companies/legacy/misc/a'), { x: 1 })));
await t('employee CANNOT write other company data', assertFails(setDoc(doc(as('emp1'), 'companies/legacy/misc/b'), { x: 1 })));
await t('Doorline client CANNOT add hangers', assertFails(setDoc(doc(as('acmeowner'), 'companies/acme/pins/9,9'), { status: 'hanger' })));
await t('Doorline client CANNOT delete billed hangers', assertFails(deleteDoc(doc(as('acmeowner'), 'companies/acme/pins/7,7'))));
await t('Doorline client CANNOT change a hanger', assertFails(updateDoc(doc(as('acmeowner'), 'companies/acme/pins/7,7'), { status: 'none' })));
await t('Doorline client CANNOT delete shifts', assertFails(deleteDoc(doc(as('acmeowner'), 'companies/acme/shifts/s1'))));
await t('Doorline client still saves routes', assertSucceeds(setDoc(doc(as('acmeowner'), 'companies/acme/settings/areas'), { list: [] })));
await t('crew removes a pin they placed', assertSucceeds(deleteDoc(doc(as('crew1'), 'companies/acme/pins/7,7'))));
await t('crew CANNOT remove another crew member\'s pin', assertFails(deleteDoc(doc(as('crew1'), 'companies/acme/pins/8,8'))));
await t('admin removes any client pin', assertSucceeds(deleteDoc(doc(as('admin'), 'companies/acme/pins/8,8'))));

console.log('Removing people and deleting accounts');
await t('owner removes employee', assertSucceeds(deleteDoc(doc(as('owner1'), 'users/newemp'))));
await t('owner CANNOT remove another company\'s employee', assertFails(deleteDoc(doc(as('owner1'), 'users/pemp'))));
await t('employee CANNOT remove the owner', assertFails(deleteDoc(doc(as('emp1'), 'users/owner1'))));
await t('user deletes self (delete account / start over)', assertSucceeds(deleteDoc(doc(as('emp1'), 'users/emp1'))));
await t('owner deletes own company', assertSucceeds(deleteDoc(doc(as('outsider'), 'companies/other'))));
await t('removed employee CANNOT read pins', assertFails(getDocs(collection(as('emp1'), 'companies/legacy/pins'))));

console.log('Company admins (owner promotes employees)');
await env.withSecurityRulesDisabled(async ctx => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'companies/mco'), { name: 'Mgr Co', ownerId: 'mo', status: 'active' });
  for (const [u, role] of [['mo', 'owner'], ['mm', 'employee'], ['mm2', 'employee'], ['me1', 'employee'], ['me2', 'employee']]) await setDoc(doc(db, 'users/' + u), { name: u, role, companyId: 'mco' });
  await setDoc(doc(db, 'companies/mco/pins/5,5'), { status: 'hanger', createdBy: 'me1' });
  await setDoc(doc(db, 'companies/mco/leads/ML'), { by: 'me1', reason: 'roof' });
  await setDoc(doc(db, 'companies/mco/shifts/ms'), { userId: 'me1', hangers: 3 });
});
await t('employee CANNOT promote themselves', assertFails(updateDoc(doc(as('mm'), 'companies/mco'), { managers: ['mm'] })));
await t('owner makes an employee admin', assertSucceeds(updateDoc(doc(as('mo'), 'companies/mco'), { managers: ['mm', 'mm2'] })));
await t('admin CANNOT promote others', assertFails(updateDoc(doc(as('mm'), 'companies/mco'), { managers: ['mm', 'mm2', 'me1'] })));
await t('admin CANNOT change company settings', assertFails(updateDoc(doc(as('mm'), 'companies/mco'), { name: 'Mine now' })));
await t('admin reads every hot lead', assertSucceeds(getDocs(collection(as('mm'), 'companies/mco/leads'))));
await t('regular employee still CANNOT list all leads', assertFails(getDocs(collection(as('me2'), 'companies/mco/leads'))));
await t('admin marks a lead handled', assertSucceeds(updateDoc(doc(as('mm'), 'companies/mco/leads/ML'), { status: 'done' })));
await t('admin assigns neighborhoods', assertSucceeds(setDoc(doc(as('mm'), 'companies/mco/settings/areas'), { list: [] })));
await t('admin deletes a coworker\'s pin', assertSucceeds(deleteDoc(doc(as('mm'), 'companies/mco/pins/5,5'))));
await t('admin deletes a shift', assertSucceeds(deleteDoc(doc(as('mm'), 'companies/mco/shifts/ms'))));
await t('admin makes an invite', assertSucceeds(setDoc(doc(as('mm'), 'invites/MGRCODE1'), { companyId: 'mco', companyName: 'Mgr Co', createdBy: 'mm', expiresAt: Timestamp.fromMillis(Date.now() + 86400000) })));
await t('admin CANNOT remove another admin', assertFails(deleteDoc(doc(as('mm'), 'users/mm2'))));
await t('admin CANNOT remove the owner', assertFails(deleteDoc(doc(as('mm'), 'users/mo'))));
await t('admin removes an employee', assertSucceeds(deleteDoc(doc(as('mm'), 'users/me1'))));
await t('regular employee CANNOT remove anyone', assertFails(deleteDoc(doc(as('me2'), 'users/mm2'))));
await t('owner removes an admin', assertSucceeds(deleteDoc(doc(as('mo'), 'users/mm2'))));
await t('owner takes admin away', assertSucceeds(updateDoc(doc(as('mo'), 'companies/mco'), { managers: [] })));
await t('ex-admin CANNOT read all leads', assertFails(getDocs(collection(as('mm'), 'companies/mco/leads'))));
await t('ex-admin CANNOT delete pins', assertFails(deleteDoc(doc(as('mm'), 'companies/mco/pins/6,6'))));

console.log(`\n${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);
