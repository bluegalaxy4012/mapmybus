import datetime

# luni - joi
_weekday_index = {
    0: 0.7, 1: 0.65, 2: 0.65, 3: 0.65, 4: 0.8, 5: 0.95,
    6: 1.1, 7: 1.25, 8: 1.3, 9: 1.225, 10: 1.125, 11: 1.075,
    12: 1.075, 13: 1.125, 14: 1.2, 15: 1.25, 16: 1.3, 17: 1.35,
    18: 1.3, 19: 1.15, 20: 1.1, 21: 1.0, 22: 0.9, 23: 0.8
}

# vineri incepe un pic mai devreme si mai puternic aglomeratia de dupamasa
_friday_index = {
    0: 0.7, 1: 0.65, 2: 0.65, 3: 0.65, 4: 0.8, 5: 0.95,
    6: 1.1, 7: 1.25, 8: 1.3, 9: 1.225, 10: 1.125, 11: 1.1,
    12: 1.1, 13: 1.15, 14: 1.25, 15: 1.3, 16: 1.35, 17: 1.38,
    18: 1.35, 19: 1.25, 20: 1.2, 21: 1.1, 22: 1.0, 23: 0.9
}

# sambata doar shopping aduce aglomeratie
_saturday_index = {
    0: 0.7, 1: 0.7, 2: 0.675, 3: 0.675, 4: 0.75, 5: 0.75,
    6: 0.8, 7: 0.9, 8: 1.0, 9: 1.05, 10: 1.05, 11: 1.1,
    12: 1.125, 13: 1.125, 14: 1.125, 15: 1.1, 16: 1.1, 17: 1.05,
    18: 1.0, 19: 0.95, 20: 0.9, 21: 0.875, 22: 0.825, 23: 0.8
}

# duminica e chill, doar seara poate revin oameni in oras
_sunday_index = {
    0: 0.7, 1: 0.675, 2: 0.65, 3: 0.65, 4: 0.675, 5: 0.7,
    6: 0.75, 7: 0.8, 8: 0.85, 9: 0.95, 10: 1.0, 11: 1.00,
    12: 1.025, 13: 1.05, 14: 1.05, 15: 1.05, 16: 1.05,
    17: 1.075, 18: 1.05, 19: 1.0, 20: 0.925, 21: 0.85, 22: 0.8, 23: 0.75
}

# datele folosite sunt, ca dimensiune, 50% din toamna, 50% din vara
# si probabil ca aglomeratie vara < primavara <= toamna < iarna
# din aceste motive probabil cam asa ar fi
_seasonal_multipliers = {
    "winter": 1.1,
    "spring": 1.025,
    "summer": 0.95,
    "autumn": 1.05
}


def get_timestamp_congestion_index(timestamp: datetime.datetime) -> float:
    day = timestamp.weekday()
    hour = timestamp.hour
    month = timestamp.month

    if day < 4:
        base_index_map = _weekday_index
    elif day == 4:
        base_index_map = _friday_index
    elif day == 5:
        base_index_map = _saturday_index
    else:
        base_index_map = _sunday_index
    
    base_congestion = base_index_map.get(hour, 1.0)

    if month in [12, 1, 2]:
        season_multiplier = _seasonal_multipliers["winter"]
    elif month in [3, 4, 5]:
        season_multiplier = _seasonal_multipliers["spring"]
    elif month in [6, 7, 8]:
        season_multiplier = _seasonal_multipliers["summer"]
    else:
        season_multiplier = _seasonal_multipliers["autumn"]

    return base_congestion * season_multiplier
