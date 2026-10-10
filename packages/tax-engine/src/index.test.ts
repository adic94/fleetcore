// Bramka `tax-rates` — zalążek. Każdy test opisuje błąd zmierzony w TaxOrder Pro
// albo regułę z docs/02. Stawki poniżej są PRZYKŁADOWE (nie z uchwały) — prawdziwe stawki
// trafiają do packages/rates z uchwały gminy, z weryfikacją pozycja po pozycji.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { selectRate, annualAmount, type Rate, type VehicleTaxInput } from './index.ts';

const base: VehicleTaxInput = { kind: 'truck', dmcKg: null, comboDmcKg: null, axles: null, suspension: null, seats: null };
const r = (p: Partial<Rate> & Pick<Rate, 'id' | 'vehicleKind' | 'amountPln'>): Rate => ({
  categoryCode: `D${p.id}`, massBasis: null, dmcMinKg: null, dmcMaxKg: null, axlesMin: null, axlesMax: null,
  suspension: null, seatsMin: null, seatsMax: null, ...p,
});

const RATES: Rate[] = [
  r({ id: 1, vehicleKind: 'truck', massBasis: 'vehicle', dmcMinKg: 3_500.01, dmcMaxKg: 5_500.01, amountPln: 900 }),
  r({ id: 2, vehicleKind: 'truck', massBasis: 'vehicle', dmcMinKg: 5_500.01, dmcMaxKg: 12_000, amountPln: 1_200 }),
  r({ id: 3, vehicleKind: 'truck', massBasis: 'vehicle', dmcMinKg: 12_000, dmcMaxKg: 15_000, axlesMin: 2, axlesMax: 2, suspension: 'pneumatic', amountPln: 2_000 }),
  r({ id: 4, vehicleKind: 'truck', massBasis: 'vehicle', dmcMinKg: 12_000, dmcMaxKg: 15_000, axlesMin: 2, axlesMax: 2, suspension: 'other', amountPln: 2_300 }),
  r({ id: 5, vehicleKind: 'truck', massBasis: 'vehicle', dmcMinKg: 12_000, dmcMaxKg: 15_000, axlesMin: 3, axlesMax: 3, suspension: 'pneumatic', amountPln: 2_600 }),
  r({ id: 6, vehicleKind: 'trailer', massBasis: 'combination', dmcMinKg: 7_000, dmcMaxKg: 12_000, amountPln: 700 }),
  r({ id: 7, vehicleKind: 'bus', seatsMin: 0, seatsMax: 21, amountPln: 1_500 }),
  r({ id: 8, vehicleKind: 'bus', seatsMin: 22, seatsMax: null, amountPln: 2_500 }),
];

test('TaxOrder Pro: brak liczby osi od 12 t NIE staje się dwójką — wyliczenie blokowane', () => {
  // W TaxOrder Pro: `parseInt(v.osie) || 2` → najniższa stawka w przedziale, deklaracja zaniżona.
  const res = selectRate({ ...base, dmcKg: 13_000, suspension: 'pneumatic' }, RATES);
  assert.deepEqual(res, { status: 'blocked', blockingFields: ['axles'] });
});

test('od 12 t stawka zależy też od zawieszenia — brak zawieszenia blokuje', () => {
  const res = selectRate({ ...base, dmcKg: 13_000, axles: 2 }, RATES);
  assert.deepEqual(res, { status: 'blocked', blockingFields: ['suspension'] });
});

test('od 12 t: ta sama liczba osi, inne zawieszenie = inna stawka', () => {
  const pneu = selectRate({ ...base, dmcKg: 13_000, axles: 2, suspension: 'pneumatic' }, RATES);
  const other = selectRate({ ...base, dmcKg: 13_000, axles: 2, suspension: 'other' }, RATES);
  assert.equal(pneu.status === 'ok' && pneu.rate.id, 3);
  assert.equal(other.status === 'ok' && other.rate.id, 4);
});

test('poniżej 12 t liczba osi i zawieszenie NIE blokują (braki formalne ≠ braki blokujące)', () => {
  const res = selectRate({ ...base, dmcKg: 7_500 }, RATES);
  assert.equal(res.status === 'ok' && res.rate.id, 2);
});

test('DMC 0 to brak danych — import zamienia je na null, a null blokuje', () => {
  const res = selectRate({ ...base, dmcKg: null }, RATES);
  assert.deepEqual(res, { status: 'blocked', blockingFields: ['dmcKg'] });
});

test('ciężarowy do 3,5 t nie podlega podatkowi', () => {
  assert.equal(selectRate({ ...base, dmcKg: 3_500 }, RATES).status, 'not_taxable');
});

test('przyczepa liczona od DMC zespołu; poniżej 7 t łącznie nie podlega', () => {
  assert.equal(selectRate({ ...base, kind: 'trailer', comboDmcKg: 6_500 }, RATES).status, 'not_taxable');
  const res = selectRate({ ...base, kind: 'trailer', comboDmcKg: 9_000 }, RATES);
  assert.equal(res.status === 'ok' && res.rate.id, 6);
});

test('przyczepa bez DMC zespołu jest blokowana, nie liczona z własnej DMC', () => {
  const res = selectRate({ ...base, kind: 'trailer', dmcKg: 9_000 }, RATES);
  assert.deepEqual(res, { status: 'blocked', blockingFields: ['comboDmcKg'] });
});

test('autobus liczony od liczby miejsc; brak liczby miejsc blokuje', () => {
  assert.deepEqual(selectRate({ ...base, kind: 'bus' }, RATES), { status: 'blocked', blockingFields: ['seats'] });
  const res = selectRate({ ...base, kind: 'bus', seats: 30 }, RATES);
  assert.equal(res.status === 'ok' && res.rate.id, 8);
});

test('pojazd specjalny zwolniony niezależnie od pozostałych parametrów', () => {
  assert.equal(selectRate({ ...base, kind: 'special', dmcKg: 20_000 }, RATES).status, 'exempt');
});

test('brak pasującej pozycji w uchwale = brak wyliczenia, nie „pierwsza z listy"', () => {
  const res = selectRate({ ...base, dmcKg: 20_000, axles: 4, suspension: 'other' }, RATES);
  assert.deepEqual(res, { status: 'ambiguous', rateIds: [] });
});

test('należność za miesiące posiadania: sprzedany w maju = 5 miesięcy', () => {
  assert.equal(annualAmount(RATES[1], 5), 500);
  assert.throws(() => annualAmount(RATES[1], 0), RangeError);
});
