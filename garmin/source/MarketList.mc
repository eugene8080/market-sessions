import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

//! The scrollable list of every market, reached from the dial with DOWN or a swipe up.
//!
//! The dial answers "what is happening now" at a glance and deliberately says nothing else — nine
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
    //! 48.5 units is 55 pixels on the AMOLED, which is the size Garmin's own stock ticker sets its
    //! rows at and is what this is meant to match. It went 25 → 38 → 55 over three attempts, and
    //! the first two were both still too small to read on a wrist.
    //!
    //! At this size a row cannot hold its content, and that is the point rather than a problem: the
    //! text scrolls instead. See `MarketRow.segments`.
    static const TEXT_SIZE = 48.5;
    static const LINES_PER_ROW = 2;
    static const GRID = 400.0;

    //! How far in from the edge a row's text starts.
    //!
    //! Small, because at 55 pixels the row needs every pixel it can get and the scrolling handles
    //! what is left over. A round display clips the corners of the topmost and bottommost rows, and
    //! a CustomMenuItem has no idea where on screen it has been placed, so that cannot be designed
    //! around — it is also exactly what the stock ticker does. You bring a row to the middle to
    //! read it.
    static const INSET_FRACTION = 0.11;

    // -------------------------------------------------------------------------------------
    // Marquee
    // -------------------------------------------------------------------------------------

    //! Advanced by the timer below; read by whichever row currently has focus.
    //!
    //! A single shared counter rather than per-row state: only the focused row ever scrolls, so
    //! there is only ever one animation, and a row that gains focus should start from the beginning
    //! rather than resume wherever it left off last time.
    static var tick as Number = 0;

    //! Milliseconds between marquee frames, and pixels moved per frame.
    private const FRAME_MS = 80;
    static const SPEED = 5;

    //! Frames held still at each end of the travel, so the beginning and the end of the line can
    //! both be read rather than swept past.
    static const DWELL = 14;

    //! Set by any focused row that had to clip a line, cleared once the frame is spent.
    //!
    //! Static because a CustomMenuItem has no route back to the menu holding it. The loop is
    //! self-sustaining but self-terminating: a row that overflows sets the flag on every draw, so
    //! the frames keep coming; when focus lands on a row that fits, the last draw leaves the flag
    //! clear and the redraws stop. CustomMenu requests its own update when the focus moves, which
    //! is what restarts them.
    static var overflowed as Boolean = false;

    private var _timer as Timer.Timer or Null = null;

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

        // Two lines of text plus a little air. Too short and the rows bleed into each other, which
        // is exactly what happened when this height was a round number picked by eye.
        CustomMenu.initialize(line * LINES_PER_ROW + line / 2, Palette.GROUND_CORE, {
            :title => new MarketListTitle(openCount),
            :titleItemHeight => line + line / 2
        });

        for (var i = 0; i < Markets.count(); i += 1) {
            addItem(new MarketRow(i, states[i], now));
        }
    }

    //! The marquee runs only while the list is on screen. A timer left running behind a popped view
    //! would redraw a menu nobody is looking at until the app closed.
    function onShow() as Void {
        tick = 0;
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        (_timer as Timer.Timer).start(method(:onMarqueeFrame), FRAME_MS, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
        }
    }

    //! One frame of travel.
    //!
    //! The redraw is requested only when the focused row actually clipped something on the last
    //! frame. A menu that repaints twelve times a second to animate nothing is a flat battery for
    //! no reason.
    function onMarqueeFrame() as Void {
        tick += 1;
        if (overflowed) {
            overflowed = false;
            WatchUi.requestUpdate();
        }
    }

    //! How far a line of `overflow` pixels too wide should currently be shifted left.
    //!
    //! One direction only: hold at the start, run to the end, hold there, then snap back to the
    //! start and begin again. It was a ping-pong first, scrolling back the way it came, and reading
    //! a line backwards is worse than not reading it — the eye tries to follow and gets nothing.
    //! The snap is instantaneous and unambiguous: the line is either at its beginning or moving
    //! forwards.
    static function travel(overflow as Number) as Number {
        if (overflow <= 0) {
            return 0;
        }

        var frames = overflow / SPEED + 1;
        var phase = tick % (frames + DWELL * 2);

        if (phase < DWELL) {
            return 0;                       // held at the start
        }
        if (phase >= DWELL + frames) {
            return overflow;                // held at the end, before the reset
        }

        var shifted = (phase - DWELL) * SPEED;
        return shifted > overflow ? overflow : shifted;
    }

    //! The row font.
    //!
    //! A vector font for the same reason the dial's hour numerals use one: Garmin's system fonts
    //! are a fixed ladder, and none of its rungs lands where this wants to be. `getVectorFont`
    //! takes a size in pixels instead.
    static function font(screenWidth as Number) as FontType {
        if (!(Graphics has :getVectorFont)) {
            return Graphics.FONT_SMALL;
        }
        var vector = Graphics.getVectorFont({
            :face => ["RobotoCondensedRegular", "RobotoRegular"],
            :size => scaled(TEXT_SIZE, screenWidth)
        });
        return vector != null ? vector : Graphics.FONT_SMALL;
    }

    //! One line's height, without needing a Dc — the menu's row height is fixed at construction,
    //! before any drawing context exists.
    static function lineHeight(screenWidth as Number) as Number {
        return (scaled(TEXT_SIZE, screenWidth) * 1.22).toNumber();
    }

    static function scaled(designUnits as Numeric, screenWidth as Number) as Number {
        var value = (designUnits * screenWidth / GRID + 0.5).toNumber();
        return value < 1 ? 1 : value;
    }

    static function inset(screenWidth as Number) as Number {
        return (screenWidth * INSET_FRACTION).toNumber();
    }
}

