-- =====================================================================
-- Business-Frage 7:
-- Wie hoch ist die Pünktlichkeitsquote pro Versanddienstleister,
-- Zielland und Mitarbeiter? Wo entstehen die Verspätungen?
--
-- Verspätet = ShippedDate liegt nach RequiredDate.
-- Noch nicht versendete Bestellungen (ShippedDate IS NULL) werden
-- nicht mitgezählt.
-- =====================================================================

WITH lieferungen AS (
    SELECT
        o.OrderID,
        s.CompanyName                                    AS versender,
        o.ShipCountry                                    AS zielland,
        e.FirstName || ' ' || e.LastName                 AS mitarbeiter,
        -- 1 = verspätet, 0 = pünktlich
        CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END AS verspaetet,
        -- Tage zwischen Bestellung und Versand
        julianday(o.ShippedDate) - julianday(o.OrderDate)          AS durchlaufzeit,
        -- Tage Verspätung (nur relevant, wenn verspätet)
        julianday(o.ShippedDate) - julianday(o.RequiredDate)       AS tage_zu_spaet
    FROM Orders o
    JOIN Shippers  s ON s.ShipperID  = o.ShipVia
    JOIN Employees e ON e.EmployeeID = o.EmployeeID
    WHERE o.ShippedDate IS NOT NULL
),
-- Dieselben Kennzahlen für drei Dimensionen, untereinander gestapelt
auswertung AS (
    SELECT 'Versender' AS dimension, versender AS wert, * FROM lieferungen
    UNION ALL
    SELECT 'Zielland',               zielland,          * FROM lieferungen
    UNION ALL
    SELECT 'Mitarbeiter',            mitarbeiter,       * FROM lieferungen
)
SELECT
    dimension                                              AS Dimension,
    wert                                                   AS Wert,
    COUNT(*)                                               AS Lieferungen,
    SUM(verspaetet)                                        AS Verspaetet,
    ROUND(100.0 * SUM(verspaetet) / COUNT(*), 1)           AS Verspaetet_Pct,
    ROUND(AVG(durchlaufzeit), 1)                           AS Avg_Durchlaufzeit_Tage,
    -- Durchschnittliche Verspätung nur über die verspäteten Lieferungen
    ROUND(AVG(CASE WHEN verspaetet = 1 THEN tage_zu_spaet END), 1)
                                                           AS Avg_Tage_zu_spaet
FROM auswertung
GROUP BY dimension, wert
ORDER BY
    -- Reihenfolge der Blöcke: Versender, Mitarbeiter, Zielland
    CASE dimension WHEN 'Versender' THEN 1 WHEN 'Mitarbeiter' THEN 2 ELSE 3 END,
    Verspaetet_Pct DESC;
