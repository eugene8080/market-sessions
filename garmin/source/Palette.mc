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
    const CLASSIC = 1;
    const EMBER = 2;
    const THEME_COUNT = 3;

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

    var OPEN_FROM as Number = 0x1F7F5C;         //! a trading session, at its open
    var OPEN_TO as Number = 0x5FE8AC;           //! and at its close
    var CLOSED_FROM as Number = 0x404A64;       //! a market waiting for its next session
    var CLOSED_TO as Number = 0x8B95B1;

    var OPEN as Number = 0x41C391;              //! flat tones, where a fade would be lost:
    var CLOSED as Number = 0x8F97B6;            //! the glance timeline, the hub's rim

    var ACCENT_HOT as Number = 0xF4522F;        //! the hour hand's tip, and nothing else
    var HAND as Number = 0xC9D3E4;

    var DIM as Number = 0x7E8AA6;
    var TRACK as Number = 0x222A3D;

    //! Switch the face to a theme. Out of range falls back to Iron rather than throwing: the value
    //! arrives from saved settings, and a face that will not draw is worse than one drawn plainly.
    function apply(theme as Number) as Void {
        if (theme == CLASSIC) {
            // The palette the project started with: flat bands, no fades, a colder blue ground.
            // Kept because it is what the web app and the widget still wear.
            GROUND_CORE = 0x151821;
            RING_NIGHT = 0x3C4761;
            RING_DAY = 0x3C4761;
            RING_TEXT = 0xEEF1F8;
            OPEN_FROM = 0x41C391;
            OPEN_TO = 0x41C391;
            CLOSED_FROM = 0x8F97B6;
            CLOSED_TO = 0x8F97B6;
            OPEN = 0x41C391;
            CLOSED = 0x8F97B6;
            ACCENT_HOT = 0xEF6A5E;
            HAND = 0xC3CBDF;
            DIM = 0x6F7899;
            TRACK = 0x2A3145;
            current = CLASSIC;

        } else if (theme == EMBER) {
            // Warm: a near-black brown ground and a copper ring. Sessions stay green, because green
            // is the only colour on the face carrying meaning rather than mood, and a theme that
            // recoloured it would be changing the data, not the styling.
            GROUND_CORE = 0x0D0906;
            RING_NIGHT = 0x37281B;
            RING_DAY = 0x5E4229;
            RING_TEXT = 0xF6ECE0;
            OPEN_FROM = 0x1F7F5C;
            OPEN_TO = 0x5FE8AC;
            CLOSED_FROM = 0x4A3B2C;
            CLOSED_TO = 0xA08D75;
            OPEN = 0x41C391;
            CLOSED = 0xA08D75;
            ACCENT_HOT = 0xFF7A2F;
            HAND = 0xEADBC8;
            DIM = 0x9A8877;
            TRACK = 0x2A1F16;
            current = EMBER;

        } else {
            GROUND_CORE = 0x070910;
            RING_NIGHT = 0x2C3854;
            RING_DAY = 0x495C82;
            RING_TEXT = 0xE9EEF8;
            OPEN_FROM = 0x1F7F5C;
            OPEN_TO = 0x5FE8AC;
            CLOSED_FROM = 0x404A64;
            CLOSED_TO = 0x8B95B1;
            OPEN = 0x41C391;
            CLOSED = 0x8F97B6;
            ACCENT_HOT = 0xF4522F;
            HAND = 0xC9D3E4;
            DIM = 0x7E8AA6;
            TRACK = 0x222A3D;
            current = IRON;
        }

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
