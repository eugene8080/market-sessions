import Toybox.Lang;
import Toybox.WatchUi;

//! Input for the dial.
//!
//! BACK leaves the app, DOWN opens the market list, MENU opens the settings. Anything else is
//! ignored rather than swallowed, so the hardware keeps doing what a tactix owner expects.
class DialDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Returning false lets the system perform its own default action, which for BACK on the
    //! initial view is to exit the app.
    function onBack() as Boolean {
        return false;
    }

    //! DOWN, or a swipe up, opens the list of every market. The dial says what is happening now;
    //! the list says when each session runs and how long until it changes. It cannot live in the
    //! glance — a glance is one non-interactive draw, and the carousel owns up and down there.
    function onNextPage() as Boolean {
        WatchUi.pushView(new MarketList(), new MarketListDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    //! MENU opens the settings menu — theme, and the colour a live session is drawn in. This is
    //! the route that works on a sideloaded app, where the Garmin Connect settings screen may
    //! never appear.
    function onMenu() as Boolean {
        WatchUi.pushView(SettingsMenu.build(), new SettingsMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}
