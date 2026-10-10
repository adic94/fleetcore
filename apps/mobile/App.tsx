import { SafeAreaView, Text, StyleSheet } from 'react-native';

// Aplikacja kierowcy i fleet managera w terenie (iOS, Android) — faza 3, docs/07-roadmap.md.
//
// Architektura offline-first (docs/01, „Platformy"; docs/03, „Założenia do potwierdzenia"):
//  - lokalna baza expo-sqlite z kolejką zapisów;
//  - każdy zapis ma client_uuid (fleet.protocols.client_uuid) i nagłówek Idempotency-Key,
//    więc ponowiona synchronizacja nie tworzy duplikatu protokołu;
//  - zdjęcia zapisywane lokalnie, wysyłane po odzyskaniu zasięgu;
//  - typy i klient API z packages/contracts (wspólne z panelem).
//
// Bundle ID `pl.fleetcore.app` jest roboczy — do zmiany po wyborze nazwy produktu,
// PRZED pierwszą publikacją w App Store / Google Play (potem nie da się go zmienić).
export default function App() {
  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>FleetCore</Text>
      <Text>Szkielet aplikacji mobilnej — protokoły, licznik, szkody (faza 3).</Text>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16 },
  title: { fontSize: 24, fontWeight: '600', marginBottom: 8 },
});
