import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! The glance: one strip in the glance list answering "is anything trading, and what moves next".
//!
//! Everything reachable from here carries the `(:glance)` annotation, which is what keeps the
//! glance build inside the 64 KB ceiling this device allows — the dial view and its timer are
//! deliberately outside that set and never loaded in glance mode.
//!
//! Layout is derived from the `Dc` rather than hard coded, because the glance strip is a different
//! shape on the 454x454 AMOLED tactix 8 than on the 280x280 Solar, and Garmin does not promise a
//! fixed height on either.
(:glance)
class MarketSessionsGlanceView extends WatchUi.GlanceView {

    //! Live sessions as [start, end, start, end, ...], reused across redraws so a glance update
    //! allocates nothing. Sized for the worst case of every market trading at once.
    private var _windows as Array<Number>;

    //! Minutes in a day, the width the timeline maps onto. Held as a Float because it is both a
    //! divisor of Float minutes and an argument to `fillSpan`, and Monkey C will not widen a
    //! Number into a Float parameter on its own.
    private const MINUTES_PER_DAY = 1440.0;

    function initialize() {
        GlanceView.initialize();
        _windows = new Array<Number>[Markets.count() * 2];
    }

    function onUpdate(dc as Dc) as Void {
        var now = Time.now().value();

        var aggregate = Sessions.scan(now, _windows);
        var openCount = aggregate[Sessions.SUMMARY_OPEN_COUNT];
        var nextIndex = aggregate[Sessions.SUMMARY_INDEX];
        var nextAt = aggregate[Sessions.SUMMARY_AT];
        var nextIsClose = aggregate[Sessions.SUMMARY_IS_CLOSE];

        var width = dc.getWidth();
        var height = dc.getHeight();
        var middle = width / 2;

        // The Dc the system hands a glance is a plain rectangle — 349x130 on the tactix 8 — and it
        // is wider than the round glass at the rows nearest the top of the band. Pixels drawn out
        // there are simply not on the display, so text gets a real margin while the timeline, which
        // sits at the bottom of the band where the chord is widest, gets a token one.
        var textInset = (width * 0.10).toNumber();
        var barInset = (width * 0.03).toNumber();
        var textWidth = width - 2 * textInset;

        var padY = (height * 0.04).toNumber();
        if (padY < 2) {
            padY = 2;
        }

        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        // FONT_GLANCE is 42px tall here, which is right for the headline and far too wide for a
        // sentence: at that size not even "TYO opens 2h 33m" clears the glass. The supporting rows
        // drop to the smallest face Garmin ships so they can say the whole thing, which also gives
        // the glance the hierarchy it should have had anyway — one number to read, one line to
        // read if you care.
        var headlineHeight = dc.getFontHeight(Graphics.FONT_GLANCE);
        var detailHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var captionHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var barHeight = (height * 0.10).toNumber();
        if (barHeight < 4) {
            barHeight = 4;
        }

        // Rows are dropped from the least informative end when the band is short: the caption
        // first, because it only carries identity, then the detail line.
        var available = height - barHeight - 2 * padY;
        var showCaption = available >= captionHeight + headlineHeight + detailHeight;
        var showDetail = available >= headlineHeight + detailHeight;

        var y = padY;
        if (showCaption) {
            dc.setColor(Palette.DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(middle, y, Graphics.FONT_XTINY,
                fit(dc, Graphics.FONT_XTINY, textWidth, ["MARKET SESSIONS", "MARKETS"]),
                Graphics.TEXT_JUSTIFY_CENTER);
            y += captionHeight;
        }

        dc.setColor(openCount > 0 ? Palette.OPEN : Palette.CLOSED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(middle, y, Graphics.FONT_GLANCE,
            fit(dc, Graphics.FONT_GLANCE, textWidth,
                headline(openCount, nextIndex, nextAt, nextIsClose, now, showDetail)),
            Graphics.TEXT_JUSTIFY_CENTER);
        y += headlineHeight;

        if (showDetail) {
            dc.setColor(Palette.DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(middle, y, Graphics.FONT_XTINY,
                fit(dc, Graphics.FONT_XTINY, textWidth, detail(nextIndex, nextAt, nextIsClose, now)),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        drawTimeline(dc, barInset, height - padY - barHeight, width - 2 * barInset, barHeight,
            openCount, now);
    }

    //! Candidate headlines, widest first.
    //!
    //! When the band is tall enough for a detail line of its own the headline is just the count.
    //! When it is not, the next transition is folded onto the end of it, because a count with no
    //! sense of what happens next is the less useful half of the pair.
    private function headline(
        openCount as Number,
        nextIndex as Number,
        nextAt as Number,
        nextIsClose as Number,
        now as Number,
        detailHasItsOwnRow as Boolean
    ) as Array<String> {
        var head = openCount > 0 ? Lang.format("$1$ OPEN", [openCount]) : "ALL CLOSED";

        if (detailHasItsOwnRow || nextIndex == Sessions.NONE || nextAt == Sessions.NONE) {
            return [head] as Array<String>;
        }

        var verb = nextIsClose == 1 ? "closes" : "opens";
        var gap = Sessions.formatGap(nextAt - now);
        return [
            Lang.format("$1$ · $2$ $3$ $4$", [head, Markets.CODES[nextIndex], verb, gap]),
            Lang.format("$1$ · $2$ $3$", [head, Markets.CODES[nextIndex], gap]),
            head
        ] as Array<String>;
    }

    //! Candidate detail lines, widest first: the full market name if it fits, the exchange code
    //! if it does not. The countdown is never dropped — it is the part that changes.
    private function detail(
        nextIndex as Number,
        nextAt as Number,
        nextIsClose as Number,
        now as Number
    ) as Array<String> {
        if (nextIndex == Sessions.NONE || nextAt == Sessions.NONE) {
            return [""] as Array<String>;
        }

        var verb = nextIsClose == 1 ? "closes" : "opens";
        var gap = Sessions.formatGap(nextAt - now);

        return [
            Lang.format("$1$ $2$ in $3$", [Markets.NAMES[nextIndex], verb, gap]),
            Lang.format("$1$ $2$ $3$", [Markets.NAMES[nextIndex], verb, gap]),
            Lang.format("$1$ $2$ $3$", [Markets.CODES[nextIndex], verb, gap]),
            Lang.format("$1$ $2$", [Markets.CODES[nextIndex], gap])
        ] as Array<String>;
    }

    //! The first candidate that fits the width, or the last one if none of them do. Measuring is
    //! cheaper than guessing: the same string is a different width in every font Garmin ships, and
    //! none of them are the same size on the two tactix 8 panels.
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

    //! A 24 hour timeline of the local day, green wherever some market is trading, with a marker
    //! at the current time. Overlapping sessions simply overdraw, which is the point: the depth of
    //! the green is not the information, the coverage of the day is.
    private function drawTimeline(
        dc as Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number,
        openCount as Number,
        now as Number
    ) as Void {
        var radius = height / 2;

        dc.setColor(Palette.TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, width, height, radius);

        dc.setColor(Palette.OPEN, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < openCount; i += 1) {
            var from = Sessions.displayMinuteOfDay(_windows[i * 2]);
            var to = Sessions.displayMinuteOfDay(_windows[i * 2 + 1]);

            if (to > from) {
                fillSpan(dc, x, y, width, height, radius, from, to);
            } else {
                // The session straddles local midnight, so it lands at both ends of the day.
                fillSpan(dc, x, y, width, height, radius, from, MINUTES_PER_DAY);
                fillSpan(dc, x, y, width, height, radius, 0.0, to);
            }
        }

        // The now marker sits above the sessions and is drawn in the hand colour, tying it to the
        // same instant the dial's hands point at.
        var nowX = x + (Sessions.displayMinuteOfDay(now) / MINUTES_PER_DAY * width).toNumber();
        dc.setColor(Palette.HAND, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(nowX, y - 1, nowX, y + height + 1);
    }

    //! One span of the timeline, in minutes of the local day.
    private function fillSpan(
        dc as Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number,
        radius as Number,
        fromMinute as Float,
        toMinute as Float
    ) as Void {
        var left = x + (fromMinute / MINUTES_PER_DAY * width).toNumber();
        var right = x + (toMinute / MINUTES_PER_DAY * width).toNumber();
        var span = right - left;

        // A session under a couple of minutes wide would round away to nothing; keep it visible.
        if (span < 2) {
            span = 2;
        }
        if (left + span > x + width) {
            left = x + width - span;
        }

        dc.fillRoundedRectangle(left, y, span, height, radius);
    }
}
