const station = "odpt.Station:TokyoMetro.Ginza.Ueno";
const direction = "odpt.RailDirection:TokyoMetro.Asakusa";

async function main() {
  const url = new URL("https://api.odpt.org/api/v4/odpt:StationTimetable");
  url.searchParams.set("odpt:station", station);
  url.searchParams.set("odpt:railDirection", direction);
  const key = process.env.ODPT_CONSUMER_KEY;
  if (key) url.searchParams.set("acl:consumerKey", key);

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    const hint = [401, 403].includes(response.status) ? " Check ODPT_CONSUMER_KEY." : "";
    throw new Error(`ODPT returned HTTP ${response.status}.${hint}`);
  }

  const tables = await response.json();
  if (!Array.isArray(tables) || tables.length === 0) {
    throw new Error("ODPT returned no station timetables for Ueno towards Asakusa.");
  }
  for (const table of tables) {
    if (table?.["odpt:station"] !== station || table["odpt:railDirection"] !== direction ||
        typeof table["odpt:calendar"] !== "string" || !Array.isArray(table["odpt:stationTimetableObject"])) {
      throw new Error("ODPT returned an unexpected station timetable.");
    }
  }
  console.log(JSON.stringify(tables, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
