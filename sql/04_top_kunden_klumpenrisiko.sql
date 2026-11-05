-- =====================================================================
-- Business-Frage 4:
-- Wer sind die Top-10-Kunden nach Umsatz, und wie hoch ist das
-- Klumpenrisiko (Anteil der Top-Kunden am Gesamtumsatz)?
-- =====================================================================

WITH umsatz_pro_kunde AS (
    SELECT
        c.CustomerID,
        c.CompanyName,
        c.Country,
        COUNT(DISTINCT o.OrderID)                          AS bestellungen,
        SUM(d.UnitPrice * d.Quantity * (1 - d.Discount))   AS umsatz
    FROM Customers c
    JOIN Orders          o ON o.CustomerID = c.CustomerID
    JOIN [Order Details] d ON d.OrderID    = o.OrderID
    GROUP BY c.CustomerID, c.CompanyName, c.Country
),
rangliste AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY umsatz DESC)               AS rang,
        umsatz / SUM(umsatz) OVER ()                           AS anteil,
        -- Kumulierter Anteil: Wie viel Umsatz bringen die Top-N zusammen?
        SUM(umsatz) OVER (ORDER BY umsatz DESC
                          ROWS UNBOUNDED PRECEDING)
            / SUM(umsatz) OVER ()                              AS kum_anteil,
        COUNT(*) OVER ()                                       AS anzahl_kunden
    FROM umsatz_pro_kunde
)
SELECT
    rang                                  AS Rang,
    CompanyName                           AS Kunde,
    Country                               AS Land,
    bestellungen                          AS Bestellungen,
    ROUND(umsatz, 0)                      AS Netto_Umsatz,
    ROUND(100 * anteil, 2)                AS Anteil_Pct,
    ROUND(100 * kum_anteil, 1)            AS Kum_Anteil_Pct,
    -- Zum Vergleich: Bei Gleichverteilung hätten N Kunden N / Anzahl Kunden
    ROUND(100.0 * rang / anzahl_kunden, 1) AS Gleichverteilung_Pct
FROM rangliste
WHERE rang <= 10
ORDER BY rang;
