-- =====================================================================
-- Business-Frage 2:
-- Welche Kategorien und Produkte tragen den Umsatz, und wie stark ist
-- der Umsatz auf wenige Produkte konzentriert? (ABC-Analyse)
--
-- A = Produkte, die zusammen die ersten 80 % des Umsatzes bringen
-- B = die nächsten 15 % (bis 95 %)
-- C = die restlichen 5 %
-- =====================================================================

WITH umsatz_pro_produkt AS (
    SELECT
        p.ProductID,
        p.ProductName,
        c.CategoryName,
        SUM(d.UnitPrice * d.Quantity * (1 - d.Discount)) AS umsatz
    FROM [Order Details] d
    JOIN Products   p ON p.ProductID  = d.ProductID
    JOIN Categories c ON c.CategoryID = p.CategoryID
    GROUP BY p.ProductID, p.ProductName, c.CategoryName
),
kumuliert AS (
    SELECT
        *,
        -- Rang nach Umsatz (1 = umsatzstärkstes Produkt)
        ROW_NUMBER() OVER (ORDER BY umsatz DESC)                    AS rang,
        -- Anteil des einzelnen Produkts am Gesamtumsatz
        umsatz / SUM(umsatz) OVER ()                                AS anteil,
        -- Kumulierter Anteil inkl. dieses Produkts
        SUM(umsatz) OVER (ORDER BY umsatz DESC
                          ROWS UNBOUNDED PRECEDING)
            / SUM(umsatz) OVER ()                                   AS kum_anteil
    FROM umsatz_pro_produkt
)
SELECT
    rang                                  AS Rang,
    ProductName                           AS Produkt,
    CategoryName                          AS Kategorie,
    ROUND(umsatz, 0)                      AS Netto_Umsatz,
    ROUND(100 * anteil, 2)                AS Anteil_Pct,
    ROUND(100 * kum_anteil, 1)            AS Kum_Anteil_Pct,
    -- Klasse anhand des kumulierten Anteils VOR diesem Produkt,
    -- damit das Produkt, das die 80-%-Grenze überschreitet, noch zu A zählt
    CASE
        WHEN kum_anteil - anteil < 0.80 THEN 'A'
        WHEN kum_anteil - anteil < 0.95 THEN 'B'
        ELSE 'C'
    END                                   AS ABC_Klasse
FROM kumuliert
ORDER BY rang;
