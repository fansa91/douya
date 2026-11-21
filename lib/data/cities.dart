/// Built-in city table for the now-playing (showing) filter.
/// There is no city-list API (probed 2026-11-21: 7 Rexxar + 3
/// Frodo candidates all 404; the official app takes the city from
/// the device location instead). Each id below was verified twice:
/// the city's Douban cinema search page carries it in the
/// pagination links (?start=20&q=&city_id=NNNNNN), and the Rexxar
/// /movie/movie_showing endpoint returns 200 with a real total for
/// it (totals in the comment are the 2026-11-21 values; they move
/// as films open and close).
class ShowingCity {
  const ShowingCity(this.name, this.locId);

  final String name;
  final int locId;
}

const showingCities = <ShowingCity>[
  ShowingCity('北京', 108288), // 67
  ShowingCity('上海', 108296), // 86
  ShowingCity('广州', 118281), // 70
  ShowingCity('深圳', 118282), // 68
  ShowingCity('成都', 118318), // 61
  ShowingCity('杭州', 118172), // 68
  ShowingCity('武汉', 118254), // 60
  ShowingCity('西安', 118371), // 60
  ShowingCity('南京', 118159), // 57
  ShowingCity('重庆', 108309), // 51
  ShowingCity('天津', 108289), // 42
  ShowingCity('苏州', 118163), // 55
];

ShowingCity? showingCityById(int locId) {
  for (final city in showingCities) {
    if (city.locId == locId) return city;
  }
  return null;
}
