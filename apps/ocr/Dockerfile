FROM python:3.12-slim

# Biblioteka OCR ciągnie wariant pakietu wizyjnego wymagający bibliotek graficznych systemu.
# Bez libgl i glib kontener startuje i pada przy pierwszym imporcie (docs/08, „Obraz OCR").
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

# Akcelerator obliczeń potrafi wywrócić proces twardo zamiast zwrócić błąd — wyłączony jawnie.
ENV OCR_ACCELERATOR=off

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
