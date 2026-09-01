import Toybox.Lang;

//! The dial's colours.
//!
//! The web app's flat dark theme came with the design the project started from. This is a
//! deliberate departure: a cold slate ground that deepens towards the centre, a steel hour ring,
//! and a warm amber-to-ember accent kept for the things that move — the hands and the marker.
//! Sessions stay green because green is the only colour on the face carrying meaning rather than
//! mood, and warm accents are reserved so they never compete with it.
//!
//! Connect IQ has no gradient primitive of any kind. Every fade on this dial is drawn as a run of
//! segments with `mix` interpolating between two endpoints, which is why the pairs below are
//! `_FROM` and `_TO` rather than single values.
//!
//! The Solar 51mm variant of the tactix 8 is an 8 bit MIP panel, rendering from a fixed 64 colour
//! palette — every channel snapped to 0x00, 0x55, 0xAA or 0xFF. Fades collapse to bands there and
//! the colours shift; the endpoints below are chosen so they snap apart rather than together, so
//! the face still reads even when the gradient does not survive.
(:glance)
module Palette {

    // -------------------------------------------------------------------------------------
    // Ground
    // -------------------------------------------------------------------------------------

    //! The face darkens towards the middle, which lifts the outer ring away from the centre and
    //! gives the band stack something to sit on.
    const GROUND_EDGE = 0x151D2E;
    const GROUND_CORE = 0x070910;

    // -------------------------------------------------------------------------------------
    // Hour ring
    // -------------------------------------------------------------------------------------

    //! The ring is cool at midnight and warms very slightly towards noon — barely a hint, but it
    //! gives the top of the dial a different weight from the bottom, so a glance at the face tells
    //! you roughly where in the day you are before you have read a single numeral.
    const RING_NIGHT = 0x2C3854;
    const RING_DAY = 0x495C82;
    const RING_TEXT = 0xE9EEF8;

    // -------------------------------------------------------------------------------------
    // Sessions
    // -------------------------------------------------------------------------------------

    //! A trading session, faded along its own arc from the open to the close, so the band carries a
    //! direction of travel rather than sitting there as a flat stripe.
    const OPEN_FROM = 0x1F7F5C;
    const OPEN_TO = 0x5FE8AC;

    //! A market waiting for its next session. Same treatment, far less presence.
    const CLOSED_FROM = 0x404A64;
    const CLOSED_TO = 0x8B95B1;

    //! Single representative tones, for anywhere a fade would be lost — the glance timeline, the
    //! rim of the summary dial.
    const OPEN = 0x41C391;
    const CLOSED = 0x8F97B6;

    // -------------------------------------------------------------------------------------
    // Accents and furniture
    // -------------------------------------------------------------------------------------

    //! Amber into ember. Used only on the hands and the now marker: the moving parts.
    const ACCENT_WARM = 0xFFA24A;
    const ACCENT_HOT = 0xF4522F;

    //! The hour hand, which is steel rather than warm so the two hands never read as one shape.
    const HAND = 0xC9D3E4;
    const HAND_EDGE = 0x767F94;

    const DIM = 0x7E8AA6;
    const TRACK = 0x222A3D;

    // -------------------------------------------------------------------------------------

    //! Blend two 0xRRGGBB colours, `amount` running 0.0 at `from` to 1.0 at `to`.
    //!
    //! Channels are mixed separately in sRGB. Interpolating gamma-encoded values is not what a
    //! colour scientist would do, but over the short, low-contrast spans on this face the
    //! difference is invisible, and the honest version costs two pow() calls per segment on a
    //! watch that redraws fourteen arcs at a time.
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
