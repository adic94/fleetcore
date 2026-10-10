"""Usługa OCR dokumentów pojazdu — szkielet.

Do przeniesienia z TaxOrder Pro `ocr-service/` (docs/15-materialy-taxorder-pro.md):
kaskada Aztec → parser geometryczny → model wizyjny, korekcja orientacji strony,
bramki sanityzacji wyniku (identyfikator modelu i opis pola nie trafiają jako wartość).

Zasady (docs/03, docs/04):
- OCR nigdy nie jest na ścieżce synchronicznego żądania użytkownika — wywołuje go worker z kolejki;
- powód zejścia na niższą warstwę wraca w odpowiedzi (`fallback_reason`) i do logu;
- pole z jednostką inną niż oczekiwana jest odrzucane.
"""
from fastapi import FastAPI, UploadFile

app = FastAPI(title="FleetCore OCR", version="0.0.0")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/v1/registration-document")
async def registration_document(file: UploadFile) -> dict:
    # Szkielet: kaskada do przeniesienia z TaxOrder Pro.
    return {
        "layer": None,
        "fields": {},
        "fallback_reason": "not_implemented",
        "filename": file.filename,
    }
