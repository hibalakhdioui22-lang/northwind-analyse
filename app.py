
"""
Northwind – interaktives Business-Dashboard (Streamlit + Plotly)

Starten:
    .\\.venv\\Scripts\\python.exe -m streamlit run app.py

Funktionsweise der Filter:
Die SQL-Dateien in sql/ werden unverändert ausgeführt. Damit die Filter (Jahr, Land,
Kategorie) trotzdem wirken, legt das Dashboard pro Abfrage temporäre Views mit den
Namen "Orders" und "Order Details" an. SQLite sucht unqualifizierte Tabellennamen
zuerst im temp-Schema – die Abfragen lesen also automatisch die gefilterten Daten,
während die Originaltabellen (main.Orders usw.) unangetastet bleiben.
"""

import sqlite3
from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# ---------------------------------------------------------------------------
# Pfade und Grundeinstellungen
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent
DB_PFAD = ROOT / "data" / "northwind_full.db"
SQL_DIR = ROOT / "sql"

# Farben (validierte Referenzpalette); Farbe folgt immer der Bedeutung, nie dem Rang
BLAU, BLAU_HELL, ORANGE, ROT = "#2a78d6", "#86b6ef", "#eb6834", "#e34948"
REGION_FARBEN = {"Eastern": "#2a78d6", "Western": "#eb6834",
                 "Northern": "#1baf7a", "Southern": "#eda100", "(keine)": "#898781"}

st.set_page_config(page_title="Northwind Dashboard", page_icon="📊", layout="wide")


# ---------------------------------------------------------------------------
# Hilfsfunktionen: Zahlenformat (deutsch) und Diagramm-Layout
# ---------------------------------------------------------------------------
def de_zahl(wert: float, nachkomma: int = 0) -> str:
    """Formatiert eine Zahl deutsch: Tausenderpunkt, Dezimalkomma."""
    text = f"{wert:,.{nachkomma}f}"
    return text.replace(",", "X").replace(".", ",").replace("X", ".")


def de_mio(wert: float) -> str:
    """Formatiert einen Betrag in Millionen, z. B. 448,9 Mio."""
    return f"{de_zahl(wert / 1e6, 1)} Mio."


def layout(fig: go.Figure, hoehe: int = 400) -> go.Figure:
    """Einheitliches, ruhiges Layout für alle Diagramme."""
    fig.update_layout(
        height=hoehe,
        margin=dict(l=10, r=10, t=10, b=10),
        separators=",.",                       # deutsches Zahlenformat in Achsen und Tooltips
        legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0, title=None),
        hoverlabel=dict(font_size=13),
        bargap=0.25,
    )
    fig.update_xaxes(showgrid=False)
    fig.update_yaxes(gridwidth=0.5)
    return fig


def horizontal(fig: go.Figure) -> go.Figure:
    """Für liegende Balken: Gitterlinien senkrecht statt waagerecht."""
    fig.update_xaxes(showgrid=True, gridwidth=0.5)
    fig.update_yaxes(showgrid=False, title=None)
    return fig


# ---------------------------------------------------------------------------
# Datenzugriff
# ---------------------------------------------------------------------------
def verbinden() -> sqlite3.Connection:
    """Öffnet die Datenbank schreibgeschützt (die Analyse verändert nie Daten)."""
    return sqlite3.connect(f"file:{DB_PFAD.as_posix()}?mode=ro", uri=True)


@st.cache_data(show_spinner=False)
def filter_optionen() -> tuple[list[int], list[str], dict[str, int]]:
    """Liest die möglichen Filterwerte (Jahre, Länder, Kategorien) aus der Datenbank."""
    with verbinden() as con:
        jahre = [int(j) for (j,) in con.execute(
            "SELECT DISTINCT strftime('%Y', OrderDate) FROM Orders ORDER BY 1")]
        # Dieselbe Länder-Logik wie in sql/06_laender_wachstum.sql
        laender = [l for (l,) in con.execute(
            "SELECT DISTINCT COALESCE(NULLIF(TRIM(Country), ''), '(unbekannt)') "
            "FROM Customers ORDER BY 1")]
        kategorien = dict(con.execute(
            "SELECT CategoryName, CategoryID FROM Categories ORDER BY CategoryName"))
    return jahre, laender, kategorien


