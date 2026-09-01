import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! The scrollable list of every market, reached from the dial with DOWN or a swipe up.
//!
//! The dial answers "what is happening now" at a glance and deliberately says nothing else — eleven
//! arcs and one summary line. This is the other half: every market, when its session runs, and how
//! long until that session changes, in a form you read rather than glance at.
//!
//! **A glance cannot do this.** A glance is a single non-interactive `Dc` draw, and up and down in
//! the glance carousel belong to the system for moving between glances. So the list lives one layer
//! in, on the app side of the START press, where the app owns the inputs.
//!
//! `CustomMenu` rather than `Menu2`. Menu2 would have been about twenty lines and scrolls for free,
//! but it draws system-styled rows — white on black, no palette — and a list that looks like a
//! settings screen would read as a different app from the dial it was opened from. CustomMenu keeps
//! the scrolling machinery and hands back the drawing.
//!
//! Deliberately **not** `(:glance)`, for the reason in the second paragraph: none of this is
//! reachable from a glance, and it would only spend the glance build's 64 KB on a screen it can
//! never show.
class MarketList extends WatchUi.CustomMenu {

    //! Row text height on the 400 unit design grid the rest of the app uses, so the list scales
    //! with the dial between the 454 pixel AMOLED and the 280 pixel Solar.
    //!
    //! This was 22 units, which measured 25 pixels on the AMOLED and was simply too small to read
    //! on a watch — Garmin's own stock ticker sets its rows at about this size instead. Going
    //! bigger cost the row its two column layout: measured on the panel, a line holding both the
    //! session window and the countdown needs
    //!
    //!     "09:30-16:00" 150px + "closes 12h30m" 193px + a gap
    //!
    //! against 272 pixels of usable row, and no arrangement of those two fits above about size 28.
    //! So the row grew a third line instead, which is also roughly the density the stock ticker
    //! runs at — two and a half rows on screen rather than four.
    static const TEXT_SIZE = 34.0;
    static const LINES_PER_ROW = 3;
    static const GRID = 400.0;

    //! Built here rather than taken as a Dc, because a menu is constructed before it is shown and
    //! there is no drawing context yet. Every device this targets has a square display.
    function initialize() {
        var size = System.getDeviceSettings().screenWidth;
        var line = lineHeight(size);

        var now = Time.now().value();
        var states = new Array<Array<Number> >[Markets.count()];
        var openCount = 0;

        // Dial order, which is east to west and also the order of the bands, outermost first. Not
        // sorted by whichever market moves next: that order rearranges itself through the day, and
        // a reference list you have to re-read from the top every time is not a reference list.
        for (var i = 0; i < Markets.count(); i += 1) {
            states[i] = Sessions.stateOf(i, now);
            if (states[i][Sessions.STATE_IS_OPEN] == 1) {
                openCount += 1;
            }
        }

        // Three lines of text plus a little air. Too short and the rows bleed into each other,
        // which is exactly what happened when this was a round number picked by eye.
        // The title holds one line, so it is sized for one. At two it was stealing most of a row's
        // worth of screen from a list that only fits two and a half.
        CustomMenu.initialize(line * LINES_PER_ROW + line / 2, Palette.GROUND_CORE, {
            :title => new MarketListTitle(openCount),
            :titleItemHeight => line + line / 2
        });

        for (var i = 0; i < Markets.count(); i += 1) {
            addItem(new MarketRow(i, states[i], now));
        }
    }

    //! The row font.
    //!
    //! A vector font for the same reason the dial's hour numerals use one: Garmin's system fonts
    //! are a fixed ladder whose smallest rung is 37 pixels on the 454 panel, and at that size two
    //! lines make a row so tall only four fit on screen — and the text runs out past the edge of a
    //! round display. `getVectorFont` takes a size in pixels instead.
    static function font(screenWidth as Number) as FontType {
        if (!(Graphics has :getVectorFont)) {
            return Graphics.FONT_XTINY;
        }
        var vector = Graphics.getVectorFont({
            :face => ["RobotoCondensedRegular", "RobotoRegular"],
            :size => scaled(TEXT_SIZE, screenWidth)
        });
        return vector != null ? vector : Graphics.FONT_XTINY;
    }

    //! One line's height, without needing a Dc — the menu's row height is fixed at construction,
    //! before any drawing context exists.
    static function lineHeight(screenWidth as Number) as Number {
        return (scaled(TEXT_SIZE, screenWidth) * 1.25).toNumber();
    }

    static function scaled(designUnits as Numeric, screenWidth as Number) as Number {
        var value = (designUnits * screenWidth / GRID + 0.5).toNumber();
        return value < 1 ? 1 : value;
    }

    //! How far in from the edge a row's text has to start.
    //!
    //! A round display clips the corners of every row, and CustomMenu hands each item the full
    //! width regardless — an item has no idea where on the screen it has been placed, so the inset
    //! cannot follow the curve and has to clear the worst case instead.
    //!
    //! That case is a row near the top or bottom of the scroll. At nine tenths of the way down a
    //! 454 pixel screen the chord is only 272 pixels, so text has to start a fifth of the way in;
    //! at 0.15 the last visible row lost the end of its line. It also clears the scroll indicator
    //! the system draws down the left.
    static function inset(screenWidth as Number) as Number {
        return (screenWidth * 0.20).toNumber();
    }
}

