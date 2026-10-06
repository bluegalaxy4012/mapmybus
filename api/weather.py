import httpx
from datetime import datetime
import time
from core import logger, AGENCY_IDS

# de reverificat

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

AGENCY_COORDS = {
    "1": (47.1621, 27.5876),
    "2": (46.7704, 23.5914),
    "4": (47.0236, 28.8339),
    "6": (47.7399, 26.6632),
    "10": (44.1830, 28.6400),
}

LABELS = {
    0: "senin",
    1: "predominant senin",
    2: "partial noros",
    3: "innorat",
    45: "ceata",
    48: "ceata cu depunere de gheata",
    51: "burnita slaba",
    53: "burnita",
    55: "burnita densa",
    61: "ploaie slaba",
    63: "ploaie",
    65: "ploaie torentiala",
    66: "ploaie inghetata",
    67: "ploaie inghetata puternica",
    71: "ninsoare slaba",
    73: "ninsoare",
    75: "ninsoare abundenta",
    77: "grindina mica",
    80: "averse slabe",
    81: "averse",
    82: "averse violente",
    85: "averse de zapada",
    86: "averse puternice de zapada",
    95: "furtuna",
    96: "furtuna cu grindina",
    99: "furtuna puternica cu grindina",
}


def _assess(code: int, precip: float, gusts: float, temp: float):
    "-> (multiplier, reliability, message|None)"
    mult, rel, msg = 1.0, "good", None

    if code in (66, 67) or (code in (71, 73, 75, 77, 85, 86)):
        mult, rel = (1.30 if code in (66, 67, 75, 86) else 1.18), "poor"
        msg = "Ninsoare/polei in apropiere - vehiculele pot avea intarzieri mari."
    elif code in (95, 96, 99):
        mult, rel = 1.18, "poor"
        msg = "Furtuna in apropiere - traficul poate fi perturbat."
    elif precip >= 2.5 or code in (65, 82):
        mult, rel = 1.12, "reduced"
        msg = "Ploaie in apropiere - traficul poate fi perturbat."
    elif precip >= 0.3 or code in (61, 63, 80, 81, 51, 53, 55):
        mult, rel = 1.06, "reduced"
        msg = "Ploaie in apropiere - traficul poate fi perturbat."
    elif code in (45, 48):
        mult, rel = 1.06, "reduced"
        msg = "Ceata in apropiere - traficul poate fi perturbat."

    if gusts >= 60:
        mult += 0.03
        rel = "reduced" if rel == "good" else rel
        msg = msg or "Vant puternic in apropiere - traficul poate fi perturbat."
    if temp <= -5:
        mult += 0.03

    return round(mult, 3), rel, msg


async def fetch_weather(agency_id: str) -> dict | None:
    coords = AGENCY_COORDS.get(agency_id)
    if not coords:
        return None
    lat, lon = coords
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,precipitation,weather_code,wind_gusts_10m",
        "timezone": "Europe/Bucharest",
    }
    async with httpx.AsyncClient() as client:
        r = await client.get(OPEN_METEO_URL, params=params, timeout=8)
    if r.status_code != 200:
        return None

    cur = r.json().get("current", {})
    code = int(cur.get("weather_code", 0))
    precip = float(cur.get("precipitation", 0) or 0)
    gusts = float(cur.get("wind_gusts_10m", 0) or 0)
    temp = float(cur.get("temperature_2m", 15) or 15)

    mult, rel, msg = _assess(code, precip, gusts, temp)
    return {
        "agency_id": agency_id,
        "temperature": temp,
        "precipitation": precip,
        "wind_gusts": gusts,
        "code": code,
        "label": LABELS.get(code, "necunoscut"),
        "eta_reliability": rel,
        "eta_multiplier": mult,
        "message": msg,
        "updated_at": datetime.now().isoformat(timespec="seconds"),
    }


weather_state: dict[str, dict] = {}
_last_weather_fetch = 0.0
DEFAULT_WEATHER = {"eta_reliability": "good", "message": None}


async def refresh_weather():
    global _last_weather_fetch
    if time.time() - _last_weather_fetch < 600:  # 10 min
        return
    _last_weather_fetch = time.time()
    for agency_id in AGENCY_IDS:
        try:
            w = await fetch_weather(agency_id)
            if w:
                weather_state[agency_id] = w
        except Exception as e:
            logger.warning("weather fetch failed for %s: %s", agency_id, e)


async def get_cached_weather(agency_id: str) -> dict:
    if agency_id not in weather_state:
        try:
            w = await fetch_weather(agency_id)
            if w:
                weather_state[agency_id] = w
        except Exception as e:
            logger.warning("weather fetch failed for %s: %s", agency_id, e)
    return weather_state.get(agency_id, DEFAULT_WEATHER)
