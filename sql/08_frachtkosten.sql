-- =====================================================================
-- Business-Frage 8:
-- Wie hoch sind die Frachtkosten im Verhältnis zum Bestellwert,
-- je Versanddienstleister und Zielland? Wo frisst die Fracht die Marge?
--
-- Frachtquote = Summe Fracht / Summe Netto-Bestellwert
-- =====================================================================

WITH bestellwert AS (
    -- Netto-Warenwert pro Bestellung
    SELECT
        OrderID,
        SUM(UnitPrice * Quantity * (1 - Discount)) AS warenwert
    FROM [Order Details]
    GROUP BY OrderID
),
bestellungen AS (
    SELECT
        o.OrderID,
        s.CompanyName       AS versender,
        o.ShipCountry       AS zielland,
        o.Freight           AS fracht,
        b.warenwert
    FROM Orders o
    JOIN Shippers    s ON s.ShipperID = o.ShipVia
    JOIN bestellwert b ON b.OrderID   = o.OrderID
),
-- Kennzahlen für zwei Dimensionen, untereinander gestapelt
auswertung AS (
    SELECT 'Versender' AS dimension, versender AS wert, * FROM bestellungen
    UNION ALL
    SELECT 'Zielland',               zielland,          * FROM bestellungen
)
SELECT
    dimension                                         AS Dimension,
    wert                                              AS Wert,
    COUNT(*)                                          AS Bestellungen,
    ROUND(SUM(fracht), 0)                             AS Fracht_Gesamt,
    ROUND(AVG(fracht), 2)                             AS Avg_Fracht,
    ROUND(AVG(warenwert), 0)                          AS Avg_Warenwert,
    -- Fracht in Prozent des Warenwerts
    ROUND(100.0 * SUM(fracht) / SUM(warenwert), 3)    AS Frachtquote_Pct
FROM auswertung
GROUP BY dimension, wert
ORDER BY
    CASE dimension WHEN 'Versender' THEN 1 ELSE 2 END,
    Frachtquote_Pct DESC;
