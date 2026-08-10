from dataclasses import dataclass


@dataclass(frozen=True)
class Location:
    name: str
    latitude: float
    longitude: float


# Chosen to span distinct climate-risk profiles rather than arbitrary coverage:
# Zurich as a low-volatility baseline, Mexico City/Madrid/Mumbai each anchoring a
# hazard the platform is expected to grow into (seismic, heat, flooding) even though
# the Open-Meteo forecast fields pulled today only cover the weather-driven ones.
LOCATIONS = [
    Location("Zurich", 47.3769, 8.5417),
    Location("Mexico City", 19.4326, -99.1332),
    Location("Madrid", 40.4168, -3.7038),
    Location("Mumbai", 19.0760, 72.8777),
]
