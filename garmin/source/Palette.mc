import Toybox.Lang;

//! The dial's colours, and the themes that supply them.
//!
//! These are module variables rather than constants because the face is themeable: `apply` swaps
//! the whole set, and `generation` ticks so a view holding derived state — the colour ramps in
//! DialView — knows to rebuild it.
//!
//! Connect IQ has no gradient primitive of any kind. Every fade on this dial is drawn as a run of
//! segments interpolated with `mix`, which is why the pairs below are `_FROM` and `_TO` rather than
//! single values. A theme that wants a flat band simply sets both ends the same.
//!
//! The Solar 51mm variant of the tactix 8 is an 8 bit MIP panel, rendering from a fixed 64 colour
//! palette — every channel snapped to 0x00, 0x55, 0xAA or 0xFF. Fades collapse to steps there and
//! hues shift; every theme keeps open and closed far enough apart to survive it.
(:glance)
module Palette {

    //! Theme ids. These are the values stored in the `theme` property, so they are part of the
    //! app's saved state — append, never renumber.
    const IRON = 0;
    const COBALT = 1;
    const EMBER = 2;
    const THEME_COUNT = 3;

    //! The colour a trading session is drawn in. Separate from the theme because it is the one
    //! thing on this face that means something rather than setting a mood — and because a warm
    //! theme and a warm session colour are a combination worth being able to avoid.
    //!
    //! Saved state, like the theme ids: append, never renumber.
    const OPEN_RED = 0;
    const OPEN_GREEN = 1;
    const OPEN_BLUE = 2;
    const OPEN_PURPLE = 3;
    const OPEN_COUNT = 4;

    //! Which session colour is live.
    var openChoice as Number = OPEN_RED;

    //! Bumped by `apply`, so anything caching derived colours can tell the theme moved.
    var generation as Number = 0;

    //! Which theme is live. Read by the settings menu to show the current choice.
    var current as Number = IRON;

    // -------------------------------------------------------------------------------------
    // The live set. Filled by `apply`; the values here are Iron, so the face is drawable even
    // if a theme is never applied.
    // -------------------------------------------------------------------------------------

    var GROUND_CORE as Number = 0x070910;       //! the face

    var RING_NIGHT as Number = 0x2C3854;        //! hour ring at midnight
    var RING_DAY as Number = 0x495C82;          //! and at noon
    var RING_TEXT as Number = 0xE9EEF8;

    var OPEN_FROM as Number = 0x8B1E1E;         //! a trading session, at its open
    var OPEN_TO as Number = 0xFF6152;           //! and at its close
    var CLOSED_FROM as Number = 0x404A64;       //! a market waiting for its next session
    var CLOSED_TO as Number = 0x8B95B1;

    var OPEN as Number = 0xE0483C;              //! flat tones, where a fade would be lost:
    var CLOSED as Number = 0x8F97B6;            //! the glance timeline, the hub's rim

    var ACCENT_HOT as Number = 0xF4522F;        //! the hour hand's tip, and nothing else
    var HAND as Number = 0xC9D3E4;

    var DIM as Number = 0x7E8AA6;
    var TRACK as Number = 0x222A3D;

    //! Switch the face to a theme. Out of range falls back to Iron rather than throwing: the value
    //! arrives from saved settings, and a face that will not draw is worse than one drawn plainly.
    function apply(theme as Number) as Void {
        if (theme == COBALT) {
            // Blue: a deep navy ground with a genuinely blue ring rather than the blue-grey the
            // project started with. Waiting markets are blue too, which leaves the red of a live
            // session as the only warm thing on the face.
            GROUND_CORE = 0x050A16;
            RING_NIGHT = 0x123058;
            RING_DAY = 0x255E9E;
            RING_TEXT = 0xE6F0FF;
            CLOSED_FROM = 0x1F3C66;
            CLOSED_TO = 0x5E86BE;
            CLOSED = 0x5E86BE;
            ACCENT_HOT = 0xFFB03A;
            HAND = 0xD6E4F7;
            DIM = 0x7391BC;
            TRACK = 0x11223D;
            current = COBALT;

        } else if (theme == EMBER) {
            // Red: a near-black maroon ground under a ring that runs from dark blood to bright
            // ember. The live sessions have to out-shout a warm face, so their gradient reaches
            // further up into orange than it does on the cooler themes.
            GROUND_CORE = 0x110503;
            RING_NIGHT = 0x3E1109;
            RING_DAY = 0x8C2A12;
            RING_TEXT = 0xFFEDE4;
            CLOSED_FROM = 0x46302A;
            CLOSED_TO = 0xA48C80;
            CLOSED = 0xA48C80;
            ACCENT_HOT = 0xFFD98A;
            HAND = 0xF2E2D6;
            DIM = 0xA48C80;
            TRACK = 0x2A1611;
            current = EMBER;

        } else {
            GROUND_CORE = 0x070910;
            RING_NIGHT = 0x2C3854;
            RING_DAY = 0x495C82;
            RING_TEXT = 0xE9EEF8;
            CLOSED_FROM = 0x404A64;
            CLOSED_TO = 0x8B95B1;
            CLOSED = 0x8F97B6;
            ACCENT_HOT = 0xFFB03A;
            HAND = 0xC9D3E4;
            DIM = 0x7E8AA6;
            TRACK = 0x222A3D;
            current = IRON;
        }

        applyOpen(openChoice);
    }

    //! Set the colour a trading session is drawn in.
    //!
    //! Each option has to hold up on all three grounds, so these are brighter than a single theme
    //! would need. Two combinations are still weaker than the rest by their nature — blue sessions
    //! on Cobalt, red on Ember — because a session cannot separate from a ground it matches.
    function applyOpen(choice as Number) as Void {
        if (choice == OPEN_GREEN) {
            OPEN_FROM = 0x1B7A56;
            OPEN_TO = 0x63EDB0;
            OPEN = 0x41C391;
        } else if (choice == OPEN_BLUE) {
            OPEN_FROM = 0x184F9B;
            OPEN_TO = 0x69BCFF;
            OPEN = 0x3D93E8;
        } else if (choice == OPEN_PURPLE) {
            OPEN_FROM = 0x54269B;
            OPEN_TO = 0xC095FF;
            OPEN = 0x9463E6;
        } else {
            OPEN_FROM = 0x9E2318;
            OPEN_TO = 0xFF6B58;
            OPEN = 0xE8503F;
        }

        openChoice = choice < OPEN_COUNT && choice >= 0 ? choice : OPEN_RED;
        generation += 1;
    }

    //! Blend two 0xRRGGBB colours, `amount` running 0.0 at `from` to 1.0 at `to`.
    //!
    //! Channels are mixed separately in sRGB. Interpolating gamma-encoded values is not what a
    //! colour scientist would do, but over the short, low-contrast spans on this face the
    //! difference is invisible, and the honest version costs two pow() calls per segment.
    function mix(from as Number, to as Number, amount as Float) as Number {
        var t = amount;
        if (t < 0.0) {
            t = 0.0;
        } else if (t > 1.0) {
            t = 1.0;
        }

        var fromRed = (from >> 16) & 0xFF;
        var fromGreen = (from >> 8) & 0xFF;
        var fromBlue = from & 0xFF;

        var red = fromRed + ((((to >> 16) & 0xFF) - fromRed) * t).toNumber();
        var green = fromGreen + ((((to >> 8) & 0xFF) - fromGreen) * t).toNumber();
        var blue = fromBlue + (((to & 0xFF) - fromBlue) * t).toNumber();

        return (red << 16) | (green << 8) | blue;
    }
}
