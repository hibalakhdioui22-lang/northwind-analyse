-- =====================================================================
-- Business-Frage 6:
-- Welche Länder (Märkte) wachsen, welche schrumpfen?
--
-- Vergleich des ersten vollständigen Jahres (2013) mit dem letzten
-- vollständigen Jahr (2022). 2012 und 2023 sind unvollständig.
-- =====================================================================

WITH umsatz_pro_land AS (
    SELECT
        -- Kunden ohne Länderangabe (Country IS NULL) gesondert ausweisen
        COALESCE(NULLIF(TRIM(c.Country), ''), '(unbekannt)')        AS land,
        COUNT(DISTINCT c.CustomerID)                                AS kunden,
        SUM(d.UnitPrice * d.Quantity * (1 - d.Discount))            AS umsatz_gesamt,
        SUM(CASE WHEN strftime('%Y', o.OrderDate) = '2013'
                 THEN d.UnitPrice * d.Quantity * (1 - d.Discount) ELSE 0 END) AS umsatz_2013,
        SUM(CASE WHEN strftime('%Y', o.OrderDate) = '2022'
                 THEN d.UnitPrice * d.Quantity * (1 - d.Discount) ELSE 0 END) AS umsatz_2022
    FROM Customers c
    JOIN Orders          o ON o.CustomerID = c.CustomerID
    JOIN [Order Details] d ON d.OrderID    = o.OrderID
    GROUP BY land
)
SELECT
    land                                                   AS Land,
    kunden                                                 AS Kunden,
    ROUND(umsatz_gesamt, 0)                                AS Umsatz_Gesamt,
    -- Anteil am Gesamtumsatz aller Länder
    ROUND(100 * umsatz_gesamt / SUM(umsatz_gesamt) OVER (), 1) AS Anteil_Pct,
    ROUND(umsatz_gesamt / kunden, 0)                       AS Umsatz_pro_Kunde,
    ROUND(umsatz_2013, 0)                                  AS Umsatz_2013,
    ROUND(umsatz_2022, 0)                                  AS Umsatz_2022,
    -- Veränderung 2022 gegenüber 2013 in Prozent
    ROUND(100.0 * (umsatz_2022 / NULLIF(umsatz_2013, 0) - 1), 1) AS Veraenderung_Pct
FROM umsatz_pro_land
ORDER BY Veraenderung_Pct DESC;
