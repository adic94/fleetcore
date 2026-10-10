# Wdrożenie na klaster Kubernetes

## Założenie wyjściowe

Docelowo jeden klaster, cztery środowiska w osobnych przestrzeniach nazw: `fleetcore-dev`, `fleetcore-stage`, `fleetcore-demo`, `fleetcore-prod`. `demo` ma **osobną bazę i osobny magazyn plików** — nigdy wspólnych z produkcją ([onboarding](14-onboarding-klienta.md)). Baza danych i magazyn obiektowy **poza klastrem** — jako usługi zarządzane albo dedykowane maszyny.

Powód wyniesienia bazy: odtworzenie do punktu w czasie, kopie zapasowe i strojenie PostgreSQL to osobna dziedzina. Uruchomienie bazy w klastrze dokłada operator bazodanowy do listy rzeczy, które mogą paść w nocy, i nie daje nic w zamian przy tej skali.

## Komponenty

| Komponent | Typ | Repliki (prod) | Uwagi |
| --- | --- | --- | --- |
| `api` | Deployment | 3 | NestJS, bezstanowy |
| `web` | Deployment | 2 | statyczny frontend za CDN |
| `worker` | Deployment | 2 | importy, ponowienia, przypomnienia |
| `ocr` | Deployment | 1–4 | Python, autoskalowanie po kolejce |
| `redis` | StatefulSet | 1 + repliki | kolejki i cache |
| `postgres` | poza klastrem | — | usługa zarządzana |
| `minio` / S3 | poza klastrem | — | dokumenty |

## Osobna pula dla OCR

OCR ma inny profil zasobowy niż reszta: długi czas wykonania, wysokie zużycie procesora, brak ruchu przychodzącego. Trafia na osobną pulę węzłów z `nodeSelector` i tolerancją skazy, żeby przebieg wsadowy na tysiącu dokumentów nie zabrał procesora obsłudze zapytań użytkowników.

> **Liczba z doświadczenia, nie z szacunku.** Przetworzenie jednego dowodu rejestracyjnego to **8–11 sekund** po optymalizacji (wcześniej 30–80 s). To wyklucza OCR na ścieżce synchronicznego żądania — przebieg jest zadaniem w kolejce, nie odpowiedzią na kliknięcie.
>
> Druga rzecz, która kosztowała dzień diagnozy: **akcelerator obliczeń potrafi wywrócić proces twardo**, a nie zwrócić błąd. Dwie różne wersje biblioteki dały dwie różne awarie — błąd konwersji atrybutów i wyjątek zmiennoprzecinkowy wewnątrz konwolucji. Naprawa nie leżała w wyborze wersji, tylko w wyłączeniu akceleratora. Obraz OCR ma to ustawienie przypięte jawnie, z komentarzem dlaczego.

## Obraz OCR — zależności systemowe

Biblioteka OCR ciągnie wariant pakietu wizyjnego wymagający bibliotek graficznych systemu. Bez nich kontener startuje i pada przy pierwszym imporcie, komunikatem o brakującej bibliotece współdzielonej. Obraz bazowy musi zawierać biblioteki `libgl` i `glib`.

To trywialna rzecz, która zabiera pół dnia, jeśli się o niej nie wie.

## Sekrety

Sekrety **nie mieszkają w repozytorium ani w obrazie**. Magazyn zewnętrzny (Vault lub magazyn dostawcy chmury), wstrzykiwane przez operator sekretów jako zmienne środowiskowe.

Lista sekretów: poświadczenia bazy, klucz szyfrowania tokenów integracji, poświadczenia KSeF per najemca, klucze telematyki, dostęp do magazynu obiektowego, sekret podpisywania sesji.

> **Pułapka narzędziowa, zmierzona.** Ustawiona zmienna środowiskowa z tokenem API potrafi **przesłonić interaktywne logowanie** narzędzia wdrożeniowego, także po świeżym zalogowaniu. Objaw to błąd uwierzytelnienia wyglądający na wygasłą sesję, który wysyła w ślepy zaułek — ponowne logowanie niczego nie naprawia, dopóki zmienna jest ustawiona.
>
> Gorszy wariant: nowsze wersje narzędzia **same czytają plik środowiskowy z katalogu projektu**, więc sama obecność tokenu w tym pliku wystarczy — żaden proces nie musi go świadomie wczytywać. Skrypty wdrożeniowe usuwają tę zmienną ze środowiska podprocesów i ostrzegają, gdy ją wykryją.

## Migracje bazy

Migracje uruchamia zadanie `pre-install`/`pre-upgrade` wykresu Helm, **nie aplikacja przy starcie**. Aplikacja startująca migracje w trzech replikach jednocześnie to wyścig.

Zasady wyniesione z bolesnego doświadczenia:

1. **Nigdy nie uruchamiać automatycznie plików wycofujących zmiany.** W systemie odniesienia nocne zadanie brało wzorzec `schema_v*.sql`, który dopasowywał **także pliki wycofania** — a leksykograficznie każdy trafiał tuż po swojej migracji. Baza co noc tworzyła tabele i natychmiast je kasowała. Zadanie kończyło się kodem sukcesu.
2. **Sortowanie musi być numeryczne, nie leksykograficzne.** Inaczej `v2` wykonuje się po `v19`.
3. **Błąd to błąd, nie „już wykonane".** Zrównanie realnej awarii z powtórzeniem sprawia, że zadanie zawsze świeci na zielono.
4. **Migracja jest transakcyjna per plik.** Jeden błędny krok wycofuje **cały** plik — więc próba dodania istniejącej już kolumny zabiera ze sobą wszystkie tabele tworzone w tym samym pliku, cicho.
5. **Bramka porównująca stan bazy z repozytorium.** Bez niej rozjazd schematu wychodzi dopiero przy błędzie użytkownika.

