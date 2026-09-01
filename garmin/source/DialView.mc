import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

//! The 24 hour dial, the view the glance opens into.
//!
//! The geometry is still the web app's: a 400 unit design grid, one band per session, midnight at
//! the top and noon at the bottom, so a whole day is one revolution. The finish is not. Connect IQ
//! has no gradient primitive, so every fade here is a run of segments with `Palette.mix` between
//! two endpoints — the ground darkening towards the centre, the hour ring cooling towards midnight,
//! each session band travelling from its open to its close.
//!
//! The hands pivot on the rim of the summary dial rather than at the centre of the face. That is a
//! choice, not a compromise: the middle of this dial is carrying three lines of text worth reading,
//! and hands sweeping across them would cost more than the conventional look is worth. Skeleton
//! watches have done the same thing for a century.
class DialView extends WatchUi.View {

    // ---------------------------------------------------------------------------------------
    // Design grid, in the web app's 400x400 space, scaled to the device in `onLayout`.
    // ---------------------------------------------------------------------------------------

    private const GRID = 400.0;
    private const BAND_OUTER = 157.0;
    private const RING_RADIUS = 177.0;
    private const RING_WIDTH = 22.0;

    private const BAND_WIDTH = 6.0;
    private const CARTOUCHE_RADIUS = 76.0;
    private const CARTOUCHE_CLEARANCE = 4.0;
    private const HUB_RADIUS = 18.0;

    //! Spacing between bands is solved in `onLayout` from however many markets the table holds, so
    //! the innermost always lands outside the summary dial. Adding a market tightens the stack.
    private var _bandStep as Float = 6.0;

    //! Where the hands begin, and how far each reaches. Short hour hand, long minute hand, as on
    //! any watch — the hour hand is broad and red tipped so it still reads as the one pointing at
    //! a session, without having to be the long one to do it.
    private const HAND_PIVOT = 20.0;
    private const HOUR_HAND_TIP = 96.0;
    private const MINUTE_HAND_TIP = 150.0;

    //! Segment counts for the two fades. Enough to read as continuous at this size, few enough
    //! that a redraw stays inside the watchdog — earlier cuts of this face used 48 and 14, plus a
    //! radial ground fade, and were killed mid-frame for running too long.
    private const RING_STEPS = 30;
    private const BAND_STEPS = 8;

    private const MINUTES_PER_DAY = 1440;

    //! Colour ramps, resolved once in `onLayout`. Interpolating inside the draw loop meant a few
    //! hundred float operations per redraw for values that never change between frames.
    private var _ringRamp as Array<Number> = [] as Array<Number>;
    private var _openRamp as Array<Number> = [] as Array<Number>;
    private var _closedRamp as Array<Number> = [] as Array<Number>;

    // ---------------------------------------------------------------------------------------
    // Session cache.
    //
    // Resolving eleven markets means several hundred daylight saving and holiday lookups, and none
    // of it changes until some market actually opens or closes. So it is done once and held until
    // that moment — which turns the expensive part of a redraw from every fifteen seconds into
    // roughly twice an hour.
    // ---------------------------------------------------------------------------------------

    private var _validUntil as Number = -1;
    private var _aggregate as Array<Number> = [] as Array<Number>;
    private var _windows as Array<Number> = [] as Array<Number>;
    private var _isOpen as Array<Number> = [] as Array<Number>;

    private var _scale as Float = 1.0;
    private var _centerX as Number = 0;
    private var _centerY as Number = 0;

    private var _hourLabelStep as Number = 3;
    private var _detailFont as FontDefinition = Graphics.FONT_XTINY;
    private var _hourFont as FontDefinition = Graphics.FONT_XTINY;

    private var _ticker as Timer.Timer?;

    //! Nothing here moves faster than a minute — the hour hand creeps a quarter of a degree per
    //! minute and the countdown is quoted in minutes — so a fifteen second tick keeps it honest
    //! without redrawing two hundred segments every second for no visible change.
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

