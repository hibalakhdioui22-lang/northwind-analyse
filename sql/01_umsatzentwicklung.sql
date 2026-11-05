-- =====================================================================
-- Business-Frage 1:
-- Wie entwickeln sich Netto-Umsatz und Bestellanzahl pro Jahr?
-- Gibt es Wachstum oder Einbrüche?
--
-- Datenbank: data/northwind_full.db
-- Netto-Umsatz = UnitPrice * Quantity * (1 - Discount)
-- =====================================================================

WITH umsatz_pro_jahr AS (
    SELECT
        strftime('%Y', o.OrderDate)                           AS jahr,
        -- Anzahl Monate mit Bestellungen: < 12 bedeutet unvollständiges Jahr
        COUNT(DISTINCT strftime('%m', o.OrderDate))           AS monate,
        COUNT(DISTINCT o.OrderID)                             AS bestellungen,
        SUM(d.UnitPrice * d.Quantity * (1 - d.Discount))      AS umsatz
    FROM Orders o
    JOIN [Order Details] d ON d.OrderID = o.OrderID
    GROUP BY jahr
)
SELECT
    jahr                                                   AS Jahr,
    monate                                                 AS Monate,
    bestellungen                                           AS Bestellungen,
    ROUND(umsatz, 0)                                       AS Netto_Umsatz,
    -- Durchschnittlicher Bestellwert (Average Order Value)
    ROUND(umsatz / bestellungen, 0)                        AS Avg_Bestellwert,
    -- Wachstum gegenüber dem Vorjahr in Prozent.
    -- Nur berechnen, wenn beide Jahre vollständig sind (12 Monate),
    -- sonst wäre der Vergleich verzerrt (z. B. 2023 nur bis Oktober).
    CASE
        WHEN monate = 12 AND LAG(monate) OVER (ORDER BY jahr) = 12
        THEN ROUND(100.0 * (umsatz / LAG(umsatz) OVER (ORDER BY jahr) - 1), 1)
    END                                                    AS Wachstum_Vorjahr_Pct
FROM umsatz_pro_jahr
ORDER BY jahr;
