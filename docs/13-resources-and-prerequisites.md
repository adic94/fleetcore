# Zasoby i warunki startu

Co musi być dostępne, żeby projekt ruszył i nie stanął w połowie.

## Warunki, bez których nie warto zaczynać

1. **Obsadzona rola decydenta zakresu.** Ktoś musi mówić „tego nie robimy" przy 478 kolumnach kartoteki. Nieobsadzenie tej roli jest częstszą przyczyną porażki takich projektów niż brak programistów.
2. **Pełny eksport danych ze źródeł — dane, nie szablony.** Znane są struktury 30 arkuszy importu; potrzebny jest wypełniony eksport bieżącego stanu.
3. **Czas praktyków na warsztaty.** Fleet manager, księgowa, dyspozytor.

Wszystko poniżej da się organizować równolegle. Te trzy — nie.

---

## Ludzie

### Zespół budujący

| Rola | Wymiar na fazy 0–1 | Uwagi |
| --- | --- | --- |
| Decydent zakresu / product owner | 0,3 etatu, stale | patrz wyżej |
| Programista full-stack TypeScript | 2 osoby | frontend + API |
| Programista backend / baza | 1 osoba | model danych, migracje, RLS |
| DevOps | 0,5 etatu | środowiska, wdrożenia, kopie zapasowe |
| Tester | 0,5 etatu | bramki, testy izolacji |
| **Wdrożeniowiec** | od pierwszego klienta zewnętrznego | audyty danych, mapowania importu, szkolenia, opieka powdrożeniowa — [onboarding](14-onboarding-klienta.md); przy kilku klientach naraz programiści nie robią wdrożeń |

Realistyczne minimum: **3–4 osoby**. Poniżej tego harmonogram 8–12 osobomiesięcy rozciąga się w czasie kalendarzowym tak, że wymagania zdążą się zmienić, zanim powstanie kod.

### Wiedza dziedzinowa — nie do kupienia u programistów

| Kto | Do czego | Kiedy |
| --- | --- | --- |
| Fleet manager | kartoteka, rejestry, przepływy floty | 2–4 h/tydzień, stale |
| Księgowa lub doradca podatkowy | dekretacja, VAT 50/100%, środki trwałe, JPK, KSeF | intensywnie w fazie 2 |
| Dyspozytor | przepływy zleceń transportowych | warsztat przed fazą 5 |
| Agent celny | tylko gdyby spedycja weszła w zakres | rekomendacja: nie wchodzi |

---

## Dane

### Do zdobycia

| Co | Skąd | Uwaga |
| --- | --- | --- |
| Eksport bieżących danych z systemu flotowego | dostawca lub administrator | **warunek startu fazy 1** |
| Eksport z pozostałych ewidencji | dostawcy | do scalenia i porównania |
| Dane kosztowe z systemu księgowego | księgowość | do weryfikacji dekretacji |
| Skany dokumentów pojazdów | własne | wejście do OCR |

> **Sprawdzić w umowach prawo do wydania własnych danych**, zanim wystąpi się o eksport. To bywa punkt sporny z dostawcą.

### Braki do uzupełnienia ręcznie

Praca człowieka z dokumentem w ręku. **Nie zniknie przez zmianę systemu** i trzeba ją zaplanować jako osobne zadanie, nie jako efekt uboczny migracji.

Na rzeczywistej flocie 217 pojazdów:

- **134 pojazdy** bez kompletu pól do wyliczenia podatku (117 bez DMC, 17 powyżej 12 t bez osi lub zawieszenia);
- **89 pozycji** na liście roboczej, posortowanej od najdroższych;
- **48 pojazdów** obecnych w dokumentacji, ale nie w bazie — do rozstrzygnięcia, co jest realną flotą, a co artefaktem dokumentacji;
- **26 pojazdów pod więcej niż jedną tablicą** — do wskazania numeru aktualnego;
- **rodzaj zawieszenia: zero wiarygodnych danych** — wszystkie rekordy mają tę samą wartość wpisaną hurtem, a polski dowód rejestracyjny nie ma na to pole rubryki.

---

## Dostępy i formalności o długich terminach

Uruchamiać najwcześniej — czas oczekiwania jest poza kontrolą zespołu.

| Co | Kiedy załatwić |
| --- | --- |
| **Wniosek o teletransmisję CEP** | **jako pierwsze**, niezależnie od fazy |
| Token lub certyfikat KSeF per spółka + środowisko testowe | przed fazą 2 |
| Dostęp do API telematyki + zgłoszenie o czas pracy z obrotów silnika | przed fazą 3 |
| Formaty plików od dostawców kart paliwowych | przed fazą 1 |
| Dostęp do zestawień e-TOLL | przed fazą 5 |
| Format wyciągów bankowych (MT940/CSV) | przed fazą 4 |
| Konfiguracja SSO w katalogu tożsamości | opcjonalne |

