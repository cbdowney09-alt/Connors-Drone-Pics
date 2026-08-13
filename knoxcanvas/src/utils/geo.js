export function pointInPolygon(lat, lng, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i][0], yi = polygon[i][1], xj = polygon[j][0], yj = polygon[j][1];
    if (((yi > lng) !== (yj > lng)) && (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi)) inside = !inside;
  }
  return inside;
}

export function distBetween(a, b) {
  return Math.sqrt(Math.pow((b.lat - a.lat) * 111000, 2) + Math.pow((b.lng - a.lng) * 111000 * Math.cos(a.lat * Math.PI / 180), 2));
}

export function optimizeRoute(start, stops) {
  const remaining = [...stops], route = [];
  let current = start;
  while (remaining.length > 0) {
    let nearestIdx = 0, nearestDist = Infinity;
    remaining.forEach((s, i) => { const d = distBetween(current, s); if (d < nearestDist) { nearestDist = d; nearestIdx = i; } });
    route.push(remaining[nearestIdx]); current = remaining[nearestIdx]; remaining.splice(nearestIdx, 1);
  }
  return route;
}

export function getNeighborhoodYearForPoint(lat, lng, neighborhoodYears) {
  for (const zone of neighborhoodYears) {
    if (zone.polygon && zone.polygon.length >= 3 && pointInPolygon(lat, lng, zone.polygon)) return zone.year;
    if (zone.radius) {
      const dist = Math.sqrt(Math.pow((lat - zone.lat) * 111000, 2) + Math.pow((lng - zone.lng) * 111000 * Math.cos(zone.lat * Math.PI / 180), 2));
      if (dist <= zone.radius) return zone.year;
    }
  }
  return '';
}