        var outermost = BAND_OUTER - BAND_WIDTH / 2.0;
        var innermost = CARTOUCHE_RADIUS + CARTOUCHE_CLEARANCE + BAND_WIDTH / 2.0;
        var gaps = Markets.count() - 1;
        _bandStep = gaps > 0 ? (outermost - innermost) / gaps : 0.0;

        _openRamp = ramp(Palette.OPEN_FROM, Palette.OPEN_TO, BAND_STEPS);
        _closedRamp = ramp(Palette.CLOSED_FROM, Palette.CLOSED_TO, BAND_STEPS);

        // The ring's fade follows the angle rather than a straight run, cool at midnight and warm
        // under the middle of the trading day, so it is built from a cosine rather than `ramp`.
        _ringRamp = new Array<Number>[RING_STEPS];
        for (var step = 0; step < RING_STEPS; step += 1) {
            var degrees = step * 360.0 / RING_STEPS;
            var t = (1.0 - Math.cos(degrees * Math.PI / 180.0)) / 2.0;
            _ringRamp[step] = Palette.mix(Palette.RING_NIGHT, Palette.RING_DAY, t);
        }

        // A layout change invalidates nothing about the sessions, but the arrays are sized here.
        _windows = new Array<Number>[Markets.count() * 2];
        _isOpen = new Array<Number>[Markets.count()];
        _validUntil = -1;

        if (size >= 400) {
            _detailFont = Graphics.FONT_XTINY;
            _hourFont = Graphics.FONT_XTINY;
        } else {
            _detailFont = Graphics.FONT_XTINY;
            _hourFont = Graphics.FONT_XTINY;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var now = Time.now().value();

        // Every curve on this face is either an arc or a tapered polygon, and both look markedly
        // better smoothed. Guarded because it arrived in API 3.2.0 and the manifest floor is lower.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        refresh(now);
        drawGround(dc);
        drawRing(dc);
        drawBands(dc);
        drawReadout(dc, now);
        drawHands(dc, now);
        drawHub(dc);
    }

    //! `count` colours stepping from `from` to `to`.
    private function ramp(from as Number, to as Number, count as Number) as Array<Number> {
        var colours = new Array<Number>[count];
        for (var i = 0; i < count; i += 1) {
            colours[i] = Palette.mix(from, to, count > 1 ? i / (count - 1.0) : 0.0);
        }
        return colours;
    }

    //! Resolve every market, but only when the last answer has expired.
    //!
    //! Nothing on this face changes between transitions: a band's arc, its colour and the summary
    //! all hold until some market opens or closes. Holding them until that instant is what keeps
    //! the redraw inside the watchdog now that the face is drawn in a few hundred segments.
    private function refresh(now as Number) as Void {
        if (_validUntil != -1 && now < _validUntil && _aggregate.size() > 0) {
            return;
        }

        var openCount = 0;
        var soonestIndex = Sessions.NONE;
        var soonestAt = Sessions.NONE;
        var soonestIsClose = 0;

        for (var i = 0; i < Markets.count(); i += 1) {
            var state = Sessions.stateOf(i, now);

            _isOpen[i] = state[Sessions.STATE_IS_OPEN];
            _windows[i * 2] = state[Sessions.STATE_START];
            _windows[i * 2 + 1] = state[Sessions.STATE_END];

            if (state[Sessions.STATE_IS_OPEN] == 1) {
                openCount += 1;
            }

            var at = state[Sessions.STATE_TRANSITION];
            if (at != Sessions.NONE && (soonestAt == Sessions.NONE || at < soonestAt)) {
                soonestAt = at;
                soonestIndex = i;
                soonestIsClose = state[Sessions.STATE_IS_OPEN];
            }
        }

        _aggregate = [openCount, soonestIndex, soonestAt, soonestIsClose] as Array<Number>;

        // Recompute at the next transition. With no transition to wait for — which should not
        // happen, but a market table could in principle produce it — fall back to an hour.
        _validUntil = soonestAt != Sessions.NONE ? soonestAt : now + 3600;
    }

