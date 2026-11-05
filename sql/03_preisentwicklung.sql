-- =====================================================================
-- Business-Frage 3:
-- Wie haben sich die tatsächlichen Verkaufspreise (Order Details.UnitPrice)
-- im Vergleich zum aktuellen Listenpreis (Products.UnitPrice) entwickelt?
-- Gibt es Preiserhöhungen oder Preisdruck?
--
-- Preisindex = mengengewichteter Verkaufspreis / mengengewichteter
-- Listenpreis. 100 % = Verkauf genau zum heutigen Listenpreis.
-- =====================================================================

SELECT
    strftime('%Y', o.OrderDate)                                    AS Jahr,
    SUM(d.Quantity)                                                AS Stueck,
    -- Durchschnittlicher Verkaufspreis pro Stück (vor Rabatt), mengengewichtet
    ROUND(SUM(d.UnitPrice * d.Quantity) / SUM(d.Quantity), 2)      AS Avg_Verkaufspreis,
    -- Durchschnittlicher Listenpreis der verkauften Stücke, mengengewichtet
    ROUND(SUM(p.UnitPrice * d.Quantity) / SUM(d.Quantity), 2)      AS Avg_Listenpreis,
    -- Preisindex in Prozent
    ROUND(100.0 * SUM(d.UnitPrice * d.Quantity)
                / SUM(p.UnitPrice * d.Quantity), 1)                AS Preisindex_Pct,
    -- Anteil der Positionen, die unter Listenpreis verkauft wurden
    ROUND(100.0 * SUM(d.UnitPrice < p.UnitPrice) / COUNT(*), 1)    AS Unter_Listenpreis_Pct,
    -- Durchschnittlicher Rabatt (mengengewichtet) in Prozent
    ROUND(100.0 * SUM(d.Discount * d.Quantity) / SUM(d.Quantity), 2)
                                                                   AS Avg_Rabatt_Pct
FROM Orders o
JOIN [Order Details] d ON d.OrderID   = o.OrderID
JOIN Products        p ON p.ProductID = d.ProductID
GROUP BY Jahr
ORDER BY Jahr;