def filter_views_anlegen(con: sqlite3.Connection, von: int, bis: int,
                         laender: tuple[str, ...], kategorie_ids: tuple[int, ...]) -> None:
    """
    Legt temporäre Views 'Orders' und 'Order Details' an, die die Originaltabellen
    nach den Filtern einschränken. Die Filterwerte stehen in temporären Tabellen
    (per Parameter eingefügt, also ohne SQL-Injection-Risiko).
    Leere Länder-/Kategorieauswahl bedeutet „alle“.
    """
    con.executescript("""
        CREATE TEMP TABLE f_jahr (von TEXT, bis TEXT);
        CREATE TEMP TABLE f_land (wert TEXT);
        CREATE TEMP TABLE f_kat  (id INTEGER);
    """)
    con.execute("INSERT INTO temp.f_jahr VALUES (?, ?)", (str(von), str(bis)))
    con.executemany("INSERT INTO temp.f_land VALUES (?)", [(l,) for l in laender])
    con.executemany("INSERT INTO temp.f_kat VALUES (?)", [(k,) for k in kategorie_ids])

    con.executescript("""
        -- Bestellungen: Zeitraum, Kundenland und (falls gewählt) mindestens eine
        -- Position aus den gewählten Kategorien
        CREATE TEMP VIEW Orders AS
        SELECT o.*
        FROM main.Orders o, temp.f_jahr fj
        WHERE strftime('%Y', o.OrderDate) BETWEEN fj.von AND fj.bis
          AND (NOT EXISTS (SELECT 1 FROM temp.f_land)
               OR o.CustomerID IN (
                   SELECT CustomerID FROM main.Customers
                   WHERE COALESCE(NULLIF(TRIM(Country), ''), '(unbekannt)')
                         IN (SELECT wert FROM temp.f_land)))
          AND (NOT EXISTS (SELECT 1 FROM temp.f_kat)
               OR EXISTS (
                   SELECT 1 FROM main.[Order Details] d
                   JOIN main.Products p ON p.ProductID = d.ProductID
                   WHERE d.OrderID = o.OrderID
                     AND p.CategoryID IN (SELECT id FROM temp.f_kat)));

        -- Positionen: nur aus gefilterten Bestellungen und gewählten Kategorien
        CREATE TEMP VIEW [Order Details] AS
        SELECT d.*
        FROM main.[Order Details] d
        WHERE d.OrderID IN (SELECT OrderID FROM temp.Orders)
          AND (NOT EXISTS (SELECT 1 FROM temp.f_kat)
               OR d.ProductID IN (
                   SELECT ProductID FROM main.Products
                   WHERE CategoryID IN (SELECT id FROM temp.f_kat)));
    """)


@st.cache_data(show_spinner="Abfrage läuft …")
def sql_ausfuehren(datei: str, von: int, bis: int,
                   laender: tuple[str, ...], kategorie_ids: tuple[int, ...]) -> pd.DataFrame:
    """Führt eine SQL-Datei aus sql/ mit den aktuellen Filtern aus (Ergebnis wird zwischengespeichert)."""
    sql = (SQL_DIR / datei).read_text(encoding="utf-8")
    with verbinden() as con:
        filter_views_anlegen(con, von, bis, laender, kategorie_ids)
        return pd.read_sql_query(sql, con)


# ---------------------------------------------------------------------------
# Start: Datenbank vorhanden?
# ---------------------------------------------------------------------------
if not DB_PFAD.exists():
    st.error("Die Datenbank `data/northwind_full.db` fehlt.")
    st.markdown("Sie ist nicht im Repository enthalten. Herunterladen mit:")
    st.code('Invoke-WebRequest "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/'
            'main/dist/northwind.db" -OutFile "data/northwind_full.db"', language="powershell")
    st.stop()

ALLE_JAHRE, ALLE_LAENDER, KATEGORIEN = filter_optionen()

# ---------------------------------------------------------------------------
# Seitenleiste: Filter
# ---------------------------------------------------------------------------
with st.sidebar:
    st.header("Filter")
    von, bis = st.select_slider("Jahr", options=ALLE_JAHRE,
                                value=(ALLE_JAHRE[0], ALLE_JAHRE[-1]))
    laender = st.multiselect("Land (Kunde)", ALLE_LAENDER, placeholder="Alle Länder")
    kategorien = st.multiselect("Kategorie", list(KATEGORIEN), placeholder="Alle Kategorien")

    st.divider()
    with st.expander("Hinweise zu den Daten"):
        st.markdown(
            "- Die Datenbank ist **synthetisch erweitert** (Juli 2012 – Oktober 2023); "
            "viele Kennzahlen sind deshalb auffällig gleichmäßig.\n"
            "- **2012 und 2023 sind unvollständige Jahre.**\n"
            "- „(unbekannt)“ sind die Kunden *Val2* und *VALON* ohne Land – vermutlich Testdaten.\n"
            "- Netto-Umsatz = UnitPrice × Quantity × (1 − Discount).\n"
            "- Der Kategorie-Filter zählt nur Positionen der gewählten Kategorien; "
            "Bestellungen zählen, wenn sie mindestens eine solche Position enthalten."
        )

