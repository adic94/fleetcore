# FleetCore — indeks dokumentacji

Dokumentacja koncepcyjna, produktowa i techniczna systemu zarządzania flotą.

## Szybka ścieżka czytania

### Zaczynasz od zera — przeczytaj w tej kolejności

1. [Założenia projektu](01-project-brief.md) — po co to powstaje i co znaczy sukces
2. [Systemy odniesienia](12-source-systems.md) — skąd wzięły się wymagania
3. [Opis produktu](02-product-functional-spec.md) — moduły i przepływy
4. [Architektura](03-architecture-and-stack.md) — jak to zbudować
5. [Projekt bazy danych](10-database-design.md) — model danych

### Zaczynasz kodować

0. [Materiały z TaxOrder Pro](15-materialy-taxorder-pro.md) — co przejmujemy z poprzedniego systemu i gdzie to leży
1. [Architektura i stack](03-architecture-and-stack.md)
2. [Struktura repozytorium](09-repository-structure.md)
3. [Projekt bazy danych](10-database-design.md) + [ERD](11-postgresql-erd-diagrams.md)
4. [Roadmapa](07-roadmap.md) — co powstaje najpierw i dlaczego akurat to

### Robisz integracje

0. [Platforma integracji](16-platforma-integracji.md) — wspólny rdzeń: pliki, API publiczne, webhooki, konektory
1. [Integracje API](04-api-integrations.md) — **przeczytaj w całości przed pierwszym wywołaniem**
2. [Model danych](05-data-model-and-analytics.md) — rozdział o pochodzeniu danych
3. [Bezpieczeństwo](06-security-privacy-compliance.md) — sekrety i ślad audytowy

### Wdrażasz klienta

1. [Onboarding klienta](14-onboarding-klienta.md) — demo przed umową, audyt po umowie, etapy, kryterium odbioru
2. [Model danych](05-data-model-and-analytics.md) — pochodzenie pól i braki blokujące

### Wdrażasz infrastrukturę

1. [Wdrożenie na klaster](08-cluster-deployment.md)
2. [Bezpieczeństwo](06-security-privacy-compliance.md)
3. [Zasoby i warunki startu](13-resources-and-prerequisites.md)

## Dokumenty

| Plik | Cel |
| --- | --- |
| `01-project-brief.md` | Problem, wizja, zakres, kryteria sukcesu, świadome wykluczenia |
| `02-product-functional-spec.md` | Moduły, role, ekrany, przepływy pracy |
| `03-architecture-and-stack.md` | Komponenty, technologie, decyzje architektoniczne i odrzucone alternatywy |
| `04-api-integrations.md` | KSeF, CEPiK, karty paliwowe, telematyka, e-TOLL, banki, OCR |
| `05-data-model-and-analytics.md` | Model zdarzeń, pochodzenie danych, TCO, wskaźniki |
| `06-security-privacy-compliance.md` | RODO, izolacja najemców, retencja, ślad audytowy |
| `07-roadmap.md` | Fazy, kryteria przejścia, ryzyka harmonogramu |
| `08-cluster-deployment.md` | Kubernetes, Helm, sekrety, observability, CI/CD, migracje |
| `09-repository-structure.md` | Układ kodu, granice modułów, bramki testowe |
| `10-database-design.md` | Schematy, tabele, klucze, polityki RLS |
| `11-postgresql-erd-diagrams.md` | Diagramy ERD |
| `12-source-systems.md` | Analiza systemów odniesienia oraz systemów, na których firma pracuje dziś (ZSI, MyCar, ORLEN) |
| `13-resources-and-prerequisites.md` | Ludzie, dane, dostępy, formalności, warunki startu |
| `14-onboarding-klienta.md` | Demo przed umową, audyt danych po umowie, wdrożenie klienta, ścieżki migracji, odejście klienta |
| `15-materialy-taxorder-pro.md` | Co przekazujemy z TaxOrder Pro: repozytorium, dane, co czytać, czego nie kopiować, lista kontrolna przekazania |
| `16-platforma-integracji.md` | Import i eksport plików, API publiczne dla CRM/CFM/ERP i integratorów, webhooki, konektory, ZSI przez eksport |

## Jak czytać ostrzeżenia w tej dokumentacji

Dokumenty zawierają bloki oznaczone symbolem ostrzeżenia. **To nie są dobre praktyki przepisane z podręcznika.** Każdy opisuje błąd, który wystąpił w rzeczywistym systemie produkcyjnym, został zmierzony i kosztował czas.

Przykłady tej klasy, rozwinięte w odpowiednich dokumentach:

- API, które **ignoruje nieznany parametr** zamiast go odrzucić, zwraca poprawnie wyglądający rekord innego pojazdu ([integracje](04-api-integrations.md));
- pole podatkowe z **wartością domyślną** daje deklarację z zaniżoną stawką, która wygląda poprawnie ([model danych](05-data-model-and-analytics.md));
- **odwrócona orientacja strony** w OCR daje wartość z sąsiedniej rubryki, mieszczącą się w dopuszczalnym zakresie ([integracje](04-api-integrations.md));
- **dwie kopie tej samej tablicy stałych** rozjeżdżają się nie tylko ze sobą, ale i z danymi ([model danych](05-data-model-and-analytics.md));
- glob w zadaniu migracyjnym dopasowujący **pliki wycofujące zmiany** kasuje tabele co noc, kończąc się kodem sukcesu ([wdrożenie](08-cluster-deployment.md)).

Wspólny mianownik: **wszystkie objawiają się jako wiarygodnie wyglądające dane, nie jako błąd.** Dlatego są w dokumentacji, a nie w komentarzach w kodzie.

## Najważniejsze założenie produktu

FleetCore nie jest kolejnym programem do floty. Jest **jednym rejestrem zdarzeń pojazdu**, z którego wynikają koszt, dekret, deklaracja i raport — zamiast kilku baz, w których ten sam pojazd i ta sama faktura żyją osobno.
