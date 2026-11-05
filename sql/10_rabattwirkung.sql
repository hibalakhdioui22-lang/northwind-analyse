-- =====================================================================
-- Business-Frage 10:
-- Steigern Rabatte die Bestellmenge, oder verschenken sie nur Marge?
--
-- Hinweis: Rabatte kommen nur in einem kleinen Teil der Daten vor
-- (ca. 838 Positionen). Damit der Vergleich fair ist, werden nur
-- Bestellungen aus dem Zeitraum betrachtet, in dem überhaupt Rabatte
-- vergeben wurden.
-- =====================================================================

WITH rabatt_zeitraum AS (
    -- Erstes und letztes Bestelldatum mit mindestens einer rabattierten Position
    SELECT
        MIN(o.OrderDate) AS von,
        MAX(o.OrderDate) AS bis
    FROM Orders o
    JOIN [Order Details] d ON d.OrderID = o.OrderID
    WHERE d.Discount > 0
),
positionen AS (
    SELECT
        d.Discount,
        d.Quantity,
        d.UnitPrice
    FROM Orders o
    JOIN [Order Details] d ON d.OrderID = o.OrderID
    CROSS JOIN rabatt_zeitraum z
    WHERE o.OrderDate BETWEEN z.von AND z.bis
)
SELECT
    -- Rabattstufe in Prozent (0 = kein Rabatt)
    CAST(ROUND(Discount * 100) AS INTEGER)                 AS Rabatt_Pct,
    COUNT(*)                                               AS Positionen,
    -- Wichtigste Kennzahl: Kaufen Kunden mit Rabatt mehr Stück pro Position?
    ROUND(AVG(Quantity), 1)                                AS Avg_Menge_pro_Position,
    ROUND(AVG(UnitPrice), 2)                               AS Avg_Stueckpreis,
    ROUND(SUM(UnitPrice * Quantity), 0)                    AS Brutto_Umsatz,
    -- Durch Rabatte entgangener Umsatz
    ROUND(SUM(UnitPrice * Quantity * Discount), 0)         AS Rabatt_Betrag,
    ROUND(SUM(UnitPrice * Quantity * (1 - Discount)), 0)   AS Netto_Umsatz
FROM positionen
GROUP BY Rabatt_Pct
ORDER BY Rabatt_Pct;
