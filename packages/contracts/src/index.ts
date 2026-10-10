// Typy wspólne dla API, panelu i aplikacji mobilnej.
// Docelowo GENEROWANE z kontraktu OpenAPI API (docs/03: „kontrakt generowany, nie pisany ręcznie").
// Do czasu generatora — ręcznie, tylko to, czego używa szkielet.

/** Statusy pochodzą z jednego miejsca — CHECK w bazie i etykiety w UI z tej samej listy (docs/02, Rent). */
export const VEHICLE_STATUSES = ['active', 'sold', 'scrapped', 'reserve', 'leased_out'] as const;
export type VehicleStatus = (typeof VEHICLE_STATUSES)[number];

export const EVENT_KINDS = [
  'refuel', 'service', 'repair', 'inspection', 'damage', 'fine', 'lease_payment',
  'insurance', 'odometer', 'handover', 'return', 'trip', 'assignment', 'toll', 'other',
] as const;
export type EventKind = (typeof EVENT_KINDS)[number];

export interface Vehicle {
  id: number;
  company_id: number;
  vin: string | null;
  plate: string;
  brand: string | null;
  model: string | null;
  kind: string | null;
  /** null = brak danych; NIGDY 0 jako brak (docs/05, „Zero to brak danych"). */
  dmc_kg: string | null;
  axles_count: number | null;
  suspension_type: 'pneumatic' | 'other' | null;
  status: VehicleStatus;
}

export interface FleetEvent {
  id: number;
  company_id: number;
  kind: EventKind;
  occurred_at: string;
  vehicle_id: number | null;
  employee_id: number | null;
  /** Kwoty jako string z NUMERIC — bez typu zmiennoprzecinkowego w obliczeniach. */
  amount_net: string | null;
  amount_gross: string | null;
  vat_amount: string | null;
  currency: string;
  source: string;
  external_ref: string | null;
  payload: Record<string, unknown>;
}
