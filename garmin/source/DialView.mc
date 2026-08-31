import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

//! The 24 hour dial, the view the glance opens into.
//!
//! A port of the SVG in index.html and of DialRenderer.kt: the same 400 unit design grid, the same
//! geometry constants, the same palette, scaled to whichever tactix 8 panel it is running on. One
//! band per market, drawn at its own radius, green while that market is trading and grey while it
//! waits for its next session.
//!
//! The minute ring labels of the web app are dropped — illegible at watch size — and the hour
//! labels thin out on the smaller panel. What survives at every size is the ring of bands, which
//! is the thing the dial exists to show.
class DialView extends WatchUi.View {

    // ---------------------------------------------------------------------------------------
    // Design grid. Every constant below is in the web app's 400x400 SVG space and is scaled to
    // the device in `onLayout`, so the three implementations stay comparable line by line.
    // ---------------------------------------------------------------------------------------

    private const GRID = 400.0;
    private const BAND_OUTER = 157.0;       //! radius of the outermost band's outer edge
    private const RING_RADIUS = 177.0;      //! centre line of the hour ring
    private const RING_WIDTH = 22.0;

    //! The band stack is tighter than the web app's 7.2 wide, 9.0 apart. In the browser the bands
    //! run all the way down to a radius of 36 and the hands sweep over them; on a watch that
    //! leaves nowhere legible for the summary, and covering the centre with it would hide the
    //! innermost markets — which happen to be the American ones, not the ones anyone would choose
    //! to lose. Narrowing the stack keeps every market visible and clears a disc to write in.
    private const BAND_WIDTH = 4.6;
    //! The summary disc, sitting inside the innermost band. Its size is a direct trade against
    //! band spacing — every unit of radius here is a unit the stack cannot use — and it is set by
    //! the narrowest thing written in it: the bottom row, furthest from the centre and so on the
    //! shortest chord, which has to hold a countdown like "12h 05m" without falling back to a
    //! coarser one.
    private const CARTOUCHE_RADIUS = 76.0;
    private const CARTOUCHE_CLEARANCE = 4.0;

    //! Spacing between bands is not a constant: it is solved in `onLayout` from however many
    //! markets the table holds, so that the innermost band always lands just outside the summary
    //! disc. Adding a market tightens the stack instead of burying it.
    private var _bandStep as Float = 6.0;

    //! A 24 hour dial has no use for a minute or second hand: the whole face is one revolution per
    //! day, so the hour hand alone says where in the day you are, and the other two would sweep a
    //! scale they do not belong to. One marker replaces all three, and it starts at the edge of the
    //! summary disc so it never crosses the text.
    private const NOW_MARKER_OUTER = 150.0;
    private const NOW_MARKER_GAP = 5.0;     //! clearance between the disc and the marker's tail

    private const MINUTES_PER_DAY = 1440;

    //! Device pixels per design unit, and the screen centre in pixels.
    private var _scale as Float = 1.0;
    private var _centerX as Number = 0;
    private var _centerY as Number = 0;

    //! Hour numerals get crowded on the 280x280 panel, so label every sixth hour there and every
    //! third on the 454x454 one. Resolved once in `onLayout`.
    private var _hourLabelStep as Number = 3;

    //! Fonts chosen against the panel size rather than assumed.
    private var _statusFont as FontDefinition = Graphics.FONT_TINY;
    private var _detailFont as FontDefinition = Graphics.FONT_XTINY;
    private var _hourFont as FontDefinition = Graphics.FONT_XTINY;

    //! Redraws the dial as time passes. Only ever alive while this view is on screen, which is why
    //! it is started in `onShow` rather than in `initialize`.
    private var _ticker as Timer.Timer?;