//! The heading that stays put while the rows scroll under it.
//!
//! Handed the count rather than working it out, because `draw` runs on every scroll frame and
//! counting means one more calendar search per market.
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

//! One market, two lines:
//!
//!     • SEHKNTL  Shanghai
//!       09:30-15:00  opens 12h30m
//!
//! At 55 pixels neither line reliably fits — "09:30-15:00 opens 12h30m" is about 500 pixels against
//! 400 of usable row — so a line that is too long is **clipped to the row and scrolled**, the way
//! the stock ticker scrolls a fund name too long for its width.
//!
//! Only the focused row scrolls. Animating every row at twelve frames a second to move text
//! nobody is reading is a flat battery, and the focused row is the one being read.
//!
//! The verb stays. "SEHK 2h10m" does not say whether Hong Kong is two hours from opening or from
//! closing, which is the same ambiguity the dial's summary had, and it is not worth trading away to
//! save the width when scrolling can buy the width instead. The dot before the code carries open or
//! shut in the session colour so the state still reads instantly.
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
    //! CustomMenuItem's `draw` runs on every scroll frame — and now on every marquee frame too — so
    //! resolving there would run that search once per market, every frame.
    function initialize(index as Number, state as Array<Number>, now as Number) {
        CustomMenuItem.initialize(index, {});

        _code = Markets.CODES[index];
        _city = Markets.NAMES[index];
        _isOpen = state[Sessions.STATE_IS_OPEN] == 1;

        // The watch's own time, not the exchange's, because that is what the dial draws and the two
        // have to agree. The city name carries the local context instead.
        _window = clock(state[Sessions.STATE_START]) + "-" + clock(state[Sessions.STATE_END]);

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
        var dot = MarketList.scaled(5.0, width);

        // The dot sits inside the inset, not left of it: outside is where the round display is
        // already cutting the row away. The text starts clear of it.
        var textLeft = left + dot * 3;
        var usable = right - textLeft;

        var top = height / 2 - (line * MarketList.LINES_PER_ROW) / 2;

        dc.setColor(_isOpen ? Palette.OPEN : Palette.CLOSED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(left + dot, top + line / 2, dot);

        segments(dc, font, textLeft, top, usable, line,
            [_code, _city] as Array<String>,
            [Palette.RING_TEXT, Palette.DIM] as Array<Number>);

        segments(dc, font, textLeft, top + line, usable, line,
            [_window, _change] as Array<String>,
            [Palette.DIM, _isOpen ? Palette.OPEN : Palette.CLOSED] as Array<Number>);
    }

    //! One line, drawn as coloured pieces laid left to right, scrolled together if too wide.
    //!
    //! The pieces move as one unit rather than each scrolling independently, because they are one
    //! sentence: "SEHKNTL Shanghai" reading past its own city would be nonsense. The clip is what
    //! keeps a long line inside its row instead of running into the row beside it, so it is set for
    //! every line, scrolling or not.
    private function segments(dc as Dc, font as FontType, x as Number, y as Number,
            usable as Number, line as Number,
            pieces as Array<String>, colours as Array<Number>) as Void {

        var gap = MarketList.scaled(14.0, dc.getWidth());

        var total = 0;
        for (var i = 0; i < pieces.size(); i += 1) {
            if (!pieces[i].equals("")) {
                total += dc.getTextWidthInPixels(pieces[i], font) + (total > 0 ? gap : 0);
            }
        }

        var overflow = total - usable;
        var offset = 0;
        if (overflow > 0 && isFocused()) {
            // Scroll only the row being read, and keep the frames coming while it is.
            MarketList.overflowed = true;
            offset = MarketList.travel(overflow);
        }

        dc.setClip(x, y, usable, line);

        var cursor = x - offset;
        for (var i = 0; i < pieces.size(); i += 1) {
            if (pieces[i].equals("")) {
                continue;
            }
            dc.setColor(colours[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(cursor, y, font, pieces[i], Graphics.TEXT_JUSTIFY_LEFT);
            cursor += dc.getTextWidthInPixels(pieces[i], font) + gap;
        }

        dc.clearClip();
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