//! The heading that stays put while the rows scroll under it.
//!
//! Handed the count rather than working it out, because `draw` runs on every scroll frame and
//! counting means eleven more calendar searches.
class MarketListTitle extends WatchUi.Drawable {

    private var _openCount as Number;

    function initialize(openCount as Number) {
        Drawable.initialize({});
        _openCount = openCount;
    }

    function draw(dc as Dc) as Void {
        dc.setColor(Palette.GROUND_CORE, Palette.GROUND_CORE);
        dc.clear();

        dc.setColor(_openCount > 0 ? Palette.OPEN : Palette.CLOSED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2,
            MarketList.font(dc.getWidth()),
            _openCount == 1 ? "1 OPEN" : _openCount.toString() + " OPEN",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

//! One market: its code and city, the session window, and how long until that window changes.
//!
//!     • SEHK  Hong Kong
//!       09:30-16:00
//!       closes 2h10m
//!
//! Three lines, one fact each, because at a size worth reading on a watch no two of them fit side
//! by side. Everything is left aligned to a single column so the eye runs straight down the codes,
//! which is how you use a list of eleven markets; the countdown takes the session colour because it
//! is the only line that changes while you are looking at it.
//!
//! The verb is on the row for the same reason it is on the dial: "SEHK 2h10m" does not say whether
//! Hong Kong is two hours from opening or from closing. The dot before the code carries open or
//! shut in the session colour, so the state reads before any of the text does — a stripe down the
//! left edge would have been clearer still, but that is where the display rounds away and where
//! CustomMenu puts its own scroll indicator.
//!
//! Nothing here needs to marquee. Measured on the 454 panel at this size, the widest line any
//! market produces is "SEHKNTL  Shanghai" at 247 pixels against 272 of usable row. The city is
//! still dropped rather than overrun if a longer name is ever added.
class MarketRow extends WatchUi.CustomMenuItem {

    private var _code as String;
    private var _city as String;
    private var _window as String;
    private var _change as String;
    private var _isOpen as Boolean;

    //! `state` is a `Sessions.stateOf` result and `now` the instant it was resolved at.
    //!
    //! Everything is turned into a string here, once. `Sessions.stateOf` walks up to eighteen
    //! calendar days per market and is why the dial caches its answers between transitions; a
    //! CustomMenuItem's `draw` runs on every scroll frame, so resolving there would run that search
    //! eleven times a frame.
    function initialize(index as Number, state as Array<Number>, now as Number) {
        CustomMenuItem.initialize(index, {});

        _code = Markets.CODES[index];
        _city = Markets.NAMES[index];
        _isOpen = state[Sessions.STATE_IS_OPEN] == 1;

        // The watch's own time, not the exchange's, because that is what the dial draws and the two
        // have to agree. The city name carries the local context instead.
        _window = clock(state[Sessions.STATE_START]) + "-" + clock(state[Sessions.STATE_END]);

        // Compact — "16h53m" not "16h 53m". A space here is a character and a half of row width,
        // which is the difference between the city fitting beside it and not.
        var at = state[Sessions.STATE_TRANSITION];
        _change = at == Sessions.NONE
            ? ""
            : (_isOpen ? "closes " : "opens ") + Sessions.formatGapCompact(at - now);
    }

    //! A UTC instant as HH:MM on the watch's clock.
    private function clock(utcSeconds as Number) as String {
        if (utcSeconds == Sessions.NONE) {
            return "--:--";
        }
        var minute = Sessions.displayMinuteOfDay(utcSeconds).toNumber();
        return Lang.format("$1$:$2$", [(minute / 60).format("%02d"), (minute % 60).format("%02d")]);
    }

    function draw(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var font = MarketList.font(width);
        var line = MarketList.lineHeight(width);

        var left = MarketList.inset(width);
        var right = width - left;

        var accent = _isOpen ? Palette.OPEN : Palette.CLOSED;
        var dot = MarketList.scaled(4.0, width);

        // The dot sits inside the inset, not left of it: outside is where the round display is
        // already cutting the row away. The text starts clear of it.
        var textLeft = left + dot * 3;

        // Three lines, centred in the row.
        var top = height / 2 - (line * MarketList.LINES_PER_ROW) / 2;

        // Open or shut, before any of the text.
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(left + dot, top + line / 2, dot);

        dc.setColor(Palette.RING_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textLeft, top, font, _code, Graphics.TEXT_JUSTIFY_LEFT);

        // The city follows the code on the same line, and is dropped rather than overrun.
        var gap = MarketList.scaled(10.0, width);
        var cityLeft = textLeft + dc.getTextWidthInPixels(_code, font) + gap;

        dc.setColor(Palette.DIM, Graphics.COLOR_TRANSPARENT);
        if (cityLeft + dc.getTextWidthInPixels(_city, font) <= right) {
            dc.drawText(cityLeft, top, font, _city, Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.drawText(textLeft, top + line, font, _window, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textLeft, top + line * 2, font, _change, Graphics.TEXT_JUSTIFY_LEFT);
    }
}

//! Input for the list. There is nothing behind a row, so selecting one does nothing and BACK
//! returns to the dial.
class MarketListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        // Every fact about a market is already on its row; there is no detail screen to push.
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