    //! Nothing on this dial moves faster than a minute — the now marker creeps a quarter of a
    //! degree per minute and the countdown is quoted in minutes — so a fifteen second tick keeps
    //! it honest without redrawing fourteen arcs every second for no visible change.
    private const TICK_MS = 15000;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        if (_ticker == null) {
            _ticker = new Timer.Timer();
        }
        (_ticker as Timer.Timer).start(method(:onTick), TICK_MS, true);
    }

    function onHide() as Void {
        if (_ticker != null) {
            (_ticker as Timer.Timer).stop();
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onLayout(dc as Dc) as Void {
        var size = dc.getWidth() < dc.getHeight() ? dc.getWidth() : dc.getHeight();

        _scale = size / GRID;
        _centerX = dc.getWidth() / 2;
        _centerY = dc.getHeight() / 2;
        _hourLabelStep = size >= 400 ? 3 : 6;

        // Fit the stack between the outermost edge and the summary disc. Both radii below are of
        // the band's centre line, which is half a band width inside its own edge.
        var outermost = BAND_OUTER - BAND_WIDTH / 2.0;
        var innermost = CARTOUCHE_RADIUS + CARTOUCHE_CLEARANCE + BAND_WIDTH / 2.0;
        var gaps = Markets.count() - 1;
        _bandStep = gaps > 0 ? (outermost - innermost) / gaps : 0.0;

        if (size >= 400) {
            _statusFont = Graphics.FONT_MEDIUM;
            _detailFont = Graphics.FONT_XTINY;
            _hourFont = Graphics.FONT_XTINY;
        } else {
            _statusFont = Graphics.FONT_TINY;
            _detailFont = Graphics.FONT_XTINY;
            _hourFont = Graphics.FONT_XTINY;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var now = Time.now().value();

        dc.setColor(Graphics.COLOR_TRANSPARENT, Palette.DIAL_BG);
        dc.clear();

        drawRing(dc);
        var aggregate = drawBands(dc, now);
        drawNowMarker(dc, now);
        drawCartouche(dc, aggregate, now);
    }

    // ---------------------------------------------------------------------------------------
    // Dial furniture
    // ---------------------------------------------------------------------------------------

    //! The hour ring and its numerals. Hour 24 sits at the top, so the dial reads as a day
    //! rather than as a clock: midnight up, noon down.
    private function drawRing(dc as Dc) as Void {
        dc.setColor(Palette.RING, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(px(RING_WIDTH));
        dc.drawCircle(_centerX, _centerY, px(RING_RADIUS));

        dc.setColor(Palette.RING_TEXT, Graphics.COLOR_TRANSPARENT);
        var half = dc.getFontHeight(_hourFont) / 2;

        for (var hour = _hourLabelStep; hour <= 24; hour += _hourLabelStep) {
            var degrees = hour / 24.0 * 360.0;
            dc.drawText(
                polarX(RING_RADIUS, degrees),
                polarY(RING_RADIUS, degrees) - half,
                _hourFont,
                hour.format("%02d"),
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! One band per market, outermost first, in table order. Returns the aggregate from the same
    //! sweep so the cartouche does not have to resolve every market a second time.
    private function drawBands(dc as Dc, now as Number) as Array<Number> {
        var openCount = 0;
        var soonestIndex = Sessions.NONE;
        var soonestAt = Sessions.NONE;
        var soonestIsClose = 0;

        dc.setPenWidth(px(BAND_WIDTH));

        for (var i = 0; i < Markets.count(); i += 1) {
            var state = Sessions.stateOf(i, now);
            var isOpen = state[Sessions.STATE_IS_OPEN] == 1;

            if (isOpen) {
                openCount += 1;
            }

            var at = state[Sessions.STATE_TRANSITION];
            if (at != Sessions.NONE && (soonestAt == Sessions.NONE || at < soonestAt)) {
                soonestAt = at;
                soonestIndex = i;
                soonestIsClose = state[Sessions.STATE_IS_OPEN];
            }

            var start = state[Sessions.STATE_START];
            var end = state[Sessions.STATE_END];
            if (start == Sessions.NONE || end == Sessions.NONE) {
                continue;
            }

            // Bands stack inwards, each one step narrower in radius than the last, and the band's
            // centre line sits half a band width inside its nominal outer edge.
            var radius = BAND_OUTER - i * _bandStep - BAND_WIDTH / 2.0;

            dc.setColor(isOpen ? Palette.OPEN : Palette.CLOSED, Graphics.COLOR_TRANSPARENT);
            drawSessionArc(dc, radius, start, end);
        }

        return [openCount, soonestIndex, soonestAt, soonestIsClose] as Array<Number>;
    }

    //! A session drawn as an arc between its open and close positions on the 24 hour dial.
    private function drawSessionArc(dc as Dc, radius as Float, start as Number, end as Number) as Void {
        var from = Sessions.displayMinuteOfDay(start) / MINUTES_PER_DAY * 360.0;
        var to = Sessions.displayMinuteOfDay(end) / MINUTES_PER_DAY * 360.0;

        var sweep = to - from;
        if (sweep <= 0) {
            sweep += 360.0;                 // the session straddles local midnight
        }
        if (sweep < 1.0) {
            sweep = 1.0;                    // never collapse to the "equal angles" full circle
        }
        if (sweep > 359.0) {
            sweep = 359.0;
        }

        // Dial angles run clockwise from midnight at the top; Dc angles run counter-clockwise from
        // the 3 o'clock position, so the two are related by `dcAngle = 90 - dialAngle`.
        var dcStart = normalise(90.0 - from);
        var dcEnd = normalise(90.0 - (from + sweep));

        dc.drawArc(_centerX, _centerY, px(radius), Graphics.ARC_CLOCKWISE, dcStart, dcEnd);
    }

    //! The now marker: one radial line at the current time of day, turning once per day so that
    //! the band it points into is the session happening right now.
    private function drawNowMarker(dc as Dc, now as Number) as Void {
        var degrees = Sessions.displayMinuteOfDay(now) / MINUTES_PER_DAY * 360.0;
        var inner = CARTOUCHE_RADIUS + NOW_MARKER_GAP;

        dc.setColor(Palette.HAND, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(px(5.0));
        dc.drawLine(
            polarX(inner, degrees), polarY(inner, degrees),
            polarX(NOW_MARKER_OUTER, degrees), polarY(NOW_MARKER_OUTER, degrees));

        // A tip dot the width of the marker, so the exact minute stays readable where the line
        // crosses the outermost band.
        dc.fillCircle(
            polarX(NOW_MARKER_OUTER, degrees), polarY(NOW_MARKER_OUTER, degrees), px(4.0));
    }

    //! The summary disc at the centre: how many markets are trading, and what flips next.
    //!
    //! It sits on top of the hands rather than under them. The hands still read clearly from the
    //! disc's edge outwards, and the count is the one thing worth being able to take in without
    //! tracing a band around the dial.
    private function drawCartouche(dc as Dc, aggregate as Array<Number>, now as Number) as Void {
        var openCount = aggregate[Sessions.SUMMARY_OPEN_COUNT];
        var nextIndex = aggregate[Sessions.SUMMARY_INDEX];
        var nextAt = aggregate[Sessions.SUMMARY_AT];

        var radius = px(CARTOUCHE_RADIUS);

        dc.setColor(Palette.DIAL_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, radius);

        // The rim takes the colour of the answer, so the dial reads open or shut from across a
        // room before any of the text resolves.
        dc.setColor(openCount > 0 ? Palette.OPEN : Palette.CLOSED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(px(2.0));
        dc.drawCircle(_centerX, _centerY, radius);

        // Three short rows rather than two longer ones. A circle is a poor shape for a line of
        // text — "NYSE 2h 14m" is wider than this disc is anywhere, at the smallest font Garmin
        // ships — but a fine shape for a stack of short ones, and stacking keeps all three facts:
        // how many markets are trading, which one moves next, and how long until it does.
        var countHeight = dc.getFontHeight(_statusFont);
        var rowHeight = dc.getFontHeight(_detailFont);
        var hasNext = nextIndex != Sessions.NONE && nextAt != Sessions.NONE;

        var y = _centerY - (countHeight + (hasNext ? 2 * rowHeight : 0)) / 2;

        dc.drawText(
            _centerX,
            y,
            _statusFont,
            openCount > 0 ? openCount.format("%d") : "0",
            Graphics.TEXT_JUSTIFY_CENTER);
        y += countHeight;

        if (!hasNext) {
            return;
        }

        dc.setColor(Palette.DIM, Graphics.COLOR_TRANSPARENT);

        dc.drawText(_centerX, y, _detailFont,
            fit(dc, _detailFont, chordAt(radius, y, y + rowHeight),
                [Markets.CODES[nextIndex]] as Array<String>),
            Graphics.TEXT_JUSTIFY_CENTER);
        y += rowHeight;

        dc.drawText(_centerX, y, _detailFont,
            fit(dc, _detailFont, chordAt(radius, y, y + rowHeight), [
                Sessions.formatGap(nextAt - now),
                Sessions.formatGapCompact(nextAt - now),
                Sessions.formatGapHours(nextAt - now)
            ] as Array<String>),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! How wide a line of text may be to stay inside the summary disc.
    //!
    //! The disc is a circle, so the room a row has depends on how far it sits from the centre: the
    //! binding constraint is whichever of the row's two edges is further out. Deriving it beats
    //! guessing at a fraction of the diameter, which either wastes half the disc or overruns it.
    private function chordAt(radius as Number, rowTop as Number, rowBottom as Number) as Number {
        var above = _centerY - rowTop;
        var below = rowBottom - _centerY;
        var furthest = above > below ? above : below;

        if (furthest >= radius) {
            return 0;
        }

        var half = Math.sqrt(radius * radius - furthest * furthest);
        var usable = (2 * half).toNumber() - px(4.0);   // a hair of clearance off the rim
        return usable < 0 ? 0 : usable;
    }

    //! The first candidate that fits, or the last one if none do — the same measure-then-choose
    //! approach the glance uses, for the same reason: string widths are not knowable up front.
    private function fit(
        dc as Dc,
        font as FontDefinition,
        usable as Number,
        candidates as Array<String>
    ) as String {
        for (var i = 0; i < candidates.size(); i += 1) {
            if (dc.getTextWidthInPixels(candidates[i], font) <= usable) {
                return candidates[i];
            }
        }
        return candidates[candidates.size() - 1];
    }

    // ---------------------------------------------------------------------------------------
    // Geometry helpers, matching `polar()` in index.html: zero degrees is straight up and angles
    // increase clockwise.
    // ---------------------------------------------------------------------------------------

    private function px(designUnits as Numeric) as Number {
        var scaled = (designUnits * _scale + 0.5).toNumber();
        return scaled < 1 ? 1 : scaled;
    }

    private function polarX(radius as Float, degrees as Float) as Number {
        var radians = (degrees - 90.0) * Math.PI / 180.0;
        return _centerX + (radius * _scale * Math.cos(radians)).toNumber();
    }

    private function polarY(radius as Float, degrees as Float) as Number {
        var radians = (degrees - 90.0) * Math.PI / 180.0;
        return _centerY + (radius * _scale * Math.sin(radians)).toNumber();
    }

    //! Fold an angle into [0, 360). Written as a loop because Monkey C's `%` is integer only and
    //! rounding through a Number here would visibly quantise the arcs.
    private function normalise(degrees as Float) as Float {
        var d = degrees;
        while (d < 0.0) {
            d += 360.0;
        }
        while (d >= 360.0) {
            d -= 360.0;
        }
        return d;
    }
}
