# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projekt

SQL-Business-Analyse der Northwind-Datenbank (SQLite). Kein Build, keine Tests. Git-Repository: github.com/hibalakhdioui22-lang/northwind-analyse (öffentlich; `*.db` ist ausgeschlossen). Die Arbeit besteht aus SQL-Abfragen in `sql/`, die gegen eine Datenbank in `data/` laufen. Kommunikation mit der Nutzerin auf Deutsch.

## Befehle

Umgebung: Windows, PowerShell 5.1. `sqlite3` liegt unter `C:\sqlite\sqlite3.exe` und ist im PATH. `python` ist nur der Microsoft-Store-Platzhalter und funktioniert nicht. Python 3.14 läuft über die Projektumgebung `.venv` (Pakete: `requirements.txt`).

Smart App Control ist aktiv und blockiert unbekannte Binärdateien. Deshalb `jupyter.exe`/`jupyter-nbconvert.exe` nicht direkt aufrufen, sondern über `python -m`. pandas 3.1.0 wird blockiert, deshalb ist pandas 2.3.3 fest eingetragen.

```powershell
# Dashboard starten (http://localhost:8501); Smoke-Test ohne Browser: streamlit.testing.v1.AppTest
.\.venv\Scripts\python.exe -m streamlit run app.py

# Notebook ausführen (schreibt Ausgaben ins Notebook und PNGs nach images/)
.\.venv\Scripts\python.exe -m nbconvert --to notebook --execute --inplace notebooks\01_analyse.ipynb
```

```powershell
# Eine Analyse ausführen
sqlite3 -bail -header -column data/northwind_full.db ".read sql/01_umsatzentwicklung.sql"

# Alle Analysen nacheinander prüfen (Exit-Code != 0 = Fehler)
foreach ($f in Get-ChildItem sql\*.sql | Sort-Object Name) { "== $($f.Name)"; sqlite3 -bail -header -column data/northwind_full.db ".read sql/$($f.Name)"; $LASTEXITCODE }

# Schema ansehen
sqlite3 data/northwind_full.db ".tables" ".schema Orders"
```

Bei Ad-hoc-SQL direkt auf der Kommandozeile: Tabellennamen mit Leerzeichen in eckige Klammern setzen (`[Order Details]`). Längere Abfragen besser als Datei schreiben und mit `.read` ausführen, um Probleme mit PowerShell-Quoting zu vermeiden.

## Die zwei Datenbanken

| Datei | Inhalt | Verwendung |
|---|---|---|
| `data/northwind_full.db` | Vollständige Northwind-Version aus `github.com/jpwhite3/northwind-SQLite3` (`dist/northwind.db`) | **Standard für alle Analysen** |
| `data/Northwind.db` | Vereinfachte W3Schools-Version (196 Bestellungen, 1996–1997). Ohne UnitPrice/Discount in den Positionen, ohne Versand-/Lieferdaten und Fracht | Nur Altbestand |

Die Schemata sind **nicht kompatibel**. In der vollständigen DB heißt die Positionstabelle `[Order Details]` statt `OrderDetails`, `CustomerID` ist Text (z. B. `ALFKI`), der Versender steht in `Orders.ShipVia` → `Shippers.ShipperID`, und Firmennamen stehen in `CompanyName`. Neue Dateien in `data/` nie `northwind.db` nennen: Windows unterscheidet bei Dateinamen nicht zwischen Groß- und Kleinschreibung, damit würde `Northwind.db` überschrieben.

## Dashboard (`app.py`)

`app.py` führt die SQL-Dateien aus `sql/` **unverändert** aus. Die Filter für Jahr, Land und Kategorie wirken über TEMP VIEWs namens `Orders` und `[Order Details]`, die die Originaltabellen überdecken: SQLite löst unqualifizierte Namen zuerst im temp-Schema auf. Die Filterwerte stehen in temp-Tabellen und werden per Parameter eingefügt. Daraus folgt:
- Neue SQL-Dateien funktionieren nur dann mit den Filtern, wenn sie `Orders` und `[Order Details]` unqualifiziert ansprechen, also ohne `main.`.
- `Customers`, `Products` usw. werden nicht gefiltert.
- Die fest eingebauten Jahre 2013 und 2022 in `06_` und `09_` sind nur dann sinnvoll, wenn der Jahresfilter beide Jahre enthält.

## Konventionen für `sql/`

- Eine Datei pro Business-Frage, nummeriert `NN_thema.sql`. Ganz oben steht ein Kommentarblock mit der Business-Frage, im Query selbst stehen deutsche Kommentare.
- Eine Ergebnismenge pro Datei. Mehrere Dimensionen (z. B. Versender, Land, Mitarbeiter) werden per `UNION ALL` mit einer Spalte `Dimension` untereinander ausgegeben (siehe `07_`, `08_`).
- Spaltenaliase ohne Umlaute (`Veraenderung_Pct`, `Avg_Bestellwert`).
- **Netto-Umsatz** immer als `d.UnitPrice * d.Quantity * (1 - d.Discount)` aus `[Order Details]`. `Products.UnitPrice` ist der aktuelle Listenpreis und nicht der Verkaufspreis.
- Zeitbezüge relativ zu `MAX(Orders.OrderDate)`, nicht zu `date('now')`.
- Jahresvergleiche nur über vollständige Jahre. Wo ein fester Vergleich nötig ist, wird 2013 mit 2022 verglichen.
- Verspätet bedeutet `ShippedDate > RequiredDate`. Bestellungen mit `ShippedDate IS NULL` (21 Stück) sind noch nicht versendet.
- Mitarbeiter → Region: über `EmployeeTerritories` → `Territories` → `Regions`. Jeder Mitarbeiter gehört genau einer Region an.

## Datenbesonderheiten von `northwind_full.db`

Diese Punkte bei der Interpretation von Ergebnissen immer erwähnen:

- **Synthetisch erweitert:** 16.282 Bestellungen und 609.283 Positionen von 2012-07-10 bis 2023-10-28 (das Original hat ~830 Bestellungen aus 1996–1998). Kennzahlen sind daher auffällig gleichmäßig: keine Saisonalität, Verspätungsquote ~23 % überall, Frachtquote ~0,9 % überall, Mitarbeiter je ~11 % Umsatzanteil. Ein Ø Bestellwert von ~28.000 ist unrealistisch.
- **2012 und 2023 sind unvollständig** (2012 ab Juli, 2023 bis Oktober).
- **Rabatte sind selten:** Nur 838 Positionen haben `Discount > 0`. Die Stufen 1–6 % kommen jeweils nur 1–3 Mal vor; aussagekräftig sind nur 5/10/15/20/25 %.
- **Vermutlich Testdatensätze:** Die Kunden `Val2` und `VALON` haben als `CompanyName` nur „IT“ und `Country = NULL`, tragen aber ~2,2 % des Umsatzes.
- Die DB enthält fertige Views (z. B. `Invoices`, `Order Subtotals`, `Sales by Category`, `Summary of Sales by Year`). Die Views `Product Sales for 1997` und `Category Sales for 1997` filtern fest auf 1997 und liefern hier 0 Zeilen.
