import Toybox.Application;
import Toybox.Lang;

//! Where the two settings are kept, and how they are read back.
//!
//! **This module is `(:glance)` and the menu that edits it is not**, which is the whole reason they
//! are separate files. The app restores the theme in `onStart`, and `onStart` runs in glance mode
//! too — so everything it touches has to exist in the glance build. It did not, once, and the
//! glance crashed with an out-of-bounds before drawing a pixel:
//!
//!     Error: Illegal Access (Out of Bounds)
//!       onStart() at MarketSessionsApp.mc:21
//!
//! Nothing in here may reference WatchUi. The menu lives in SettingsMenu.mc, which the glance never
//! loads and does not need to.
(:glance)
module Settings {

    //! Property keys, also declared in resources/settings/properties.xml, which is what makes them
    //! appear in Garmin Connect.
    const THEME_KEY = "theme";
    const OPEN_KEY = "openColor";

    //! Read both saved settings and make them live. Called at startup — in both modes — and again
    //! whenever the phone pushes a change.
    function restore() as Void {
        Palette.apply(read(THEME_KEY, Palette.IRON));
        Palette.applyOpen(read(OPEN_KEY, Palette.OPEN_RED));
    }

    //! A saved number, or the fallback. A property can be absent on first run, or on a device that
    //! has never synced, and a face that will not draw is worse than one drawn plainly.
    function read(key as String, fallback as Number) as Number {
        var saved = null;
        try {
            saved = Application.Properties.getValue(key);
        } catch (ex) {
            saved = null;
        }
        return saved instanceof Number ? saved : fallback;
    }

    function write(key as String, value as Number) as Void {
        try {
            Application.Properties.setValue(key, value);
        } catch (ex) {
            // Nothing to be done about a device that will not persist it; the choice still applies
            // for this run rather than the press doing visibly nothing.
        }
    }
}
