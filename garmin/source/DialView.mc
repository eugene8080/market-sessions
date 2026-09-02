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

    //! The ring is as wide as the numerals printed on it, plus a little air.
    //!
    //! It was 22 units, which was fine while the dial only counted in threes and the numerals
    //! could hang over the edges without looking like a mistake. With every hour numbered they
    //! have to sit *in* the band, so the band grew to fit them and the numerals shrank to meet
    //! it — see `hourFontSize`. Ring spans 162 to 192 of a 200 unit half width, which still
    //! leaves the panel edge clear.
    private const RING_WIDTH = 30.0;

    //! Numeral height as a fraction of the ring's width. Cap height is roughly 70% of the em, so
    //! at 0.78 a two digit hour fills a little over half the band and is comfortably enclosed.
    private const HOUR_FONT_FILL = 0.78;

    //! Height of the two summary lines, in design units.
    private const READOUT_SIZE = 25.0;

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
    //!
    //! The minute hand stops on the inner edge of the fourth band rather than at a fixed radius, so
    //! it lands on the geometry wherever the stack happens to sit. Adding or merging a market moves
    //! every band; a hand measured in design units would drift off them.
    private const HAND_PIVOT = 20.0;
    private const HOUR_HAND_TIP = 96.0;
    private const MINUTE_HAND_BAND = 3;
    private var _minuteHandTip as Float = 130.0;

    //! Segment counts for the two fades.
    //!
    //! These are set by the watchdog, not by taste. The frame budget on this face is genuinely
    //! tight and has been exceeded three times: first by a radial ground fade, then by 48/14
    //! segments, and finally by numbering all twenty four hours — text is dear, and sixteen more
    //! numerals cost more than the fades could spare at 30/8. Coarser fades bought them back, and
    //! at this size the steps are not visible on the panel anyway.
    private const RING_STEPS = 18;
    private const BAND_STEPS = 6;

    private const MINUTES_PER_DAY = 1440;

    //! Where a band's name sits, in degrees along its own arc from the market's open.
    //!
    //! The bands are about ten pixels apart and the names are drawn far larger than that, so every
    //! name bleeds across its neighbours — which is the point, since a name confined to its own
    //! band would be too small to read. What stops them landing on top of each other is that each
    //! is walked along its own arc until it clears the ones already placed.
    //!
    //! This started as a fixed stagger — each band's name a further twenty six degrees round the
    //! face than the one outside it — and that failed exactly where it mattered. The offset has to
    //! be clamped into the band's own arc so the name sits on the colour it names, and Hong Kong's
    //! six and a half hours are too short to hold the offset its position asked for. Clamping put
    //! it back where Singapore already was: the two ended up eight degrees apart, overlapping.
    //! An offset that has to be clamped is not a stagger, so the placement tests rather than
    //! assumes.
    private const LABEL_STEP = 4.0;
    private const LABEL_ARC_PAD = 9.0;
    private const LABEL_SIZE = 17.0;

    //! Clearance around a name, on top of its own measured box.
    //!
    //! Design units like everything else, but with a floor in real pixels: five units is six pixels
    //! on the tactix and three on a 218 pixel Forerunner, and three is not a gap — the codes came
    //! out touching, so "SEHKNTL SEHK" read as one word.
    private const LABEL_GAP = 7.0;
    private const LABEL_GAP_MIN = 4;

    //! Colour ramps, resolved once in `onLayout`. Interpolating inside the draw loop meant a few
    //! hundred float operations per redraw for values that never change between frames.
    private var _ringRamp as Array<Number> = [] as Array<Number>;

    //! The palette generation the ramps were built from, so a theme change rebuilds them.
    private var _paletteGeneration as Number = -1;
    private var _openRamp as Array<Number> = [] as Array<Number>;
    private var _closedRamp as Array<Number> = [] as Array<Number>;

    // ---------------------------------------------------------------------------------------
    // Session cache.
    //
    // Resolving every market means several hundred daylight saving and holiday lookups, and none
    // of it changes until some market actually opens or closes. So it is done once and held until
    // that moment — which turns the expensive part of a redraw from every fifteen seconds into
    // roughly twice an hour.
    // ---------------------------------------------------------------------------------------

    private var _validUntil as Number = -1;
    private var _aggregate as Array<Number> = [] as Array<Number>;
    private var _windows as Array<Number> = [] as Array<Number>;
    private var _isOpen as Array<Number> = [] as Array<Number>;

    //! Where each band's name goes, in degrees. Solved with the sessions in `refresh`, because it
    //! depends only on where the arcs are and those hold until the next transition.
    private var _labelAt as Array<Float> = [] as Array<Float>;

    private var _scale as Float = 1.0;
    private var _centerX as Number = 0;
    private var _centerY as Number = 0;

    private var _hourLabelStep as Number = 3;
    private var _clearRadius as Number = 1;
    private var _detailFont as FontType = Graphics.FONT_XTINY;
    // Widened from FontDefinition because `hourFont` may hand back a VectorFont, which is a
    // different branch of Graphics.FontType.
    private var _hourFont as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

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
        // Every hour is numbered on the big AMOLED panel: a 24 hour dial that counts in threes
        // makes you do arithmetic to read the time off it. The 280 pixel MIP screens keep the
        // three hour step, where twenty four numerals would be too small to tell apart. Twenty
        // four numerals is not free — text is the most expensive thing on this face, and adding
        // sixteen of them tripped the watchdog until the two fades were coarsened to pay for it.
        _hourLabelStep = size >= 400 ? 1 : 3;

        var outermost = BAND_OUTER - BAND_WIDTH / 2.0;
        var innermost = CARTOUCHE_RADIUS + CARTOUCHE_CLEARANCE + BAND_WIDTH / 2.0;
        var gaps = Markets.count() - 1;
        _bandStep = gaps > 0 ? (outermost - innermost) / gaps : 0.0;

        // Inner edge of the fourth band in: its centre line, less half a band.
        _minuteHandTip = BAND_OUTER - MINUTE_HAND_BAND * _bandStep - BAND_WIDTH;

        // The disc the summary text has to stay inside: the inner edge of the innermost band.
        _clearRadius = px(innermost - BAND_WIDTH / 2.0);

        // Sized here because the market count cannot change without a rebuild.
        _windows = new Array<Number>[Markets.count() * 2];
        _isOpen = new Array<Number>[Markets.count()];
        _labelAt = new Array<Float>[Markets.count()];
        _validUntil = -1;

        // The readout takes a vector font for the same reason the numerals do, and for one more:
        // at FONT_XTINY "SEHKNTL 55m" is about 200 pixels against a 134 pixel chord, so the widest
        // codes fell all the way through `fit`'s candidates to a bare "55m" — a summary that says
        // when something happens without saying what. A smaller font clears it with room to spare.
        _detailFont = sizedFont(px(READOUT_SIZE));
        _hourFont = sizedFont((px(RING_WIDTH) * HOUR_FONT_FILL).toNumber());
        _labelFont = sizedFont(px(LABEL_SIZE));

        buildRamps();
    }

    //! Text at the size this face wants, rather than at whatever size Garmin happens to ship.
    //!
    //! The system fonts are a fixed ladder and FONT_XTINY, the smallest rung, is 37 pixels tall on
    //! the 454 panel. That is taller than the ring is wide, so the hours sat *across* the band
    //! instead of in it, and wide enough that the longest summary line did not fit the disc at all.
    //! Vector fonts take a size in pixels, which is exactly the control both wanted.
    //!
    //! Condensed rather than regular: the numerals are two digit numbers repeated twenty four times
    //! around a circle, and the summary has to hold a seven letter venue code and a duration on one
    //! line. The narrower face buys both.
    //!
    //! Both tactix 8 variants report `enhancedGraphicSupport`, but the check is done properly
    //! anyway — a device without it falls back to the system font, which is merely the old look,
    //! not a blank dial.
    private function sizedFont(pixels as Number) as FontType {
        if (!(Graphics has :getVectorFont)) {
            return Graphics.FONT_XTINY;
        }

        var font = Graphics.getVectorFont({
            :face => ["RobotoCondensedRegular", "RobotoRegular"],
            :size => pixels
        });

        // A face the device does not carry returns null rather than substituting one.
        return font != null ? font : Graphics.FONT_XTINY;
    }

    //! The colour ramps, and the generation they came from.
    private function buildRamps() as Void {
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

        _paletteGeneration = Palette.generation;
    }

    function onUpdate(dc as Dc) as Void {
        var now = Time.now().value();

        // Every curve on this face is either an arc or a tapered polygon, and both look markedly
        // better smoothed. Guarded because it arrived in API 3.2.0 and the manifest floor is lower.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        if (_paletteGeneration != Palette.generation) {
            buildRamps();
        }

        refresh(dc, now);
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
    private function refresh(dc as Dc, now as Number) as Void {
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

        placeLabels(dc);

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
    //! frame every time. Everything else on this face put together — the ring, the faded bands,
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

        // VCENTER rather than subtracting half the font height by hand. The two agree for a bitmap
        // font, but a vector font's reported height is its em, not its ink, so the hand rolled
        // version sat the numerals a couple of pixels proud of the middle of the band.
        for (var hour = _hourLabelStep; hour <= 24; hour += _hourLabelStep) {
            var degrees = hour / 24.0 * 360.0;
            dc.drawText(
                polarX(RING_RADIUS, degrees),
                polarY(RING_RADIUS, degrees),
                _hourFont,
                hour.format("%02d"),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Sessions
    // ---------------------------------------------------------------------------------------

    //! One band per market, outermost first, each faded from its open to its close. Reads the
    //! sessions `refresh` resolved rather than resolving them again.
    //! Choose where each band's name sits, once per transition.
    //!
    //! Each name is walked along its own arc in `LABEL_STEP` degree increments and takes the first
    //! position whose box clears every name already placed. Boxes, not distances: the codes differ
    //! in width by a factor of three — `SGX` against `SEHKNTL` — so a single separation radius is
    //! either too small for the long ones or too generous for the short ones.
    //!
    //! Bands are walked outermost first, so when a position genuinely cannot be found, the name
    //! that has to settle for its least-bad spot is an inner one, where the arcs are shorter and
    //! there was least room to begin with.
    private function placeLabels(dc as Dc) as Void {
        var height = dc.getFontHeight(_labelFont);
        var gap = px(LABEL_GAP);
        if (gap < LABEL_GAP_MIN) {
            gap = LABEL_GAP_MIN;
        }

        // Names already placed, as [centreX, centreY, halfWidth, halfHeight] each — plus one more
        // slot for the summary in the middle of the face.
        var placed = new Array<Number>[(Markets.count() + 1) * 4];

        // The summary is seeded as though it were a name already placed, so the bands avoid it. It
        // is not optional and it is not on an arc, so it goes in first and never moves. Without it
        // the innermost band — the one whose arc passes closest to the centre — put its name
        // straight through the readout on the smaller screens.
        //
        // The box is the summary's *text*, not the disc it sits in. Reserving the whole disc was
        // the obvious first try and it was far too greedy: at 91 pixels of half width it walled off
        // most of the two innermost arcs, and Europe and Singapore — whose long sessions make them
        // the last to be placed — were left with nowhere legal to go and went unnamed on a screen
        // with room to spare.
        var summaryLine = dc.getFontHeight(_detailFont);
        var summaryTop = _centerY - px(HUB_RADIUS) - px(2.0) - summaryLine;
        placed[0] = _centerX;
        placed[1] = _centerY;
        placed[2] = chordAt(_clearRadius, summaryTop, summaryTop + summaryLine) / 2;
        placed[3] = px(HUB_RADIUS) + px(2.0) + summaryLine;
        var count = 1;

        // Shortest arc first, not outermost first.
        //
        // A name can only go on its own band, so a market with a short session has few places to
        // put one and a market with a long session has many. Placing in band order let Sydney's
        // ninety degrees take a spot Shanghai's eighty two needed, and Shanghai — having nowhere
        // else to be — went unnamed while Sydney had the rest of its arc free. Giving the most
        // constrained band the first pick is what fits all nine on the tactix.
        var order = arcOrder();

        for (var slot = 0; slot < order.size(); slot += 1) {
            var i = order[slot];
            var start = _windows[i * 2];
            var end = _windows[i * 2 + 1];
            if (start == Sessions.NONE || end == Sessions.NONE) {
                _labelAt[i] = -1.0;
                continue;
            }

            var from = Sessions.displayMinuteOfDay(start) / MINUTES_PER_DAY * 360.0;
            var to = Sessions.displayMinuteOfDay(end) / MINUTES_PER_DAY * 360.0;
            var sweep = to - from;
            if (sweep <= 0) {
                sweep += 360.0;         // the session straddles local midnight
            }

            var radius = BAND_OUTER - i * _bandStep - BAND_WIDTH / 2.0;
            var halfWidth = dc.getTextWidthInPixels(Markets.CODES[i], _labelFont) / 2 + gap;
            var halfHeight = height / 2 + gap;

            var usable = sweep - 2 * LABEL_ARC_PAD;
            if (usable < 0) {
                usable = 0.0;
            }

            var found = -1.0;

            for (var step = 0.0; step <= usable && found < 0.0; step += LABEL_STEP) {
                var angle = from + LABEL_ARC_PAD + step;
                if (isClear(placed, count,
                        polarX(radius, angle), polarY(radius, angle), halfWidth, halfHeight)) {
                    found = LABEL_ARC_PAD + step;
                }
            }

            // Nowhere clear: leave this band unnamed rather than print two codes on top of each
            // other. The whole point of walking the arc is that names do not overlap, and a face
            // reading "SEHKNTLASX" has failed at that more completely than a missing name does —
            // it is not merely unhelpful, it is unreadable, and it makes its neighbour unreadable
            // too. Nine names will not fit legibly on a 218 pixel screen; the market list, one
            // button away, has room for all of them.
            if (found < 0.0) {
                _labelAt[i] = -1.0;
                continue;
            }

            var chosen = normalise(from + found);
            _labelAt[i] = chosen;

            placed[count * 4] = polarX(radius, chosen);
            placed[count * 4 + 1] = polarY(radius, chosen);
            placed[count * 4 + 2] = halfWidth;
            placed[count * 4 + 3] = halfHeight;
            count += 1;
        }
    }

    //! Market indices ordered by how much arc they have to put a name on, tightest first.
    //!
    //! An insertion sort, because nine markets is nine and the array is rebuilt only when a session
    //! changes. A market with no session at all sorts last: it has no arc, no name to place, and no
    //! claim on anyone else's room.
    private function arcOrder() as Array<Number> {
        var count = Markets.count();
        var order = new Array<Number>[count];
        var sweeps = new Array<Float>[count];

        for (var i = 0; i < count; i += 1) {
            order[i] = i;
            var start = _windows[i * 2];
            var end = _windows[i * 2 + 1];
            if (start == Sessions.NONE || end == Sessions.NONE) {
                sweeps[i] = 999.0;
                continue;
            }
            var sweep = Sessions.displayMinuteOfDay(end) / MINUTES_PER_DAY * 360.0
                - Sessions.displayMinuteOfDay(start) / MINUTES_PER_DAY * 360.0;
            sweeps[i] = sweep <= 0 ? sweep + 360.0 : sweep;
        }

        for (var i = 1; i < count; i += 1) {
            var value = order[i];
            var key = sweeps[value];
            var j = i - 1;
            while (j >= 0 && sweeps[order[j]] > key) {
                order[j + 1] = order[j];
                j -= 1;
            }
            order[j + 1] = value;
        }
        return order;
    }

    //! Does a box at this position touch anything already placed?
    private function isClear(placed as Array<Number>, count as Number,
            x as Number, y as Number, halfWidth as Number, halfHeight as Number) as Boolean {
        for (var j = 0; j < count; j += 1) {
            var apart = (placed[j * 4] - x).abs() >= placed[j * 4 + 2] + halfWidth
                || (placed[j * 4 + 1] - y).abs() >= placed[j * 4 + 3] + halfHeight;
            if (!apart) {
                return false;
            }
        }
        return true;
    }

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

        drawBandLabels(dc);
    }

    //! The venue codes, over the bands they name.
    //!
    //! Drawn after every band so a name is never buried under the arc of the band inside it, and
    //! in the ring's text colour rather than the session colour: the arc already carries open or
    //! shut, and a name that changed colour with it would be saying the same thing twice while
    //! being harder to read against its own background.
    private function drawBandLabels(dc as Dc) as Void {
        dc.setColor(Palette.RING_TEXT, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < Markets.count(); i += 1) {
            if (_labelAt[i] < 0.0) {
                continue;
            }
            var radius = BAND_OUTER - i * _bandStep - BAND_WIDTH / 2.0;
            dc.drawText(
                polarX(radius, _labelAt[i]),
                polarY(radius, _labelAt[i]),
                _labelFont,
                Markets.CODES[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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
        drawHand(dc, minutesIntoHour / 60.0 * 360.0, _minuteHandTip, 4.5, 1.5,
            Palette.HAND, null);
        drawHand(dc, minuteOfDay / MINUTES_PER_DAY * 360.0, HOUR_HAND_TIP, 7.2, 2.4,
            Palette.HAND, Palette.ACCENT_HOT);
    }

    //! One tapered hand, drawn as a keyline polygon with a narrower coloured one on top.
    //!
    //! The keyline is what lets a hand cross a stack of bands of arbitrary colour and stay a hand. The
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
    //! What moves next, and which way — two lines straddling the hub.
    //!
    //! It was one line, "ASX 25m", and that line was ambiguous in the way that mattered: it does
    //! not say whether Sydney is twenty five minutes from opening or from closing, which is the
    //! only thing the summary exists to tell you. Colouring it by direction was tried first and
    //! is not enough — a colour reads as mood, and the reader has no reason to know the code.
    //!
    //! So the direction gets its own line. There is genuinely no room for it on the first one:
    //! "ASX 25m" measures 127 pixels of a 134 pixel chord at FONT_XTINY, and FONT_XTINY is the
    //! smallest font Garmin ships. The colour stays as well, now as reinforcement rather than as
    //! the whole message.
    //!
    //! Drawn before the hands, so a hand crossing it simply covers it — no recess, no routing
    //! around it.
    private function drawReadout(dc as Dc, now as Number) as Void {
        var nextIndex = _aggregate[Sessions.SUMMARY_INDEX];
        var nextAt = _aggregate[Sessions.SUMMARY_AT];
        if (nextIndex == Sessions.NONE || nextAt == Sessions.NONE) {
            return;
        }

        var aClose = _aggregate[Sessions.SUMMARY_IS_CLOSE] == 1;
        var lineHeight = dc.getFontHeight(_detailFont);

        // One line above the hub and one below, rather than both beneath it. The disc is widest
        // across its middle, and stacking two lines under the hub pushes the lower one down to
        // where the chord is about 80 pixels — too narrow for the word that has to go there.
        var clearOfHub = px(HUB_RADIUS) + px(2.0);
        var topRow = _centerY - clearOfHub - lineHeight;
        var bottomRow = _centerY + clearOfHub;

        var which = fit(dc, _detailFont, chordAt(_clearRadius, topRow, topRow + lineHeight), [
            Markets.CODES[nextIndex] + " " + Sessions.formatGap(nextAt - now),
            Markets.CODES[nextIndex] + " " + Sessions.formatGapCompact(nextAt - now),
            Markets.CODES[nextIndex] + " " + Sessions.formatGapHours(nextAt - now),
            Sessions.formatGapCompact(nextAt - now)
        ] as Array<String>);

        // The direction, spelled out. It used to be carried only by the colour of the line above,
        // which reads as decoration rather than information: shown "ASX 25m" you cannot tell
        // whether Sydney is twenty five minutes from opening or from closing, and that is the one
        // thing the summary exists to say. There is no room for it on the same line — "ASX 25m"
        // is already 127 pixels of a 134 pixel chord — so it gets its own.
        var direction = fit(dc, _detailFont,
            chordAt(_clearRadius, bottomRow, bottomRow + lineHeight),
            aClose ? ["to close", "close"] as Array<String>
                   : ["to open", "open"] as Array<String>);

        dc.setColor(Palette.RING_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, topRow, _detailFont, which, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(aClose ? Palette.CLOSED_TO : Palette.OPEN_TO, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, bottomRow, _detailFont, direction, Graphics.TEXT_JUSTIFY_CENTER);
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
