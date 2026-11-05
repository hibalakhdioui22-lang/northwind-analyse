-- =====================================================================
-- Business-Frage 9:
-- Welche Mitarbeiter und Vertriebsregionen erzielen den meisten Umsatz,
-- und wie entwickelt sich ihr Umsatz über die Jahre?
--
-- Vergleich erstes vollständiges Jahr (2013) mit letztem (2022).
-- =====================================================================

WITH region_pro_mitarbeiter AS (
    -- Jeder Mitarbeiter ist über seine Territorien genau einer Region zugeordnet
    SELECT
        et.EmployeeID,
        MIN(r.RegionDescription) AS region
    FROM EmployeeTerritories et
    JOIN Territories t ON t.TerritoryID = et.TerritoryID
    JOIN Regions     r ON r.RegionID    = t.RegionID
    GROUP BY et.EmployeeID
),
umsatz_pro_mitarbeiter AS (
    SELECT
        e.EmployeeID,
        e.FirstName || ' ' || e.LastName                            AS mitarbeiter,
        e.Title                                                     AS titel,
        COUNT(DISTINCT o.OrderID)                                   AS bestellungen,
        SUM(d.UnitPrice * d.Quantity * (1 - d.Discount))            AS umsatz,
        SUM(CASE WHEN strftime('%Y', o.OrderDate) = '2013'
                 THEN d.UnitPrice * d.Quantity * (1 - d.Discount) ELSE 0 END) AS umsatz_2013,
        SUM(CASE WHEN strftime('%Y', o.OrderDate) = '2022'
                 THEN d.UnitPrice * d.Quantity * (1 - d.Discount) ELSE 0 END) AS umsatz_2022
    FROM Employees e
    JOIN Orders          o ON o.EmployeeID = e.EmployeeID
    JOIN [Order Details] d ON d.OrderID    = o.OrderID
    GROUP BY e.EmployeeID, mitarbeiter, titel
)
SELECT
    u.mitarbeiter                                          AS Mitarbeiter,
    u.titel                                                AS Titel,
    COALESCE(r.region, '(keine)')                          AS Region,
    u.bestellungen                                         AS Bestellungen,
    ROUND(u.umsatz, 0)                                     AS Netto_Umsatz,
    ROUND(100 * u.umsatz / SUM(u.umsatz) OVER (), 1)       AS Anteil_Pct,
    ROUND(u.umsatz / u.bestellungen, 0)                    AS Avg_Bestellwert,
    ROUND(u.umsatz_2013, 0)                                AS Umsatz_2013,
    ROUND(u.umsatz_2022, 0)                                AS Umsatz_2022,
    ROUND(100.0 * (u.umsatz_2022 / NULLIF(u.umsatz_2013, 0) - 1), 1)
                                                           AS Veraenderung_Pct
FROM umsatz_pro_mitarbeiter u
LEFT JOIN region_pro_mitarbeiter r ON r.EmployeeID = u.EmployeeID
ORDER BY u.umsatz DESC;