# Filter als hashbare Tupel (für den Cache)
FILTER = dict(von=von, bis=bis, laender=tuple(sorted(laender)),
              kategorie_ids=tuple(sorted(KATEGORIEN[k] for k in kategorien)))


def laden(datei: str) -> pd.DataFrame:
    """Kurzform: SQL-Datei mit den aktuellen Filtern ausführen."""
    return sql_ausfuehren(datei, **FILTER)


# Benötigte Abfragen laden
df_umsatz = laden("01_umsatzentwicklung.sql")
df_kunden = laden("04_top_kunden_klumpenrisiko.sql")
df_laender = laden("06_laender_wachstum.sql")
df_liefer = laden("07_liefertreue.sql")
df_mitarb = laden("09_mitarbeiter_performance.sql")

# ---------------------------------------------------------------------------
# Kopfzeile und KPI-Kacheln
# ---------------------------------------------------------------------------
st.title("Northwind – Business-Dashboard")
filter_text = [f"{von}–{bis}" if von != bis else str(von)]
filter_text.append(", ".join(laender) if laender else "alle Länder")
filter_text.append(", ".join(kategorien) if kategorien else "alle Kategorien")
st.caption("Auswahl: " + " · ".join(filter_text))

if df_umsatz.empty:
    st.warning("Für diese Filterkombination gibt es keine Bestellungen.")
    st.stop()

umsatz = df_umsatz["Netto_Umsatz"].sum()
bestellungen = int(df_umsatz["Bestellungen"].sum())
versender = df_liefer[df_liefer["Dimension"] == "Versender"]
lieferungen = versender["Lieferungen"].sum()
puenktlich = 100 * (1 - versender["Verspaetet"].sum() / lieferungen) if lieferungen else float("nan")

k1, k2, k3, k4 = st.columns(4)
k1.metric("Netto-Umsatz", de_mio(umsatz), border=True)
k2.metric("Bestellungen", de_zahl(bestellungen), border=True)
k3.metric("Ø Bestellwert", de_zahl(umsatz / bestellungen), border=True)
k4.metric("Pünktlichkeitsquote", f"{de_zahl(puenktlich, 1)} %", border=True,
          help="Anteil der versendeten Bestellungen mit ShippedDate ≤ RequiredDate")

# ---------------------------------------------------------------------------
# 1. Umsatzentwicklung (sql/01)
# ---------------------------------------------------------------------------
st.subheader("Umsatzentwicklung")
d = df_umsatz.copy()
d["Status"] = d["Monate"].map(lambda m: "vollständiges Jahr" if m == 12 else "unvollständiges Jahr")
d["Umsatz_Mio"] = d["Netto_Umsatz"] / 1e6
d["Wachstum_Text"] = d["Wachstum_Vorjahr_Pct"].map(
    lambda v: "–" if pd.isna(v) else f"{de_zahl(v, 1)} %")
fig = px.bar(d, x="Jahr", y="Umsatz_Mio", color="Status",
             color_discrete_map={"vollständiges Jahr": BLAU, "unvollständiges Jahr": BLAU_HELL},
             custom_data=["Bestellungen", "Avg_Bestellwert", "Wachstum_Text", "Monate"])
fig.update_traces(hovertemplate=(
    "<b>%{x}</b><br>Netto-Umsatz: %{y:,.1f} Mio.<br>Bestellungen: %{customdata[0]:,.0f}"
    "<br>Ø Bestellwert: %{customdata[1]:,.0f}<br>Wachstum ggü. Vorjahr: %{customdata[2]}"
    "<br>Monate mit Daten: %{customdata[3]}<extra></extra>"))
