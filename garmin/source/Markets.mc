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
//! **Tokyo and Seoul are one band.** Japan and Korea keep the same offset and the same hours to
//! the minute, so drawn separately they were two concentric arcs of identical extent — the same
//! coincidence that put Toronto, New York and Nasdaq together. What they do not share is a
//! calendar, and the holiday table carries that: the band is shut only when both are, so Japan's
//! holidays leave it open on Korea's account and Korea's leave it open on Japan's.
//!
//! **Europe is one band here and five markets everywhere else.** London, Frankfurt, Zurich, Paris
//! and Amsterdam open and close at the same instant to the second, all year: London trades an hour
//! earlier by its own clock and sits an hour behind CET, and the UK and EU move their clocks
//! together, so the two differences cancel exactly. In a browser they are worth listing separately
//! because their wall clocks differ; on a dial they would be five arcs drawn on top of each other.
//! The band is kept in CET, which four of the five actually use.
//!
//! **North America is one band too**, and for the same reason. Toronto, New York and Nasdaq open
//! and close at the same instant in the same zone — their three rows in SPEC were byte for byte
//! identical — so on a dial they were three arcs drawn on top of each other, indistinguishable and
//! costing three bands of radius. They were kept separate for a while on the grounds that three
//! American venues are worth seeing as three; on a face this size that turned out to buy nothing
//! you could see. Where they genuinely differ is the calendar, and the holiday table keeps that:
//! the band is shut only when all three are, so Canada Day and Thanksgiving each leave it open
//! because the other side of the border is trading.
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
        "Tokyo/Seoul",
        "Taipei",
        "Singapore",
        "Hong Kong",
        "Shanghai",
        "Mumbai",
        "Europe",
        "N.America"
    ] as Array<String>;

    //! Short codes, for anywhere the full name will not fit.
    //!
    //! These are Interactive Brokers' venue codes, not city or IATA codes, because IBKR is where
    //! these markets are actually traded from — a code that matches the exchange column of a
    //! watchlist needs no translating. They are IBKR's own spellings, oddities included: Xetra is
    //! IBIS after the system Deutsche Boerse retired in 1997, Zurich is EBS, Paris is SBF, and
    //! Shanghai A-shares are reached over Stock Connect so they carry the northbound link's code
    //! rather than the exchange's.
    //!
    //! Watch the two Toronto/Tokyo lookalikes: TSE is Toronto and TSEJ is Tokyo.
    var CODES as Array<String> = [
        "ASX",       // Australian Securities Exchange
        "TSEJ/KSE",  // Tokyo Stock Exchange and Korea Exchange — one session, see below
        "TWSE",      // Taiwan Stock Exchange
        "SGX",       // Singapore Exchange
        "SEHK",      // Stock Exchange of Hong Kong
        "SEHKNTL",   // Shanghai A-shares, over Stock Connect northbound
        "NSE",       // National Stock Exchange of India
        "EUR",       // LSE, IBIS, EBS, SBF and AEB — one session, see below
        "AMER"       // TSE, NYSE and NASDAQ — one session, see below
    ] as Array<String>;

    //! Four numbers per market, in NAMES order:
    //!   standard UTC offset in minutes, daylight saving rule, open minute of day, close minute.
    //!
    //! The offset is the zone's *winter* offset; Zones.offsetAt adds the summer hour when the
    //! rule says so. Minutes of day keep the arithmetic in whole numbers throughout.
    var SPEC as Array<Number> = [
        //  offset  rule                open          close
             600,   Zones.RULE_AU,     10 * 60,       16 * 60,        // Sydney       AEST/AEDT
             540,   Zones.RULE_NONE,    9 * 60,       15 * 60 + 30,   // Tokyo/Seoul  JST=KST
             480,   Zones.RULE_NONE,    9 * 60,       13 * 60 + 30,   // Taipei       CST (no DST)
             480,   Zones.RULE_NONE,    9 * 60,       17 * 60,        // Singapore    SGT
             480,   Zones.RULE_NONE,    9 * 60 + 30,  16 * 60,        // Hong Kong    HKT
             480,   Zones.RULE_NONE,    9 * 60 + 30,  15 * 60,        // Shanghai     CST
             330,   Zones.RULE_NONE,    9 * 60 + 15,  15 * 60 + 30,   // Mumbai       IST
              60,   Zones.RULE_EU,      9 * 60,       17 * 60 + 30,   // Europe       CET/CEST
            -300,   Zones.RULE_US,      9 * 60 + 30,  16 * 60         // N. America   EST/EDT
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
