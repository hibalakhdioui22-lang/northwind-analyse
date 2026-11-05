-- =====================================================================
-- Business-Frage 5:
-- Welche Kunden waren früher aktiv, kaufen jetzt aber weniger oder gar
-- nicht mehr? (Churn-Analyse)
--
-- Vergleich: Umsatz der letzten 12 Monate vs. die 12 Monate davor.
-- Stichtag ist das letzte Bestelldatum in der Datenbank (nicht "heute"),
-- damit die Abfrage auch auf historischen Daten sinnvoll funktioniert.
-- =====================================================================

WITH stichtag AS (
    SELECT
        MAX(OrderDate)                         AS max_datum,
        date(MAX(OrderDate), '-12 months')     AS grenze_12m,
        date(MAX(OrderDate), '-24 months')     AS grenze_24m
    FROM Orders
),
kunde_umsatz AS (
    SELECT
        c.CustomerID,
        c.CompanyName,
        c.Country,
        MAX(o.OrderDate)                                            AS letzte_bestellung,
        -- Umsatz in den letzten 12 Monaten
        SUM(CASE WHEN o.OrderDate > s.grenze_12m
                 THEN d.UnitPrice * d.Quantity * (1 - d.Discount) ELSE 0 END) AS umsatz_12m,
        -- Umsatz in den 12 Monaten davor
        SUM(CASE WHEN o.OrderDate >  s.grenze_24m
                  AND o.OrderDate <= s.grenze_12m
                 THEN d.UnitPrice * d.Quantity * (1 - d.Discount) ELSE 0 END) AS umsatz_vorjahr
    FROM Customers c
    JOIN Orders          o ON o.CustomerID = c.CustomerID
    JOIN [Order Details] d ON d.OrderID    = o.OrderID
    CROSS JOIN stichtag  s
    GROUP BY c.CustomerID, c.CompanyName, c.Country
)
SELECT
    CompanyName                                       AS Kunde,
    Country                                           AS Land,
    date(letzte_bestellung)                           AS Letzte_Bestellung,
    ROUND(umsatz_vorjahr, 0)                          AS Umsatz_Vorjahr_12M,
    ROUND(umsatz_12m, 0)                              AS Umsatz_Letzte_12M,
    ROUND(100.0 * (umsatz_12m / umsatz_vorjahr - 1), 1) AS Veraenderung_Pct,
    -- Einstufung des Kunden
    CASE
        WHEN umsatz_12m = 0                         THEN 'Verloren'
        WHEN umsatz_12m < 0.7 * umsatz_vorjahr      THEN 'Stark rückläufig (> -30 %)'
        WHEN umsatz_12m < umsatz_vorjahr            THEN 'Rückläufig'
        ELSE 'Stabil / wachsend'
    END                                               AS Status
FROM kunde_umsatz
-- Nur Kunden, die im Vorjahreszeitraum aktiv waren und jetzt weniger kaufen
WHERE umsatz_vorjahr > 0
  AND umsatz_12m < umsatz_vorjahr
ORDER BY Veraenderung_Pct ASC;
