// Silnik DT-1 — dobór stawki z uchwały gminy.
//
// Reguły: docs/02-product-functional-spec.md („Moduł Podatki") i docs/05-data-model-and-analytics.md
// („Cicha zaniżona stawka"). Najważniejsza zasada: BRAK DANEJ NIE MA WARTOŚCI DOMYŚLNEJ.
// TaxOrder Pro miał `parseInt(v.osie) || 2` — brak liczby osi cicho stawał się dwójką,
// czyli najniższą stawką w przedziale. Tutaj brak danej daje status `blocked` z listą pól.
//
// Ten pakiet jest punktem startowym do przeniesienia silnika z TaxOrder Pro
// (docs/15-materialy-taxorder-pro.md). Przenoszone kategorie muszą przejść te same testy.

export type VehicleKind = 'truck' | 'tractor' | 'trailer' | 'bus' | 'special' | 'passenger' | 'other';
export type Suspension = 'pneumatic' | 'other';

export interface VehicleTaxInput {
  kind: VehicleKind | null;
  /** DMC pojazdu w kg; null = brak danych (NIGDY 0 jako brak). */
  dmcKg: number | null;
  /** DMC zespołu (ciągnik + naczepa, przyczepa + pojazd silnikowy) w kg. */
  comboDmcKg: number | null;
  axles: number | null;
  suspension: Suspension | null;
  /** Miejsca do siedzenia poza miejscem kierowcy — tylko autobusy. */
  seats: number | null;
}

export interface Rate {
  id: number;
  categoryCode: string;
  vehicleKind: 'truck' | 'tractor' | 'trailer' | 'bus';
  massBasis: 'vehicle' | 'combination' | null;
  dmcMinKg: number | null; // przedział [min, max)
  dmcMaxKg: number | null;
  axlesMin: number | null;
  axlesMax: number | null;
  suspension: Suspension | null;
  seatsMin: number | null;
  seatsMax: number | null;
  amountPln: number;
}

export type RateResult =
  | { status: 'not_taxable'; reason: string }
  | { status: 'exempt'; reason: string }
  | { status: 'blocked'; blockingFields: (keyof VehicleTaxInput)[] }
  | { status: 'ambiguous'; rateIds: number[] }
  | { status: 'ok'; rate: Rate };

const T12 = 12_000;

/** Progi opodatkowania: ustawa o podatkach i opłatach lokalnych, art. 8 (do potwierdzenia z doradcą). */
function taxability(v: VehicleTaxInput): RateResult | { mass: number; basis: 'vehicle' | 'combination' } {
  switch (v.kind) {
    case null:
      return { status: 'blocked', blockingFields: ['kind'] };
    case 'special':
      // Guard w silniku, nie w prezentacji (docs/02).
      return { status: 'exempt', reason: 'special_vehicle' };
    case 'passenger':
    case 'other':
      return { status: 'not_taxable', reason: 'kind' };
    case 'bus':
      return { mass: 0, basis: 'vehicle' };
    case 'truck':
      if (v.dmcKg == null) return { status: 'blocked', blockingFields: ['dmcKg'] };
      if (v.dmcKg <= 3_500) return { status: 'not_taxable', reason: 'dmc_up_to_3_5t' };
      return { mass: v.dmcKg, basis: 'vehicle' };
    case 'tractor':
      if (v.comboDmcKg == null) return { status: 'blocked', blockingFields: ['comboDmcKg'] };
      if (v.comboDmcKg < 3_500) return { status: 'not_taxable', reason: 'combo_below_3_5t' };
      return { mass: v.comboDmcKg, basis: 'combination' };
    case 'trailer':
      if (v.comboDmcKg == null) return { status: 'blocked', blockingFields: ['comboDmcKg'] };
      if (v.comboDmcKg < 7_000) return { status: 'not_taxable', reason: 'combo_below_7t' };
      return { mass: v.comboDmcKg, basis: 'combination' };
  }
}

const inRange = (x: number, min: number | null, max: number | null) =>
  (min == null || x >= min) && (max == null || x < max);

export function selectRate(v: VehicleTaxInput, rates: Rate[]): RateResult {
  const t = taxability(v);
  if ('status' in t) return t;

  // Braki blokujące — TYLKO pola, które silnik przy tym tonażu faktycznie czyta.
  const blocking: (keyof VehicleTaxInput)[] = [];
  if (v.kind === 'bus') {
    if (v.seats == null) blocking.push('seats');
  } else if (t.mass >= T12) {
    if (v.axles == null) blocking.push('axles');
    if (v.suspension == null) blocking.push('suspension');
  }
  if (blocking.length) return { status: 'blocked', blockingFields: blocking };

  const matches = rates.filter(
    (r) =>
      r.vehicleKind === v.kind &&
      (v.kind === 'bus'
        ? inRange(v.seats!, r.seatsMin, r.seatsMax === null ? null : r.seatsMax + 1)
        : (r.massBasis === null || r.massBasis === t.basis) &&
          inRange(t.mass, r.dmcMinKg, r.dmcMaxKg) &&
          (t.mass < T12 ||
            (inRange(v.axles!, r.axlesMin, r.axlesMax === null ? null : r.axlesMax + 1) &&
              r.suspension === v.suspension))),
  );

  // Zero albo więcej niż jedna pasująca pozycja = brak wyliczenia, nigdy „pierwsza z listy".
  if (matches.length === 0) return { status: 'ambiguous', rateIds: [] };
  if (matches.length > 1) return { status: 'ambiguous', rateIds: matches.map((r) => r.id) };
  return { status: 'ok', rate: matches[0] };
}

/** Należność za rok: stawka × miesiące posiadania / 12, zaokrąglona do pełnych złotych. */
export function annualAmount(rate: Rate, monthsOwned: number): number {
  if (!Number.isInteger(monthsOwned) || monthsOwned < 1 || monthsOwned > 12) {
    throw new RangeError(`monthsOwned poza zakresem 1..12: ${monthsOwned}`);
  }
  return Math.round((rate.amountPln * monthsOwned) / 12);
}