    // ---------------------------------------------------------------------------------------
    // Ground and ring
    // ---------------------------------------------------------------------------------------

    //! The face.
    //!
    //! This was a radial fade, drawn as concentric filled discs from the rim inwards, because
    //! Connect IQ has no gradient primitive. It cost the app its life: twenty two fills of a
    //! 454 pixel disc is about four and a half million pixel writes, and the watchdog killed the
    //! frame every time. Everything else on this face put together — the ring, eleven faded bands,
    //! the hands — is under a tenth of that.
    //!
    //! A buffered bitmap would buy the fade back by drawing it once, but a full screen buffer is
    //! roughly 412 KB against a 768 KB app budget, which is a poor trade for an effect that was
    //! barely visible on an AMOLED panel and mostly read as banding. So the ground is flat, and
    //! the fades live where they earn their place: around the ring, and along each session.
    private function drawGround(dc as Dc) as Void {
        dc.setColor(Palette.GROUND_CORE, Palette.GROUND_CORE);
        dc.clear();
    }

    //! The hour ring and its numerals, cool at midnight and warmer towards noon. Hour 24 sits at
    //! the top, so the dial reads as a day rather than as a clock.
    private function drawRing(dc as Dc) as Void {
        var radius = px(RING_RADIUS);
        dc.setPenWidth(px(RING_WIDTH));

        var sweep = 360.0 / RING_STEPS;
        for (var step = 0; step < RING_STEPS; step += 1) {
            var from = step * sweep;
            dc.setColor(_ringRamp[step], Graphics.COLOR_TRANSPARENT);

            // A hair of overlap, or antialiasing leaves a seam between every pair of segments.
            drawArcBetween(dc, radius, from - 0.6, from + sweep + 0.6);
        }

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

    // ---------------------------------------------------------------------------------------
    // Sessions
    // ---------------------------------------------------------------------------------------

    //! One band per market, outermost first, each faded from its open to its close. Reads the
    //! sessions `refresh` resolved rather than resolving them again.
    private function drawBands(dc as Dc) as Void {
        dc.setPenWidth(px(BAND_WIDTH));

        for (var i = 0; i < Markets.count(); i += 1) {
            var start = _windows[i * 2];
            var end = _windows[i * 2 + 1];
            if (start == Sessions.NONE || end == Sessions.NONE) {
                continue;
            }

            var radius = BAND_OUTER - i * _bandStep - BAND_WIDTH / 2.0;
            drawSession(dc, radius, start, end, _isOpen[i] == 1);
        }
    }

    //! A session as a run of short arcs, the colour travelling from the open to the close so the
    //! band has a direction rather than sitting flat.
    private function drawSession(dc as Dc, radius as Float, start as Number, end as Number,
            isOpen as Boolean) as Void {
        var from = Sessions.displayMinuteOfDay(start) / MINUTES_PER_DAY * 360.0;
        var to = Sessions.displayMinuteOfDay(end) / MINUTES_PER_DAY * 360.0;

        var sweep = to - from;
        if (sweep <= 0) {
            sweep += 360.0;             // the session straddles local midnight
        }
        if (sweep < 1.0) {
            sweep = 1.0;
        }
        if (sweep > 359.0) {
            sweep = 359.0;
        }

        var colours = isOpen ? _openRamp : _closedRamp;
        var step = sweep / BAND_STEPS;
        var scaled = px(radius);

        for (var segment = 0; segment < BAND_STEPS; segment += 1) {
            dc.setColor(colours[segment], Graphics.COLOR_TRANSPARENT);
            var edge = segment == BAND_STEPS - 1 ? 0.0 : 0.5;
            drawArcBetween(dc, scaled, from + segment * step, from + (segment + 1) * step + edge);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Hands
    // ---------------------------------------------------------------------------------------

    //! Hour and minute hands, tapered, pivoting on the rim of the summary dial.
    private function drawHands(dc as Dc, now as Number) as Void {
        var minuteOfDay = Sessions.displayMinuteOfDay(now);

        // Monkey C's modulo is integer only, so the minute hand's position within the hour comes
        // from subtracting the whole hours rather than with `%`. Keeping it in Float preserves the
        // sub-minute movement that makes the hand sweep rather than step.
        var minutesIntoHour = minuteOfDay - (minuteOfDay.toNumber() / 60) * 60;

        // Minute hand first, so the hour hand — the one that points at a session — sits on top.
        drawHand(dc, minutesIntoHour / 60.0 * 360.0, MINUTE_HAND_TIP, 3.0, 1.0,
            Palette.HAND, null);
        drawHand(dc, minuteOfDay / MINUTES_PER_DAY * 360.0, HOUR_HAND_TIP, 7.2, 2.4,
            Palette.HAND, Palette.ACCENT_HOT);
    }

    //! One tapered hand, drawn as a keyline polygon with a narrower coloured one on top.
    //!
    //! The keyline is what lets a hand cross eleven bands of arbitrary colour and stay a hand. The
    //! tip takes the warm accent on both hands, which ties them together and puts the eye on the
    //! end that is doing the pointing.
    private function drawHand(dc as Dc, degrees as Float, tip as Float, halfBase as Float,
            halfTip as Float, body as Number, tipColour as Number?) as Void {
        var radians = (degrees - 90.0) * Math.PI / 180.0;
        var alongX = Math.cos(radians);
        var alongY = Math.sin(radians);
        var acrossX = -alongY;
        var acrossY = alongX;

        // A dark shoulder a shade wider than the hand itself, so it separates from whatever band
        // it happens to be lying over.
        fillTaper(dc, alongX, alongY, acrossX, acrossY, HAND_PIVOT, tip,
            halfBase + 1.1, halfTip + 1.1, Palette.GROUND_CORE);
        fillTaper(dc, alongX, alongY, acrossX, acrossY, HAND_PIVOT, tip,
            halfBase, halfTip, body);

        // The last fifth of the hand, in the accent — only the hour hand gets one. It is the hand
        // that points at a session, and a second flash of red would just be decoration.
        if (tipColour != null) {
            var shoulder = tip - (tip - HAND_PIVOT) * 0.2;
            fillTaper(dc, alongX, alongY, acrossX, acrossY, shoulder, tip,
                halfBase * 0.45, halfTip, tipColour);
        }
    }

    private function fillTaper(dc as Dc, alongX as Float, alongY as Float, acrossX as Float,
            acrossY as Float, from as Float, to as Float, halfFrom as Float, halfTo as Float,
            colour as Number) as Void {
        var baseX = _centerX + alongX * from * _scale;
        var baseY = _centerY + alongY * from * _scale;
        var tipX = _centerX + alongX * to * _scale;
        var tipY = _centerY + alongY * to * _scale;

        var b = halfFrom * _scale;
        var t = halfTo * _scale;

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [(baseX + acrossX * b).toNumber(), (baseY + acrossY * b).toNumber()],
            [(tipX + acrossX * t).toNumber(), (tipY + acrossY * t).toNumber()],
            [(tipX - acrossX * t).toNumber(), (tipY - acrossY * t).toNumber()],
            [(baseX - acrossX * b).toNumber(), (baseY - acrossY * b).toNumber()]
        ]);
    }

    // ---------------------------------------------------------------------------------------
    // Summary
    // ---------------------------------------------------------------------------------------

    //! The dial at the centre: how many markets are trading, which moves next, and when. Its rim
    //! is also the pivot the hands turn on, which is why it is drawn last — over the hand roots.
    //! What moves next, printed on the face below the hub.
    //!
    //! Drawn before the hands, so a hand crossing it simply covers it — no recess, no routing
    //! around it. It is a line you read when you look for it, not one that has to survive being
    //! looked at from any angle at any minute.
    private function drawReadout(dc as Dc, now as Number) as Void {
        var nextIndex = _aggregate[Sessions.SUMMARY_INDEX];
        var nextAt = _aggregate[Sessions.SUMMARY_AT];
        if (nextIndex == Sessions.NONE || nextAt == Sessions.NONE) {
            return;
        }

        var label = fit(dc, _detailFont, px(CARTOUCHE_RADIUS * 1.6), [
            Markets.CODES[nextIndex] + " " + Sessions.formatGap(nextAt - now),
            Markets.CODES[nextIndex] + " " + Sessions.formatGapCompact(nextAt - now),
            Sessions.formatGapCompact(nextAt - now)
        ] as Array<String>);

        dc.setColor(Palette.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _centerY + px(36.0), _detailFont, label,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! The hub, over the roots of both hands the way a centre cap sits over a pinion.
    //!
    //! It held the number of open markets until that turned out to be a fact nobody needed spelled
    //! out — the green bands already say how many are trading. What survives is the rim, which
    //! still carries open-or-shut in a colour readable across a room.
    private function drawHub(dc as Dc) as Void {
        var radius = px(HUB_RADIUS);

        dc.setColor(Palette.GROUND_CORE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, radius);

        dc.setColor(_aggregate[Sessions.SUMMARY_OPEN_COUNT] > 0 ? Palette.OPEN : Palette.CLOSED,
            Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(px(2.4));
        dc.drawCircle(_centerX, _centerY, radius);
    }

    //! How wide a line of text may be to stay inside the summary dial. The binding constraint is
    //! whichever of the row's edges sits further from the centre.
    private function chordAt(radius as Number, rowTop as Number, rowBottom as Number) as Number {
        var above = _centerY - rowTop;
        var below = rowBottom - _centerY;
        var furthest = above > below ? above : below;

        if (furthest >= radius) {
            return 0;
        }

        var half = Math.sqrt(radius * radius - furthest * furthest);
        var usable = (2 * half).toNumber() - px(4.0);
        return usable < 0 ? 0 : usable;
    }

    //! The first candidate that fits, or the last one if none do.
    private function fit(dc as Dc, font as FontDefinition, usable as Number,
            candidates as Array<String>) as String {
        for (var i = 0; i < candidates.size(); i += 1) {
            if (dc.getTextWidthInPixels(candidates[i], font) <= usable) {
                return candidates[i];
            }
        }
        return candidates[candidates.size() - 1];
    }

    // ---------------------------------------------------------------------------------------
    // Geometry. Zero degrees is straight up and angles increase clockwise, matching `polar()` in
    // index.html; Dc angles run counter-clockwise from 3 o'clock, hence the 90 minus.
    // ---------------------------------------------------------------------------------------

    private function drawArcBetween(dc as Dc, radius as Number, from as Float, to as Float) as Void {
        dc.drawArc(_centerX, _centerY, radius, Graphics.ARC_CLOCKWISE,
            normalise(90.0 - from), normalise(90.0 - to));
    }

    private function px(designUnits as Numeric) as Number {
        var scaled = (designUnits * _scale + 0.5).toNumber();
        return scaled < 1 ? 1 : scaled;
    }

    private function polarX(radius as Float, degrees as Float) as Number {
        return _centerX + (radius * _scale * Math.cos((degrees - 90.0) * Math.PI / 180.0)).toNumber();
    }

    private function polarY(radius as Float, degrees as Float) as Number {
        return _centerY + (radius * _scale * Math.sin((degrees - 90.0) * Math.PI / 180.0)).toNumber();
    }

    //! Fold an angle into [0, 360). A loop because Monkey C's `%` is integer only and rounding
    //! through a Number would visibly quantise the arcs.
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