Punkt 4 kosztował w systemie odniesienia pięć nieistniejących tabel i kilka funkcji, które działały jak „ciche zera" — użytkownik dostawał wiarygodnie wyglądające zero zamiast błędu.

## Observability

- Metryki: Prometheus, Grafana. Poza technicznymi także **domenowe**: liczba dokumentów w kolejce OCR, wiek najstarszej pozycji kolejki KSeF, liczba pojazdów z brakami blokującymi wyliczenie podatku.
- Logi: Loki, ustrukturyzowane JSON, z identyfikatorem najemca i identyfikatorem żądania. **Bez danych osobowych w logach.**
- Ślady: OpenTelemetry na ścieżkach integracji.

Alerty, które faktycznie coś znaczą:

| Alert | Próg | Dlaczego |
| --- | --- | --- |
| Kolejka KSeF rośnie | > 50 pozycji lub najstarsza > 24 h | integracja padła, faktury nie wychodzą |
| Kaskada OCR schodzi na najniższą warstwę | > 20% w godzinie | wyższa warstwa padła — dane są gorsze, ale błędu nie ma |
| Odmowy dostępu między najemcami | jakakolwiek | próba lub błąd uprawnień |
| Eksport dużego zbioru | > 10 000 wierszy | zdarzenie bezpieczeństwa |
| Opóźnienie odświeżenia widoków TCO | > 26 h | raporty pokazują wczorajszy stan bez ostrzeżenia |

Drugi wiersz to bezpośredni wniosek z incydentu: cicha kaskada objawiała się jako gorsze dane, nie jako awaria.

## CI/CD

    commit → testy jednostkowe i bramki → build obrazu → dev
           → testy E2E → stage → zatwierdzenie → prod

Argo CD synchronizuje stan z repozytorium konfiguracji. Wdrożenie produkcyjne wymaga zatwierdzenia człowieka.

**Bramki uruchamiane lokalnie przed wysłaniem** — nie tylko w CI. Uzasadnienie jest przyziemne: minuty w usłudze CI bywają wyczerpane w połowie miesiąca, a wtedy bramki lokalne są całą siecią bezpieczeństwa.

> **Lista bramek nie może żyć w dwóch miejscach.** W systemie odniesienia istniała równolegle w konfiguracji pakietu i w opisie przepływu CI, po czym cicho się rozjechała: z 13 bramek uruchamiały się 3, a całość wyglądała na zieloną. Runner czyta katalog testów i **sprawdza spójność w obie strony** — plik testowy nieobecny w konfiguracji CI to porażka, tak samo krok CI wskazujący na nieistniejący plik.

## Plan odtworzenia

| Parametr | Cel |
| --- | --- |
| Czas odtworzenia | 4 h |
| Dopuszczalna utrata danych | 15 min |
| Próbne odtworzenie | raz na kwartał, z protokołem |

Odtworzenie obejmuje bazę **i** magazyn dokumentów. Baza bez skanów dowodów i polis nie pozwala odtworzyć danych podatkowych.

## Zmienne środowiskowe

Wartości oznaczone `_REF` to odwołania do magazynu sekretów, nie same sekrety.

### `api` i `worker`

```text
NODE_ENV=production
DATABASE_URL_REF=...              # rola aplikacji, BEZ BYPASSRLS
DATABASE_MAINT_URL_REF=...        # tylko worker: rola do odświeżania widoków i retencji
REDIS_URL=redis://redis:6379
S3_ENDPOINT=https://...
S3_BUCKET_DOCUMENTS=fleetcore-documents
S3_CREDENTIALS_REF=...
SESSION_SECRET_REF=...
TOKEN_ENCRYPTION_KEY_REF=...      # szyfrowanie tokenów integracji
OCR_SERVICE_URL=http://ocr:8000
KSEF_BASE_URL=https://api-test.ksef.mf.gov.pl/v2   # per środowisko
MODULE_ENFORCEMENT=off            # włączane świadomie, patrz projekt bazy
PUBLIC_APP_URL=https://app.example.pl
```

### `ocr`

```text
OCR_ACCELERATOR=off               # przypięte jawnie, patrz „Osobna pula dla OCR"
OCR_MAX_CONCURRENCY=2
```

Poświadczenia KSeF i telematyki są **per najemca** i nie są zmiennymi środowiskowymi — siedzą zaszyfrowane w bazie, kluczem z `TOKEN_ENCRYPTION_KEY_REF`.

## Lista kontrolna pierwszego wdrożenia

1. Zarządzany PostgreSQL 16 z odtwarzaniem do punktu w czasie; rozszerzenie `btree_gist`.
2. Role bazodanowe: właściciel schematu (migracje), aplikacja (bez `BYPASSRLS`), konserwacja (odświeżanie widoków, retencja).
3. Magazyn obiektowy z wersjonowaniem i kopią poza główną lokalizacją.
4. Magazyn sekretów i operator sekretów.
5. Ingress, TLS, nagłówki bezpieczeństwa.
6. Migracje jako zadanie `pre-install`/`pre-upgrade`; bramka `schema-diff` zielona.
7. Wdrożenie `api`, `worker`, `web`, `ocr`.
8. Test izolacji najemców na środowisku docelowym.
9. Monitoring i alerty z tabeli wyżej, w tym domenowe.
10. Próbne odtworzenie z kopii przed wpuszczeniem pierwszych danych produkcyjnych.
11. Utworzenie pierwszej spółki, modułów i użytkowników.
