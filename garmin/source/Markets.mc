import Toybox.Lang;

//! The exchange table, mirroring `MARKETS` in index.html and `MARKETS` in Markets.kt.
//!
//! Trading hours are the exchange's own regular local trading day, so daylight saving is handled
//! by the zone rule rather than baked into the numbers. Editing a market here changes the glance
//! and the dial together — and has to be mirrored in index.html, android/…/Markets.kt and
//! tools/verify_zones.py, which is what checks the zone rule below is the right one.
//!
//! The convention is the regular cash session: first to last continuous trade. Pre-open and
//! post-close auctions are excluded, so Sydney starts at 10:00 rather than at its 07:00 pre-open.
//! Midday breaks are not modelled — Tokyo, Hong Kong and Shanghai each shut for lunch and are
//! drawn here as trading straight through.
//!
//! The data is held as flat arrays rather than as an array of objects. A glance runs under a hard
//! 64 KB ceiling on this device, and fourteen small objects with four fields each cost far more in
//! headers than fifty-six raw numbers do.
(:glance)
module Markets {

    //! Number of entries in SPEC per market: standard offset, rule, open, close.
    const STRIDE = 4;

    //! Offsets into a market's SPEC slice.
    const FIELD_STANDARD_OFFSET = 0;
    const FIELD_RULE = 1;
    const FIELD_OPEN_MINUTE = 2;
    const FIELD_CLOSE_MINUTE = 3;

    //! Full names, for the dial and the wide glance.
    var NAMES as Array<String> = [
        "Sydney",
        "Tokyo",
        "Singapore",
        "Hong Kong",
        "Shanghai",
        "Mumbai",
        "Frankfurt",
        "London",
        "Zurich",
        "Paris",
        "Amsterdam",
        "Toronto",
        "New York",
        "NASDAQ"
    ] as Array<String>;

    //! Three or four letter codes, for anywhere the full name will not fit.
    var CODES as Array<String> = [
        "SYD",
        "TYO",
        "SGX",
        "HKG",
        "SHA",
        "BSE",
        "FRA",
        "LON",
        "SWX",
        "PAR",
        "AMS",
        "TSX",
        "NYSE",
        "NDQ"
    ] as Array<String>;

    //! Four numbers per market, in NAMES order:
    //!   standard UTC offset in minutes, daylight saving rule, open minute of day, close minute.
    //!
    //! The offset is the zone's *winter* offset; Zones.offsetAt adds the summer hour when the
    //! rule says so. Minutes of day keep the arithmetic in whole numbers throughout.
    var SPEC as Array<Number> = [
        //  offset  rule                open          close
             600,   Zones.RULE_AU,     10 * 60,       16 * 60,        // Sydney       AEST/AEDT
             540,   Zones.RULE_NONE,    9 * 60,       15 * 60 + 30,   // Tokyo        JST
             480,   Zones.RULE_NONE,    9 * 60,       17 * 60,        // Singapore    SGT
             480,   Zones.RULE_NONE,    9 * 60 + 30,  16 * 60,        // Hong Kong    HKT
             480,   Zones.RULE_NONE,    9 * 60 + 30,  15 * 60,        // Shanghai     CST
             330,   Zones.RULE_NONE,    9 * 60 + 15,  15 * 60 + 30,   // Mumbai       IST
              60,   Zones.RULE_EU,      9 * 60,       17 * 60 + 30,   // Frankfurt    CET/CEST
               0,   Zones.RULE_EU,      8 * 60,       16 * 60 + 30,   // London       GMT/BST
              60,   Zones.RULE_EU,      9 * 60,       17 * 60 + 30,   // Zurich       CET/CEST
              60,   Zones.RULE_EU,      9 * 60,       17 * 60 + 30,   // Paris        CET/CEST
              60,   Zones.RULE_EU,      9 * 60,       17 * 60 + 30,   // Amsterdam    CET/CEST
            -300,   Zones.RULE_US,      9 * 60 + 30,  16 * 60,        // Toronto      EST/EDT
            -300,   Zones.RULE_US,      9 * 60 + 30,  16 * 60,        // New York     EST/EDT
            -300,   Zones.RULE_US,      9 * 60 + 30,  16 * 60         // NASDAQ       EST/EDT
    ] as Array<Number>;

    //! How many markets the table holds.
    function count() as Number {
        return NAMES.size();
    }

    //! One field of one market's specification.
    function field(index as Number, which as Number) as Number {
        return SPEC[index * STRIDE + which];
    }
}
