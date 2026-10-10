import { useEffect, useState } from 'react';

type Health = { status: string; database: string };

// Szkielet panelu. Ekrany do zbudowania: docs/02-product-functional-spec.md, „Ekrany główne".
// Siatki: TanStack Table z konfiguracją kolumn z core.report_definitions; dane: TanStack Query.
export function App() {
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch('/v1/health')
      .then((r) => r.json() as Promise<Health>)
      .then(setHealth)
      .catch((e: unknown) => setError(String(e)));
  }, []);

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 720, margin: '48px auto', padding: '0 16px' }}>
      <h1>FleetCore</h1>
      <p>Szkielet panelu — faza 0.</p>
      <h2>Stan API</h2>
      {error && <p role="alert">API niedostępne: {error}</p>}
      {!error && !health && <p>Sprawdzam…</p>}
      {health && (
        <p>
          API: <strong>{health.status}</strong>, baza: <strong>{health.database}</strong>
        </p>
      )}
    </main>
  );
}
