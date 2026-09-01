import Toybox.Lang;
import Toybox.WatchUi;

//! Input for the dial.
//!
//! The dial has nothing to drill into, so this exists to keep the hardware buttons doing what a
//! tactix owner expects: BACK leaves the app, everything else is ignored rather than swallowed.
class DialDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Returning false lets the system perform its own default action, which for BACK on the
    //! initial view is to exit the app.
    function onBack() as Boolean {
        return false;
    }

    //! MENU opens the theme picker. This is the route that works on a sideloaded app, where the
    //! Garmin Connect settings screen may never appear.
    function onMenu() as Boolean {
        WatchUi.pushView(ThemeMenu.build(), new ThemeMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}