---

## Infrastruktura

### Na fazy 0–1 — minimum, nie stan docelowy

Architektura klastra opisana we [wdrożeniu](08-cluster-deployment.md) jest **celem, nie punktem startu**. Przy zespole 3–4 osób Kubernetes w fazie 1 to koszt bez korzyści.

Minimum na start:

- jeden serwer aplikacyjny — Docker Compose wystarczy;
- **PostgreSQL zarządzany** — tu nie oszczędzać; kopie zapasowe i odtworzenie do punktu w czasie są warte więcej niż cała reszta infrastruktury razem;
- magazyn obiektowy na dokumenty (S3 lub MinIO);
- Redis;
- magazyn sekretów;
- domena i certyfikaty;
- kopie zapasowe poza główną lokalizacją.

Przejście na klaster ma sens, gdy pojawi się drugi najemca zewnętrzny albo wymóg dostępności.

### Narzędziowa

- Repozytorium i CI. **Uwaga na budżet minut** — przy płatnym planie wyczerpuje się szybciej, niż się zakłada. Bramki uruchamiane lokalnie są pierwszą linią, CI drugą.
- Rejestr obrazów kontenerów.
- Środowiska: deweloperskie, testowe, produkcyjne.
- Monitoring, logi, alerty.

---

## Sprawy prawne

Najczęściej pomijana kategoria, a potrafi zatrzymać wdrożenie gotowego systemu.

- **Umowy powierzenia przetwarzania danych** między spółkami korzystającymi z jednego systemu.
- **Ocena skutków dla ochrony danych** — dane lokalizacyjne kierowców to monitoring pracowników; przy tej skali ocena jest prawdopodobnie wymagana.
- **Regulamin monitoringu GPS i informacja dla pracowników** — wymóg kodeksu pracy, niezależny od systemu.
- **Okresy wypowiedzenia umów** z dotychczasowymi dostawcami. Starego systemu nie wyłącza się w dniu uruchomienia nowego — trzeba policzyć okres pracy równoległej i jego koszt.
- **Produkt będzie sprzedawany klientom zewnętrznym** ([brief](01-project-brief.md)), więc przed pierwszym klientem potrzebne są: licencja, umowa, regulamin świadczenia usługi, polityka prywatności i umowa powierzenia przetwarzania danych z każdym klientem.

---

## Co jest już gotowe

Nie liczyć jako koszt — to skraca fazy 1 i 2.

| Zasób | Stan |
| --- | --- |
| Silnik podatkowy DT-1 | działa; zgodność z bazą produkcyjną 0,24%, różnice wyjaśnione |
| Stawki gminne | zweryfikowane 45/45 z uchwałą |
| Usługa OCR dowodów | parser geometryczny, 8–11 s/dokument, korekcja orientacji |
| Dekodowanie kodu Aztec | pełna ścieżka sprawdzona end-to-end, 17/17 pól |
| Importy kart paliwowych i telematyki | działają na realnych danych |
| Scalanie źródeł z rangami | działa na 907 pojazdach |
| Bramki testowe | ~19 plików, 154 asercje, ~20 s bez sieci |
| Struktury 30 arkuszy importu | mapa migracji danych |
| **Udokumentowane pułapki** | patrz [systemy odniesienia](12-source-systems.md) |

Ostatni wiersz bywa lekceważony, a jest wart najwięcej: każda pozycja to błąd, który kosztował już raz i drugi raz nie kosztuje.

---

## Pierwsze kroki

Kolejność, w której każdy krok zależy od poprzedniego tylko tam, gdzie musi:

1. Obsadzić rolę decydenta zakresu.
2. Złożyć wniosek o teletransmisję CEP — długi termin, przyda się w każdym wariancie.
3. Wystąpić o pełny eksport danych; wcześniej sprawdzić umowy.
4. Rozstrzygnąć założenia z [briefu](01-project-brief.md): praca offline (a z nią technologia aplikacji mobilnej) i lokalizacja danych. Sprzedaż na zewnątrz jest już rozstrzygnięta: tak.
5. Uruchomić fazę 0 — fundament z RLS i testem izolacji od pierwszego dnia.
6. Warsztat z fleet managerem: które z 478 kolumn są faktycznie używane.

Punkty 1–4 nie wymagają programisty i można je zacząć natychmiast.