fig.update_layout(xaxis_title=None, yaxis_title="Netto-Umsatz (Mio.)", xaxis_type="category")
st.plotly_chart(layout(fig, 360), width="stretch")
voll = d[d["Monate"] == 12]
if len(voll) >= 2:
    erstes, letztes = voll.iloc[0], voll.iloc[-1]
    veraend = 100 * (letztes["Netto_Umsatz"] / erstes["Netto_Umsatz"] - 1)
    st.caption(f"Vollständige Jahre {erstes['Jahr']} → {letztes['Jahr']}: "
               f"{de_mio(erstes['Netto_Umsatz'])} → {de_mio(letztes['Netto_Umsatz'])} "
               f"({'+' if veraend >= 0 else ''}{de_zahl(veraend, 1)} %).")
with st.expander("Daten anzeigen"):
    st.dataframe(df_umsatz, hide_index=True, width="stretch")

# ---------------------------------------------------------------------------
# 2. Top-Kunden (sql/04) und 3. Länder (sql/06)
# ---------------------------------------------------------------------------
links, rechts = st.columns(2, gap="large")

with links:
    st.subheader("Top-10-Kunden")
    d = df_kunden.sort_values("Netto_Umsatz")
    d["Label"] = d["Kunde"] + " (" + d["Land"].fillna("unbekannt") + ")"
    fig = px.bar(d, x="Netto_Umsatz", y="Label", orientation="h",
                 color_discrete_sequence=[BLAU],
                 custom_data=["Anteil_Pct", "Kum_Anteil_Pct", "Bestellungen"])
    fig.update_traces(hovertemplate=(
        "<b>%{y}</b><br>Netto-Umsatz: %{x:,.0f}<br>Anteil: %{customdata[0]:,.2f} %"
        "<br>Kumuliert: %{customdata[1]:,.1f} %<br>Bestellungen: %{customdata[2]}<extra></extra>"))
    fig.update_layout(xaxis_title="Netto-Umsatz")
    st.plotly_chart(horizontal(layout(fig, 420)), width="stretch")
    if len(df_kunden) >= 10:
        st.caption(f"Die Top 10 bringen zusammen {de_zahl(df_kunden['Kum_Anteil_Pct'].iloc[-1], 1)} % "
                   f"des Umsatzes; bei Gleichverteilung wären es "
                   f"{de_zahl(df_kunden['Gleichverteilung_Pct'].iloc[-1], 1)} %.")
    elif not df_kunden.empty:
        st.caption(f"In dieser Auswahl gibt es nur {len(df_kunden)} Kunde(n) mit Bestellungen.")
    with st.expander("Daten anzeigen"):
        st.dataframe(df_kunden, hide_index=True, width="stretch")

with rechts:
    st.subheader("Länder")
    # Der Vergleich 2013 vs. 2022 aus sql/06 ist nur sinnvoll, wenn beide Jahre im Filter liegen
    vergleich_moeglich = von <= 2013 and bis >= 2022
    kennzahl = st.radio("Kennzahl", ["Netto-Umsatz", "Veränderung 2022 vs. 2013"],
                        horizontal=True, label_visibility="collapsed",
                        disabled=not vergleich_moeglich)
    if not vergleich_moeglich:
        kennzahl = "Netto-Umsatz"
        st.caption("Der Vergleich 2022 vs. 2013 ist nur verfügbar, wenn der Jahresfilter beide Jahre enthält.")

    if kennzahl == "Netto-Umsatz":
        d = df_laender.sort_values("Umsatz_Gesamt")
        fig = px.bar(d, x="Umsatz_Gesamt", y="Land", orientation="h",
                     color_discrete_sequence=[BLAU],
                     custom_data=["Anteil_Pct", "Kunden", "Umsatz_pro_Kunde"])
        fig.update_traces(hovertemplate=(
            "<b>%{y}</b><br>Netto-Umsatz: %{x:,.0f}<br>Anteil: %{customdata[0]:,.1f} %"
            "<br>Kunden: %{customdata[1]}<br>Umsatz pro Kunde: %{customdata[2]:,.0f}<extra></extra>"))
        fig.update_layout(xaxis_title="Netto-Umsatz")
    else:
        d = df_laender.sort_values("Veraenderung_Pct")
        d["Richtung"] = d["Veraenderung_Pct"].map(lambda v: "Wachstum" if v >= 0 else "Rückgang")
        fig = px.bar(d, x="Veraenderung_Pct", y="Land", orientation="h", color="Richtung",
                     color_discrete_map={"Wachstum": BLAU, "Rückgang": ROT},
                     custom_data=["Umsatz_2013", "Umsatz_2022", "Kunden"])
        fig.update_traces(hovertemplate=(
            "<b>%{y}</b><br>Veränderung: %{x:+,.1f} %<br>2013: %{customdata[0]:,.0f}"
            "<br>2022: %{customdata[1]:,.0f}<br>Kunden: %{customdata[2]}<extra></extra>"))
        fig.update_layout(xaxis_title="Veränderung 2022 vs. 2013 (%)")
    st.plotly_chart(horizontal(layout(fig, 420 + 8 * max(len(d) - 10, 0))), width="stretch")
    with st.expander("Daten anzeigen"):
        st.dataframe(df_laender, hide_index=True, width="stretch")

