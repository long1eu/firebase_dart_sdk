# Capturing gtag.js traffic

The steps the owner of the project follows to record what gtag.js sends, for the planned gtag transport
([docs/analytics_gtag.md](../docs/analytics_gtag.md)). Nothing in this repository sends the requests: a browser
runs gtag.js from a local page, and the developer tools record what it sends.

## Before

- Use a **test** GA4 property with a web data stream, not a production one. Its measurement id (`G-…`) is all
  the page needs; no API secret is involved.
- Use a clean browser profile, or a private window, so that no extension or earlier cookie changes the requests.
- Turn off ad and tracking blockers for `localhost`: they block `/g/collect`.

## Steps

1. Serve the page from this directory, so that it runs on `http://localhost` and not from a file:

       cd tool && python3 -m http.server 8765

2. Open the developer tools, Network tab, with "Preserve log" on and the filter set to `collect`.
3. Open `http://localhost:8765/gtag_capture.html?id=G-XXXXXXXXXX` with the test stream's id. Loading the page
   sends the page view.
4. Press buttons 1 to 8 in order, a few seconds apart. gtag.js may hold events back and send them together;
   that batching is part of what the capture should show, so do not hurry it.
5. Wait 30 seconds, then reload the page once: the second page view in the same session.
6. In GA4, open DebugView and check that the `capture_debug` event of step 7 is there. Note whether the other
   events show in Realtime.

## Saving

Right-click in the request list, then "Save all as HAR". The file holds the measurement id, the client id from
the `_ga` cookie, the address of the server and the user agent: keep it **outside this repository**,
with the other files of the owner that are not public.

Then write down, for the planned transport:

- the browser and its version, and the date;
- the version of gtag.js: the `gtm` parameter, or the `Last-Modified` of the script;
- whether the events showed in DebugView and in Realtime.

The plan is updated from the HAR file. Its identifiers are replaced by placeholders before any request goes
into a test.
