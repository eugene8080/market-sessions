import Toybox.Lang;

//! The web app's dark theme, lifted verbatim from the `:root` block in index.html and from
//! `DialRenderer.Palette` on Android, so all three faces of Market Sessions read as one product.
//!
//! The Solar 51mm variant of the tactix 8 is an 8 bit MIP panel. It renders from a fixed 64 colour
//! palette — every channel snapped to 0x00, 0x55, 0xAA or 0xFF — so these values shift there:
//! the open green lands on 0x55AAAA and reads more teal than mint. Contrast survives, which is
//! what the dial actually trades on, and the AMOLED panel gets the web app's colours exactly.
//!
//! Where the snapping would change a colour's *character* rather than its shade, the value is
//! nudged to land where it should. See HAND.
(:glance)
module Palette {
    const OPEN = 0x41C391;          //! a market trading right now
    const CLOSED = 0x8F97B6;        //! a market waiting for its next session
    const DIAL_BG = 0x151821;       //! the clock face
    const RING = 0x3C4761;          //! the hour ring behind the labels
    const RING_TEXT = 0xEEF1F8;     //! hour numerals
    //! The now marker, on the dial and on the glance timeline. The web app's #C3CBDF has a blue
    //! channel of 0xDF, which snaps up to 0xFF on the MIP panel and turns the marker lilac against
    //! an otherwise grey face. Holding the blue below 0xD4 snaps it to a neutral 0xAAAAAA there,
    //! and is indistinguishable from the original on the AMOLED.
    const HAND = 0xC3CBCF;
    const DIM = 0x6F7899;           //! captions and inactive furniture
    const TRACK = 0x2A3145;         //! the unfilled part of the glance timeline
}