# ---------------------------------------------------------------------------
# 4. Mitarbeiter (sql/09) und 5. Lieferperformance (sql/07)
# ---------------------------------------------------------------------------
links, rechts = st.columns(2, gap="large")

with links:
    st.subheader("Mitarbeiter")
    d = df_mitarb.sort_values("Netto_Umsatz")
    fig = px.bar(d, x="Netto_Umsatz", y="Mitarbeiter", orientation="h", color="Region",
                 color_discrete_map=REGION_FARBEN,
                 custom_data=["Titel", "Bestellungen", "Avg_Bestellwert", "Anteil_Pct"])
    fig.update_traces(hovertemplate=(
        "<b>%{y}</b> – %{customdata[0]}<br>Netto-Umsatz: %{x:,.0f}"
        "<br>Anteil: %{customdata[3]:,.1f} %<br>Bestellungen: %{customdata[1]:,.0f}"
        "<br>Ø Bestellwert: %{customdata[2]:,.0f}<extra></extra>"))
    fig.update_layout(xaxis_title="Netto-Umsatz",
                      yaxis={"categoryorder": "array", "categoryarray": d["Mitarbeiter"].tolist()})
    st.plotly_chart(horizontal(layout(fig, 420)), width="stretch")
    if not df_mitarb.empty:
        beste = df_mitarb.iloc[0]
        st.caption(f"Umsatzstärkste Person: {beste['Mitarbeiter']} ({de_zahl(beste['Anteil_Pct'], 1)} % "
                   f"Anteil). Spanne aller Mitarbeiter: {de_zahl(df_mitarb['Anteil_Pct'].min(), 1)}–"
                   f"{de_zahl(df_mitarb['Anteil_Pct'].max(), 1)} %.")
    with st.expander("Daten anzeigen"):
        st.dataframe(df_mitarb, hide_index=True, width="stretch")

with rechts:
    st.subheader("Lieferperformance")
    dimension = st.radio("Aufschlüsseln nach", ["Versender", "Mitarbeiter", "Zielland"],
                         horizontal=True, label_visibility="collapsed")
    d = df_liefer[df_liefer["Dimension"] == dimension].sort_values("Verspaetet_Pct")
    schnitt = 100 * d["Verspaetet"].sum() / d["Lieferungen"].sum() if len(d) else 0
    fig = px.bar(d, x="Verspaetet_Pct", y="Wert", orientation="h",
                 color_discrete_sequence=[BLAU],
                 custom_data=["Lieferungen", "Verspaetet", "Avg_Durchlaufzeit_Tage", "Avg_Tage_zu_spaet"])
    fig.update_traces(hovertemplate=(
        "<b>%{y}</b><br>Verspätet: %{x:,.1f} % (%{customdata[1]:,.0f} von %{customdata[0]:,.0f})"
        "<br>Ø Durchlaufzeit: %{customdata[2]:,.1f} Tage"
        "<br>Ø Verspätung (wenn verspätet): %{customdata[3]:,.1f} Tage<extra></extra>"))
    # Gestrichelte Linie: Durchschnitt über alle Lieferungen der gewählten Dimension
    fig.add_vline(x=schnitt, line_dash="dash", line_width=1, line_color="#52514e",
                  annotation_text=f"Ø {de_zahl(schnitt, 1)} %", annotation_position="top")
    fig.update_layout(xaxis_title="Anteil verspäteter Lieferungen (%)",
                      xaxis_range=[0, max(30, d["Verspaetet_Pct"].max() * 1.1) if len(d) else 30])
    st.plotly_chart(horizontal(layout(fig, 420 + 12 * max(len(d) - 10, 0))), width="stretch")
    st.caption("Verspätet = ShippedDate liegt nach RequiredDate. Noch nicht versendete Bestellungen "
               "sind nicht enthalten.")
    with st.expander("Daten anzeigen"):
        st.dataframe(d, hide_index=True, width="stretch")
